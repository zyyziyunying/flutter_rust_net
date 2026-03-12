import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/net_models.dart';
import 'package:flutter_rust_net/network/rust_adapter.dart';
import 'package:flutter_rust_net/rust_bridge/api.dart' as rust_api;

import 'fake_rust_bridge_api.dart';

void main() {
  group('RustAdapter request path', () {
    test('rejects initialized constructor flag for bridge-backed adapters', () {
      expect(
        () => RustAdapter(initialized: true, bridgeApi: FakeRustBridgeApi()),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('Use initializeEngine()'),
          ),
        ),
      );
    });

    test('rejects markInitialized for bridge-backed adapters', () {
      final adapter = RustAdapter(bridgeApi: FakeRustBridgeApi());

      expect(
        () => adapter.markInitialized(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('requestHandler-backed adapters'),
          ),
        ),
      );
    });

    test('throws infrastructure error before initialization', () async {
      final adapter = RustAdapter(bridgeApi: FakeRustBridgeApi());

      expect(
        adapter.request(const NetRequest(method: 'GET', url: 'https://a.com')),
        throwsA(
          isA<NetException>()
              .having(
                (error) => error.code,
                'code',
                NetErrorCode.infrastructure,
              )
              .having(
                (error) => error.fallbackEligible,
                'fallbackEligible',
                isTrue,
              )
              .having(
                (error) => error.message,
                'message',
                contains('RustAdapter.initializeEngine()'),
              ),
        ),
      );
    });

    test('initializes and maps rust success response', () async {
      final fakeBridge = FakeRustBridgeApi(
        requestResponder: (spec) async {
          expect(spec.path, 'https://example.com/todos/1');
          expect(spec.query, contains(('lang', 'en')));
          expect(spec.query, contains(('limit', '10')));
          return rust_api.ResponseMeta(
            requestId: spec.requestId,
            statusCode: 200,
            headers: const [('content-type', 'application/json')],
            bodyInline: Uint8List.fromList(const [123, 125]),
            bodyFilePath: null,
            fromCache: false,
            costMs: 9,
            error: null,
          );
        },
      );
      final adapter = RustAdapter(bridgeApi: fakeBridge);

      await adapter.initializeEngine();
      expect(fakeBridge.lastInitConfig?.maxInFlightTasks, 32);
      final response = await adapter.request(
        const NetRequest(
          method: 'GET',
          url: 'https://example.com/todos/1?lang=en',
          queryParameters: {'limit': 10},
        ),
      );

      expect(fakeBridge.ensureLoadedCalls, 2);
      expect(fakeBridge.initCalls, 1);
      expect(response.statusCode, 200);
      expect(response.channel, NetChannel.rust);
      expect(response.bodyBytes, isNotNull);
      expect(response.fromFallback, isFalse);
      expect(response.requestId, isNotNull);
      expect(response.requestId, isNotEmpty);
    });

    test('passes cache policy options to rust init config', () async {
      final fakeBridge = FakeRustBridgeApi();
      final adapter = RustAdapter(bridgeApi: fakeBridge);

      await adapter.initializeEngine(
        options: const RustEngineInitOptions(
          cacheDefaultTtlSeconds: 12,
          cacheMaxNamespaceBytes: 4096,
        ),
      );

      final config = fakeBridge.lastInitConfig;
      expect(config, isNotNull);
      expect(config!.cacheDefaultTtlSeconds, 12);
      expect(config.cacheMaxNamespaceBytes, 4096);
    });

    test('maps rust fromCache flag into net response', () async {
      final fakeBridge = FakeRustBridgeApi(
        requestResponder: (spec) async {
          return rust_api.ResponseMeta(
            requestId: spec.requestId,
            statusCode: 200,
            headers: const [('content-type', 'application/json')],
            bodyInline: Uint8List.fromList(const [123, 125]),
            bodyFilePath: null,
            fromCache: true,
            costMs: 2,
            error: null,
          );
        },
      );
      final adapter = RustAdapter(bridgeApi: fakeBridge);
      await adapter.initializeEngine();

      final response = await adapter.request(
        const NetRequest(method: 'GET', url: 'https://example.com/cache'),
      );

      expect(response.channel, NetChannel.rust);
      expect(response.fromCache, isTrue);
    });

    test(
      'forwards expectLargeResponse and keeps normal request priority',
      () async {
        final fakeBridge = FakeRustBridgeApi(
          requestResponder: (spec) async {
            expect(spec.expectLargeResponse, isTrue);
            expect(spec.priority, 1);
            return rust_api.ResponseMeta(
              requestId: spec.requestId,
              statusCode: 200,
              headers: const [('content-type', 'application/octet-stream')],
              bodyInline: Uint8List.fromList(const [1, 2, 3]),
              bodyFilePath: null,
              fromCache: false,
              costMs: 3,
              error: null,
            );
          },
        );
        final adapter = RustAdapter(bridgeApi: fakeBridge);
        await adapter.initializeEngine();

        final response = await adapter.request(
          const NetRequest(
            method: 'GET',
            url: 'https://example.com/large.bin',
            expectLargeResponse: true,
          ),
        );

        expect(response.channel, NetChannel.rust);
        expect(response.statusCode, 200);
      },
    );

    test('maps typed rust timeout error as fallback eligible', () async {
      final fakeBridge = FakeRustBridgeApi(
        requestResponder: (spec) async {
          return rust_api.ResponseMeta(
            requestId: spec.requestId,
            statusCode: 0,
            headers: const [],
            bodyInline: null,
            bodyFilePath: null,
            fromCache: false,
            costMs: 1,
            errorKind: rust_api.NetErrorKind.timeout,
            error: 'request timeout',
          );
        },
      );
      final adapter = RustAdapter(bridgeApi: fakeBridge);
      await adapter.initializeEngine();

      expect(
        adapter.request(const NetRequest(method: 'GET', url: 'https://a.com')),
        throwsA(
          isA<NetException>()
              .having((error) => error.code, 'code', NetErrorCode.timeout)
              .having(
                (error) => error.fallbackEligible,
                'fallbackEligible',
                isTrue,
              )
              .having((error) => error.requestId, 'requestId', isNotNull),
        ),
      );
    });

    test('maps typed rust http error with status code', () async {
      final fakeBridge = FakeRustBridgeApi(
        requestResponder: (spec) async {
          return rust_api.ResponseMeta(
            requestId: spec.requestId,
            statusCode: 429,
            headers: const [],
            bodyInline: null,
            bodyFilePath: null,
            fromCache: false,
            costMs: 1,
            errorKind: rust_api.NetErrorKind.http4Xx,
            error: 'upstream rate limit reached',
          );
        },
      );
      final adapter = RustAdapter(bridgeApi: fakeBridge);
      await adapter.initializeEngine();

      expect(
        adapter.request(const NetRequest(method: 'GET', url: 'https://a.com')),
        throwsA(
          isA<NetException>()
              .having((error) => error.code, 'code', NetErrorCode.http4xx)
              .having((error) => error.statusCode, 'statusCode', 429)
              .having(
                (error) => error.fallbackEligible,
                'fallbackEligible',
                isFalse,
              )
              .having((error) => error.requestId, 'requestId', isNotNull),
        ),
      );
    });

    test('maps typed rust internal error as non-fallback internal', () async {
      final fakeBridge = FakeRustBridgeApi(
        requestResponder: (spec) async {
          return rust_api.ResponseMeta(
            requestId: spec.requestId,
            statusCode: 0,
            headers: const [],
            bodyInline: null,
            bodyFilePath: null,
            fromCache: false,
            costMs: 1,
            errorKind: rust_api.NetErrorKind.internal,
            error: 'scheduler closed',
          );
        },
      );
      final adapter = RustAdapter(bridgeApi: fakeBridge);
      await adapter.initializeEngine();

      expect(
        adapter.request(const NetRequest(method: 'GET', url: 'https://a.com')),
        throwsA(
          isA<NetException>()
              .having((error) => error.code, 'code', NetErrorCode.internal)
              .having(
                (error) => error.fallbackEligible,
                'fallbackEligible',
                isFalse,
              )
              .having((error) => error.requestId, 'requestId', isNotNull),
        ),
      );
    });

    test(
      'keeps legacy string-prefix mapping as compatibility fallback',
      () async {
        final fakeBridge = FakeRustBridgeApi(
          requestResponder: (spec) async {
            return rust_api.ResponseMeta(
              requestId: spec.requestId,
              statusCode: 0,
              headers: const [],
              bodyInline: null,
              bodyFilePath: null,
              fromCache: false,
              costMs: 1,
              error: 'dns: lookup failed',
            );
          },
        );
        final adapter = RustAdapter(bridgeApi: fakeBridge);
        await adapter.initializeEngine();

        expect(
          adapter.request(
            const NetRequest(method: 'GET', url: 'https://a.com'),
          ),
          throwsA(
            isA<NetException>()
                .having((error) => error.code, 'code', NetErrorCode.dns)
                .having(
                  (error) => error.fallbackEligible,
                  'fallbackEligible',
                  isTrue,
                )
                .having((error) => error.requestId, 'requestId', isNotNull),
          ),
        );
      },
    );

    test('maps unknown rust error as non-fallback internal', () async {
      final fakeBridge = FakeRustBridgeApi(
        requestResponder: (spec) async {
          return rust_api.ResponseMeta(
            requestId: spec.requestId,
            statusCode: 0,
            headers: const [],
            bodyInline: null,
            bodyFilePath: null,
            fromCache: false,
            costMs: 1,
            error: 'panic: unexpected bridge state',
          );
        },
      );
      final adapter = RustAdapter(bridgeApi: fakeBridge);
      await adapter.initializeEngine();

      expect(
        adapter.request(const NetRequest(method: 'GET', url: 'https://a.com')),
        throwsA(
          isA<NetException>()
              .having((error) => error.code, 'code', NetErrorCode.internal)
              .having(
                (error) => error.fallbackEligible,
                'fallbackEligible',
                isFalse,
              )
              .having((error) => error.requestId, 'requestId', isNotNull),
        ),
      );
    });
  });
}
