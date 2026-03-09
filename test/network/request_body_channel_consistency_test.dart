import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/dio_adapter.dart';
import 'package:flutter_rust_net/network/net_feature_flag.dart';
import 'package:flutter_rust_net/network/net_models.dart';
import 'package:flutter_rust_net/network/network_gateway.dart';
import 'package:flutter_rust_net/network/routing_policy.dart';
import 'package:flutter_rust_net/network/rust_adapter.dart';
import 'package:flutter_rust_net/network/rust_bridge_api.dart';
import 'package:flutter_rust_net/rust_bridge/api.dart' as rust_api;

void main() {
  group('request body channel consistency', () {
    test(
      'map body without content-type stays aligned when rust falls back to dio',
      () async {
        final capture = await _exerciseFallback(
          body: const <String, Object?>{'ok': true, 'count': 1},
        );

        expect(capture.response.channel, NetChannel.dio);
        expect(capture.response.fromFallback, isTrue);
        expect(capture.response.routeReason, 'force_channel -> fallback_dio');
        expect(capture.rustSpec.bodyBytes, isNotNull);
        expect(
          capture.dioRequest.bodyBytes,
          capture.rustSpec.bodyBytes!.toList(growable: false),
        );
        expect(
          utf8.decode(capture.dioRequest.bodyBytes),
          '{"ok":true,"count":1}',
        );
        expect(capture.dioRequest.contentType, isNull);
        expect(_headerValue(capture.rustSpec.headers, 'content-type'), isNull);
      },
    );

    test('raw byte payload stays aligned when rust falls back to dio',
        () async {
      final capture = await _exerciseFallback(
        body: <int>[65, 66, 67, 0, 255],
      );

      expect(capture.rustSpec.bodyBytes, isNotNull);
      expect(
        capture.dioRequest.bodyBytes,
        capture.rustSpec.bodyBytes!.toList(growable: false),
      );
      expect(capture.dioRequest.bodyBytes, [65, 66, 67, 0, 255]);
      expect(capture.dioRequest.contentType, isNull);
      expect(_headerValue(capture.rustSpec.headers, 'content-type'), isNull);
    });
  });
}

Future<_FallbackCapture> _exerciseFallback({required Object body}) async {
  final requestCompleter = Completer<_RecordedRequest>();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final bodyBytes = await _readAll(request);
    requestCompleter.complete(
      _RecordedRequest(
        bodyBytes: bodyBytes,
        contentType: request.headers.value(HttpHeaders.contentTypeHeader),
      ),
    );
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.add(utf8.encode('{}'));
    await request.response.close();
  });

  try {
    final bridge = _CapturingRustBridgeApi();
    final rustAdapter = RustAdapter(bridgeApi: bridge);
    await rustAdapter.initializeEngine();

    final gateway = NetworkGateway(
      routingPolicy: const RoutingPolicy(),
      featureFlag: const NetFeatureFlag(
        enableRustChannel: true,
        enableFallback: true,
      ),
      dioAdapter: DioAdapter(),
      rustAdapter: rustAdapter,
    );

    final response = await gateway.request(
      NetRequest(
        method: 'PUT',
        url: 'http://${server.address.address}:${server.port}/echo',
        headers: const {'x-trace-id': 'trace-1'},
        body: body,
        forceChannel: NetChannel.rust,
      ),
    );
    final dioRequest = await requestCompleter.future.timeout(
      const Duration(seconds: 3),
    );
    final rustSpec = bridge.lastRequestSpec;
    expect(rustSpec, isNotNull);
    expect(_headerValue(rustSpec!.headers, 'x-trace-id'), 'trace-1');

    return _FallbackCapture(
      response: response,
      rustSpec: rustSpec,
      dioRequest: dioRequest,
    );
  } finally {
    await server.close(force: true);
  }
}

Future<List<int>> _readAll(HttpRequest request) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in request) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

String? _headerValue(List<(String, String)> headers, String name) {
  final lowerName = name.toLowerCase();
  for (final header in headers) {
    if (header.$1.toLowerCase() == lowerName) {
      return header.$2;
    }
  }
  return null;
}

class _FallbackCapture {
  final NetResponse response;
  final rust_api.RequestSpec rustSpec;
  final _RecordedRequest dioRequest;

  const _FallbackCapture({
    required this.response,
    required this.rustSpec,
    required this.dioRequest,
  });
}

class _RecordedRequest {
  final List<int> bodyBytes;
  final String? contentType;

  const _RecordedRequest({
    required this.bodyBytes,
    required this.contentType,
  });
}

class _CapturingRustBridgeApi implements RustBridgeApi {
  rust_api.RequestSpec? lastRequestSpec;

  @override
  Future<void> ensureBridgeLoaded() async {}

  @override
  Future<void> initNetEngine({
    required rust_api.NetEngineConfig config,
  }) async {}

  @override
  Future<rust_api.ResponseMeta> request({
    required rust_api.RequestSpec spec,
  }) async {
    lastRequestSpec = spec;
    return rust_api.ResponseMeta(
      requestId: spec.requestId,
      statusCode: 0,
      headers: const [],
      bodyInline: null,
      bodyFilePath: null,
      fromCache: false,
      costMs: 1,
      error: 'timeout: simulated rust timeout',
    );
  }

  @override
  Future<String> startTransferTask({
    required rust_api.TransferTaskSpec spec,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<rust_api.NetEvent>> pollEvents({required int limit}) {
    throw UnimplementedError();
  }

  @override
  Future<bool> cancel({required String id}) {
    throw UnimplementedError();
  }

  @override
  Future<int> clearCache({String? namespace}) {
    throw UnimplementedError();
  }
}
