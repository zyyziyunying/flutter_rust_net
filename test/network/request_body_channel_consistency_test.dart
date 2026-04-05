import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/dio_adapter.dart';
import 'package:flutter_rust_net/network/net_adapter.dart';
import 'package:flutter_rust_net/network/net_models.dart';
import 'package:flutter_rust_net/network/rhttp_adapter.dart';

void main() {
  final realRhttpSkip = _realRhttpSkipReason();

  group('request body channel consistency', () {
    test(
      'map body without content-type stays aligned between dio and rhttp',
      () async {
        final dioCapture = await _exerciseAdapter(
          DioAdapter(),
          body: const <String, Object?>{'ok': true, 'count': 1},
        );
        final rhttpCapture = await _exerciseRhttpAdapter(
          body: const <String, Object?>{'ok': true, 'count': 1},
        );

        expect(dioCapture.response.channel, NetChannel.dio);
        expect(rhttpCapture.response.channel, NetChannel.rust);
        expect(dioCapture.request.bodyBytes, rhttpCapture.request.bodyBytes);
        expect(
          utf8.decode(rhttpCapture.request.bodyBytes),
          '{"ok":true,"count":1}',
        );
        expect(dioCapture.request.contentType, isNull);
        expect(rhttpCapture.request.contentType, isNull);
      },
    );

    test('json int array body stays aligned between dio and rhttp', () async {
      final dioCapture = await _exerciseAdapter(
        DioAdapter(),
        body: <int>[1, 2, 256, -1],
      );
      final rhttpCapture = await _exerciseRhttpAdapter(
        body: <int>[1, 2, 256, -1],
      );

      expect(dioCapture.request.bodyBytes, rhttpCapture.request.bodyBytes);
      expect(utf8.decode(rhttpCapture.request.bodyBytes), '[1,2,256,-1]');
      expect(dioCapture.request.contentType, isNull);
      expect(rhttpCapture.request.contentType, isNull);
    });

    test('raw byte payload stays aligned between dio and rhttp', () async {
      final dioCapture = await _exerciseAdapter(
        DioAdapter(),
        bodyBytes: const <int>[65, 66, 67, 0, 255],
      );
      final rhttpCapture = await _exerciseRhttpAdapter(
        bodyBytes: const <int>[65, 66, 67, 0, 255],
      );

      expect(dioCapture.request.bodyBytes, rhttpCapture.request.bodyBytes);
      expect(rhttpCapture.request.bodyBytes, [65, 66, 67, 0, 255]);
      expect(dioCapture.request.contentType, isNull);
      expect(rhttpCapture.request.contentType, isNull);
    });

    test(
      'explicit content-type header stays aligned between dio and rhttp',
      () async {
        final headers = const {
          'x-trace-id': 'trace-1',
          'content-type': 'application/vnd.api+json',
        };
        final dioCapture = await _exerciseAdapter(
          DioAdapter(),
          headers: headers,
          body: const <String, Object?>{'ok': true},
        );
        final rhttpCapture = await _exerciseRhttpAdapter(
          headers: headers,
          body: const <String, Object?>{'ok': true},
        );

        expect(dioCapture.request.bodyBytes, rhttpCapture.request.bodyBytes);
        expect(dioCapture.request.contentType, 'application/vnd.api+json');
        expect(rhttpCapture.request.contentType, 'application/vnd.api+json');
      },
    );
  });

  group('request body channel consistency with real rhttp', () {
    test('map body without content-type stays aligned on wire', () async {
      final dioCapture = await _exerciseAdapter(
        DioAdapter(),
        body: const <String, Object?>{'ok': true, 'count': 1},
      );
      final rhttpCapture = await _exerciseAdapter(
        RhttpAdapter(),
        body: const <String, Object?>{'ok': true, 'count': 1},
      );

      expect(dioCapture.response.channel, NetChannel.dio);
      expect(rhttpCapture.response.channel, NetChannel.rust);
      expect(dioCapture.request.bodyBytes, rhttpCapture.request.bodyBytes);
      expect(
        utf8.decode(rhttpCapture.request.bodyBytes),
        '{"ok":true,"count":1}',
      );
      expect(dioCapture.request.contentType, isNull);
      expect(rhttpCapture.request.contentType, isNull);
    }, skip: realRhttpSkip);

    test('json int array body stays aligned on wire', () async {
      final dioCapture = await _exerciseAdapter(
        DioAdapter(),
        body: <int>[1, 2, 256, -1],
      );
      final rhttpCapture = await _exerciseAdapter(
        RhttpAdapter(),
        body: <int>[1, 2, 256, -1],
      );

      expect(dioCapture.request.bodyBytes, rhttpCapture.request.bodyBytes);
      expect(utf8.decode(rhttpCapture.request.bodyBytes), '[1,2,256,-1]');
      expect(dioCapture.request.contentType, isNull);
      expect(rhttpCapture.request.contentType, isNull);
    }, skip: realRhttpSkip);

    test('raw byte payload stays aligned on wire', () async {
      final dioCapture = await _exerciseAdapter(
        DioAdapter(),
        bodyBytes: const <int>[65, 66, 67, 0, 255],
      );
      final rhttpCapture = await _exerciseAdapter(
        RhttpAdapter(),
        bodyBytes: const <int>[65, 66, 67, 0, 255],
      );

      expect(dioCapture.request.bodyBytes, rhttpCapture.request.bodyBytes);
      expect(rhttpCapture.request.bodyBytes, [65, 66, 67, 0, 255]);
      expect(dioCapture.request.contentType, isNull);
      expect(rhttpCapture.request.contentType, isNull);
    }, skip: realRhttpSkip);

    test('explicit content-type header stays aligned on wire', () async {
      final headers = const {
        'x-trace-id': 'trace-1',
        'content-type': 'application/vnd.api+json',
      };
      final dioCapture = await _exerciseAdapter(
        DioAdapter(),
        headers: headers,
        body: const <String, Object?>{'ok': true},
      );
      final rhttpCapture = await _exerciseAdapter(
        RhttpAdapter(),
        headers: headers,
        body: const <String, Object?>{'ok': true},
      );

      expect(dioCapture.request.bodyBytes, rhttpCapture.request.bodyBytes);
      expect(dioCapture.request.contentType, 'application/vnd.api+json');
      expect(rhttpCapture.request.contentType, 'application/vnd.api+json');
    }, skip: realRhttpSkip);
  });
}

Future<_AdapterCapture> _exerciseAdapter(
  NetAdapter adapter, {
  Map<String, String> headers = const {'x-trace-id': 'trace-1'},
  Object? body,
  List<int>? bodyBytes,
}) async {
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
    final response = await adapter.request(
      NetRequest(
        method: 'PUT',
        url: 'http://${server.address.address}:${server.port}/echo',
        headers: headers,
        body: body,
        bodyBytes: bodyBytes,
      ),
    );
    final recorded = await requestCompleter.future.timeout(
      const Duration(seconds: 3),
    );
    return _AdapterCapture(response: response, request: recorded);
  } finally {
    await server.close(force: true);
  }
}

Future<_AdapterCapture> _exerciseRhttpAdapter({
  Map<String, String> headers = const {'x-trace-id': 'trace-1'},
  Object? body,
  List<int>? bodyBytes,
}) async {
  late RhttpAdapterRequest capturedRequest;
  final adapter = RhttpAdapter(
    requestHandler: (request) async {
      capturedRequest = request;
      return RhttpAdapterResponse(
        statusCode: HttpStatus.ok,
        headers: const [('content-type', 'application/json')],
        bodyBytes: Uint8List.fromList(const [123, 125]),
      );
    },
  );

  final response = await adapter.request(
    NetRequest(
      method: 'PUT',
      url: 'https://example.com/echo',
      headers: headers,
      body: body,
      bodyBytes: bodyBytes,
    ),
  );

  return _AdapterCapture(
    response: response,
    request: _RecordedRequest(
      bodyBytes: capturedRequest.bodyBytes?.toList(growable: false) ?? const [],
      contentType: capturedRequest.headers[HttpHeaders.contentTypeHeader],
    ),
  );
}

Future<List<int>> _readAll(HttpRequest request) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in request) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

class _AdapterCapture {
  final NetResponse response;
  final _RecordedRequest request;

  const _AdapterCapture({required this.response, required this.request});
}

class _RecordedRequest {
  final List<int> bodyBytes;
  final String? contentType;

  const _RecordedRequest({required this.bodyBytes, required this.contentType});
}

String? _realRhttpSkipReason() {
  final nativeLibDir =
      Platform.environment['FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR'];
  if (nativeLibDir == null || nativeLibDir.isEmpty) {
    return 'Set the native rhttp library directory via FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR to run opt-in real-rhttp tests.';
  }
  final nativeLib = File('$nativeLibDir/librhttp.dylib');
  if (!nativeLib.existsSync()) {
    return 'Missing librhttp.dylib under the configured native rhttp library directory: $nativeLibDir';
  }
  return null;
}
