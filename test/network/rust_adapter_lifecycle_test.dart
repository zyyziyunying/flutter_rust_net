import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/net_models.dart';
import 'package:flutter_rust_net/network/rust_adapter.dart';
import 'package:flutter_rust_net/network/rust_bridge_api.dart';
import 'package:flutter_rust_net/rust_bridge/api.dart' as rust_api;

void main() {
  group('RustAdapter lifecycle', () {
    test('shutdown invalidates adapter readiness and request path', () async {
      final bridge = _LifecycleFakeRustBridgeApi();
      final adapter = RustAdapter(bridgeApi: bridge);

      await adapter.initializeEngine();
      expect(adapter.isReady, isTrue);

      await adapter.shutdownEngine();

      expect(adapter.isReady, isFalse);
      expect(bridge.shutdownCalls, 1);
      await expectLater(
        adapter.request(const NetRequest(method: 'GET', url: 'https://a.com')),
        throwsA(
          isA<NetException>().having(
            (error) => error.code,
            'code',
            NetErrorCode.infrastructure,
          ),
        ),
      );
    });

    test(
      'shutdown on one adapter invalidates other adapters in same scope',
      () async {
        final bridge = _LifecycleFakeRustBridgeApi();
        final firstAdapter = RustAdapter(bridgeApi: bridge);
        final secondAdapter = RustAdapter(bridgeApi: bridge);

        await firstAdapter.initializeEngine();
        await secondAdapter.initializeEngine();

        expect(firstAdapter.isReady, isTrue);
        expect(secondAdapter.isReady, isTrue);
        expect(bridge.initCalls, 1);

        await firstAdapter.shutdownEngine();

        expect(firstAdapter.isReady, isFalse);
        expect(secondAdapter.isReady, isFalse);
        await expectLater(
          secondAdapter.request(
            const NetRequest(method: 'GET', url: 'https://example.com/shared'),
          ),
          throwsA(
            isA<NetException>().having(
              (error) => error.code,
              'code',
              NetErrorCode.infrastructure,
            ),
          ),
        );
      },
    );

    test(
      'shutdown allows reinitialize with new config on same scope',
      () async {
        final bridge = _LifecycleFakeRustBridgeApi();
        final firstAdapter = RustAdapter(bridgeApi: bridge);
        final secondAdapter = RustAdapter(bridgeApi: bridge);

        await firstAdapter.initializeEngine(
          options: const RustEngineInitOptions(cacheDefaultTtlSeconds: 12),
        );
        await firstAdapter.shutdownEngine();
        await secondAdapter.initializeEngine(
          options: const RustEngineInitOptions(cacheDefaultTtlSeconds: 30),
        );

        expect(firstAdapter.isReady, isFalse);
        expect(secondAdapter.isReady, isTrue);
        expect(bridge.initCalls, 2);
        expect(bridge.initConfigs, hasLength(2));
        expect(bridge.initConfigs.first.cacheDefaultTtlSeconds, 12);
        expect(bridge.initConfigs.last.cacheDefaultTtlSeconds, 30);
      },
    );

    test(
      'failed shutdown keeps current scope conservatively initialized',
      () async {
        final bridge = _LifecycleFakeRustBridgeApi(
          shutdownError: Exception('shutdown failed'),
        );
        final adapter = RustAdapter(bridgeApi: bridge);

        await adapter.initializeEngine(
          options: const RustEngineInitOptions(cacheDefaultTtlSeconds: 12),
        );

        await expectLater(
          adapter.shutdownEngine(),
          throwsA(
            isA<NetException>()
                .having(
                  (error) => error.code,
                  'code',
                  NetErrorCode.infrastructure,
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains('Rust shutdown failed'),
                ),
          ),
        );

        expect(adapter.isReady, isTrue);
        final response = await adapter.request(
          const NetRequest(
            method: 'GET',
            url: 'https://example.com/keep-ready',
          ),
        );
        expect(response.statusCode, 200);
        expect(bridge.shutdownCalls, 1);
      },
    );
  });
}

class _LifecycleFakeRustBridgeApi implements RustBridgeApi {
  int ensureLoadedCalls = 0;
  int initCalls = 0;
  int shutdownCalls = 0;
  final List<rust_api.NetEngineConfig> initConfigs =
      <rust_api.NetEngineConfig>[];
  final Exception? shutdownError;

  _LifecycleFakeRustBridgeApi({this.shutdownError});

  @override
  Future<void> ensureBridgeLoaded() async {
    ensureLoadedCalls += 1;
  }

  @override
  Future<void> initNetEngine({required rust_api.NetEngineConfig config}) async {
    initCalls += 1;
    initConfigs.add(config);
  }

  @override
  Future<void> shutdownNetEngine() async {
    shutdownCalls += 1;
    if (shutdownError != null) {
      throw shutdownError!;
    }
  }

  @override
  Future<rust_api.ResponseMeta> request({
    required rust_api.RequestSpec spec,
  }) async {
    return rust_api.ResponseMeta(
      requestId: spec.requestId,
      statusCode: 200,
      headers: const [('content-type', 'application/json')],
      bodyInline: Uint8List.fromList(const [123, 125]),
      bodyFilePath: null,
      fromCache: false,
      costMs: 1,
      error: null,
    );
  }

  @override
  Future<String> startTransferTask({required rust_api.TransferTaskSpec spec}) {
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
