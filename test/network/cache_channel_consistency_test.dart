import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/dio_adapter.dart';
import 'package:flutter_rust_net/network/net_adapter.dart';
import 'package:flutter_rust_net/network/net_feature_flag.dart';
import 'package:flutter_rust_net/network/net_models.dart';
import 'package:flutter_rust_net/network/network_gateway.dart';
import 'package:flutter_rust_net/network/routing_policy.dart';

void main() {
  group('cache channel consistency', () {
    late HttpServer server;
    late String baseUrl;
    late DioAdapter dioAdapter;
    late _RustCacheHarnessAdapter rustAdapter;
    late NetworkGateway gateway;
    final requestHitsByKey = <String, int>{};

    setUpAll(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUrl = 'http://${server.address.address}:${server.port}';

      server.listen((request) async {
        final key = request.uri.queryParameters['key'] ?? 'default';
        final cacheMode = request.uri.queryParameters['cache'] ?? 'off';
        final hits = (requestHitsByKey[key] ?? 0) + 1;
        requestHitsByKey[key] = hits;

        final payload = utf8.encode(
          jsonEncode({'key': key, 'cache': cacheMode, 'hit': hits, 'ok': true}),
        );

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        if (cacheMode == 'on') {
          request.response.headers.set(
            HttpHeaders.cacheControlHeader,
            'max-age=120',
          );
        }
        request.response.add(payload);
        await request.response.close();
      });

      dioAdapter = DioAdapter();
      rustAdapter = _RustCacheHarnessAdapter(networkAdapter: DioAdapter());
      gateway = NetworkGateway(
        routingPolicy: const RoutingPolicy(),
        featureFlag: const NetFeatureFlag(
          enableRustChannel: true,
          enableFallback: false,
        ),
        dioAdapter: dioAdapter,
        rustAdapter: rustAdapter,
      );
    });

    tearDownAll(() async {
      await server.close(force: true);
    });

    setUp(() {
      requestHitsByKey.clear();
      rustAdapter.clearCache();
    });

    test('cache-off keeps dio and rust request semantics aligned', () async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final dioKey = 'dio_off_$suffix';
      final rustKey = 'rust_off_$suffix';
      final cacheControl = <String, String>{
        HttpHeaders.cacheControlHeader: 'no-store',
      };

      final dio1 = await _sendAndDecode(
        gateway: gateway,
        baseUrl: baseUrl,
        key: dioKey,
        cacheMode: 'off',
        channel: NetChannel.dio,
        headers: cacheControl,
      );
      final dio2 = await _sendAndDecode(
        gateway: gateway,
        baseUrl: baseUrl,
        key: dioKey,
        cacheMode: 'off',
        channel: NetChannel.dio,
        headers: cacheControl,
      );
      final rust1 = await _sendAndDecode(
        gateway: gateway,
        baseUrl: baseUrl,
        key: rustKey,
        cacheMode: 'off',
        channel: NetChannel.rust,
        headers: cacheControl,
      );
      final rust2 = await _sendAndDecode(
        gateway: gateway,
        baseUrl: baseUrl,
        key: rustKey,
        cacheMode: 'off',
        channel: NetChannel.rust,
        headers: cacheControl,
      );

      expect([dio1.hitCount, dio2.hitCount], [1, 2]);
      expect([rust1.hitCount, rust2.hitCount], [1, 2]);
      expect(rust1.response.fromCache, isFalse);
      expect(rust2.response.fromCache, isFalse);
      expect(requestHitsByKey[dioKey], 2);
      expect(requestHitsByKey[rustKey], 2);
      expect(dio1.cacheMode, 'off');
      expect(rust1.cacheMode, 'off');
    });

    test(
      'cache-on keeps response contract aligned and rust serves second hit from cache',
      () async {
        final suffix = DateTime.now().microsecondsSinceEpoch.toString();
        final dioKey = 'dio_on_$suffix';
        final rustKey = 'rust_on_$suffix';

        final dio1 = await _sendAndDecode(
          gateway: gateway,
          baseUrl: baseUrl,
          key: dioKey,
          cacheMode: 'on',
          channel: NetChannel.dio,
        );
        final dio2 = await _sendAndDecode(
          gateway: gateway,
          baseUrl: baseUrl,
          key: dioKey,
          cacheMode: 'on',
          channel: NetChannel.dio,
        );
        final rust1 = await _sendAndDecode(
          gateway: gateway,
          baseUrl: baseUrl,
          key: rustKey,
          cacheMode: 'on',
          channel: NetChannel.rust,
        );
        final rust2 = await _sendAndDecode(
          gateway: gateway,
          baseUrl: baseUrl,
          key: rustKey,
          cacheMode: 'on',
          channel: NetChannel.rust,
        );

        expect(dio1.response.statusCode, HttpStatus.ok);
        expect(rust1.response.statusCode, dio1.response.statusCode);
        expect([dio1.hitCount, dio2.hitCount], [1, 2]);
        expect([rust1.hitCount, rust2.hitCount], [1, 1]);
        expect(rust1.response.fromCache, isFalse);
        expect(rust2.response.fromCache, isTrue);
        expect(requestHitsByKey[dioKey], 2);
        expect(requestHitsByKey[rustKey], 1);
        expect(dio1.cacheMode, 'on');
        expect(rust1.cacheMode, dio1.cacheMode);
      },
    );
  });
}

Future<_DecodedResponse> _sendAndDecode({
  required NetworkGateway gateway,
  required String baseUrl,
  required String key,
  required String cacheMode,
  required NetChannel channel,
  Map<String, String> headers = const {},
}) async {
  final response = await gateway.request(
    NetRequest(
      method: 'GET',
      url: '$baseUrl/cache?key=$key&cache=$cacheMode',
      headers: headers,
      forceChannel: channel,
    ),
  );
  final bodyBytes = response.bodyBytes ?? const <int>[];
  final payload = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;
  return _DecodedResponse(
    response: response,
    hitCount: payload['hit'] as int,
    cacheMode: payload['cache'] as String,
  );
}

class _DecodedResponse {
  final NetResponse response;
  final int hitCount;
  final String cacheMode;

  const _DecodedResponse({
    required this.response,
    required this.hitCount,
    required this.cacheMode,
  });
}

class _RustCacheHarnessAdapter implements NetAdapter {
  final DioAdapter _networkAdapter;
  final Map<String, NetResponse> _cache = <String, NetResponse>{};

  _RustCacheHarnessAdapter({required DioAdapter networkAdapter})
    : _networkAdapter = networkAdapter;

  @override
  bool get isReady => true;

  void clearCache() {
    _cache.clear();
  }

  @override
  Future<NetResponse> request(
    NetRequest request, {
    bool fromFallback = false,
  }) async {
    final cacheEnabled = !_requestDisablesCache(request.headers);
    final cacheKey = '${request.method.toUpperCase()} ${request.url}';

    if (cacheEnabled) {
      final cached = _cache[cacheKey];
      if (cached != null) {
        return cached.withMeta(fromCache: true, fromFallback: fromFallback);
      }
    }

    final networkResponse = await _networkAdapter.request(
      request,
      fromFallback: fromFallback,
    );
    final rustResponse = networkResponse.withMeta(
      channel: NetChannel.rust,
      fromCache: false,
      fromFallback: fromFallback,
    );

    if (cacheEnabled && _responseCanBeCached(rustResponse.headers)) {
      _cache[cacheKey] = rustResponse;
    }
    return rustResponse;
  }

  @override
  Future<String> startTransferTask(NetTransferTaskRequest request) {
    throw UnsupportedError('transfer not implemented in cache harness');
  }

  @override
  Future<List<NetTransferEvent>> pollTransferEvents({int limit = 64}) async {
    return const <NetTransferEvent>[];
  }

  @override
  Future<bool> cancelTransferTask(String taskId) async {
    return false;
  }

  bool _requestDisablesCache(Map<String, String> headers) {
    final cacheControl = _headerValue(headers, HttpHeaders.cacheControlHeader);
    final pragma = _headerValue(headers, 'pragma');

    if (cacheControl.contains('no-cache') ||
        cacheControl.contains('no-store')) {
      return true;
    }
    return pragma.contains('no-cache');
  }

  bool _responseCanBeCached(Map<String, String> headers) {
    final cacheControl = _headerValue(headers, HttpHeaders.cacheControlHeader);
    if (cacheControl.contains('no-store')) {
      return false;
    }
    final match = RegExp(r'max-age=(\d+)').firstMatch(cacheControl);
    if (match == null) {
      return false;
    }
    return int.tryParse(match.group(1) ?? '') != null;
  }

  String _headerValue(Map<String, String> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) {
        return entry.value.toLowerCase();
      }
    }
    return '';
  }
}
