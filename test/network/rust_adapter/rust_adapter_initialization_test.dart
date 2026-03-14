import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/net_models.dart';
import 'package:flutter_rust_net/network/rust_adapter.dart';

import 'fake_rust_bridge_api.dart';

void main() {
  group('RustAdapter initialization', () {
    test('allows same adapter reinitialization when config matches', () async {
      final fakeBridge = FakeRustBridgeApi();
      final adapter = RustAdapter(bridgeApi: fakeBridge);
      const options = RustEngineInitOptions(cacheDefaultTtlSeconds: 12);

      await adapter.initializeEngine(options: options);
      await adapter.initializeEngine(options: options);

      expect(adapter.isInitialized, isTrue);
      expect(fakeBridge.initCalls, 1);
    });

    test('rejects conflicting reinitialization on same adapter', () async {
      final fakeBridge = FakeRustBridgeApi();
      final adapter = RustAdapter(bridgeApi: fakeBridge);

      await adapter.initializeEngine(
        options: const RustEngineInitOptions(cacheDefaultTtlSeconds: 12),
      );

      await expectLater(
        adapter.initializeEngine(
          options: const RustEngineInitOptions(cacheDefaultTtlSeconds: 30),
        ),
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
                isFalse,
              )
              .having(
                (error) => error.message,
                'message',
                contains('cacheDefaultTtlSeconds=12 -> 30'),
              ),
        ),
      );
      expect(fakeBridge.initCalls, 1);
    });

    test('coalesces concurrent initialization when config matches', () async {
      final gate = Completer<void>();
      final fakeBridge = FakeRustBridgeApi(
        initResponder: (config) async {
          await gate.future;
        },
      );
      final firstAdapter = RustAdapter(bridgeApi: fakeBridge);
      final secondAdapter = RustAdapter(bridgeApi: fakeBridge);
      const options = RustEngineInitOptions(cacheDefaultTtlSeconds: 12);

      final firstInit = firstAdapter.initializeEngine(options: options);
      final secondInit = secondAdapter.initializeEngine(options: options);

      await Future<void>.delayed(Duration.zero);
      expect(fakeBridge.initCalls, 1);

      gate.complete();
      await Future.wait([firstInit, secondInit]);

      expect(firstAdapter.isInitialized, isTrue);
      expect(secondAdapter.isInitialized, isTrue);
      expect(fakeBridge.initCalls, 1);
    });

    test(
      'rejects conflicting concurrent initialization before second init attempt',
      () async {
        final gate = Completer<void>();
        final fakeBridge = FakeRustBridgeApi(
          initResponder: (config) async {
            await gate.future;
          },
        );
        final firstAdapter = RustAdapter(bridgeApi: fakeBridge);
        final secondAdapter = RustAdapter(bridgeApi: fakeBridge);

        final firstInit = firstAdapter.initializeEngine(
          options: const RustEngineInitOptions(cacheDefaultTtlSeconds: 12),
        );
        final secondInit = secondAdapter.initializeEngine(
          options: const RustEngineInitOptions(cacheDefaultTtlSeconds: 30),
        );

        final secondInitExpectation = expectLater(
          secondInit,
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
                  isFalse,
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains('cacheDefaultTtlSeconds=12 -> 30'),
                ),
          ),
        );

        gate.complete();
        await firstInit;
        await secondInitExpectation;

        expect(firstAdapter.isInitialized, isTrue);
        expect(secondAdapter.isInitialized, isFalse);
        expect(fakeBridge.initCalls, 1);
      },
    );

    test('reuses shared initialized scope when config matches', () async {
      final fakeBridge = FakeRustBridgeApi();
      final firstAdapter = RustAdapter(bridgeApi: fakeBridge);
      final secondAdapter = RustAdapter(bridgeApi: fakeBridge);
      const options = RustEngineInitOptions(cacheDefaultTtlSeconds: 12);

      await firstAdapter.initializeEngine(options: options);
      await secondAdapter.initializeEngine(options: options);

      expect(firstAdapter.isInitialized, isTrue);
      expect(secondAdapter.isInitialized, isTrue);
      expect(fakeBridge.initCalls, 1);
    });

    test('rejects conflicting config on shared initialized scope', () async {
      final fakeBridge = FakeRustBridgeApi();
      final firstAdapter = RustAdapter(bridgeApi: fakeBridge);
      final secondAdapter = RustAdapter(bridgeApi: fakeBridge);

      await firstAdapter.initializeEngine(
        options: const RustEngineInitOptions(cacheDefaultTtlSeconds: 12),
      );

      await expectLater(
        secondAdapter.initializeEngine(
          options: const RustEngineInitOptions(cacheDefaultTtlSeconds: 30),
        ),
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
                isFalse,
              )
              .having(
                (error) => error.message,
                'message',
                contains('cacheDefaultTtlSeconds=12 -> 30'),
              ),
        ),
      );
      expect(secondAdapter.isInitialized, isFalse);
      expect(fakeBridge.initCalls, 1);
    });

    test(
      'rejects conflicting namespace budget on shared initialized scope',
      () async {
        final fakeBridge = FakeRustBridgeApi();
        final firstAdapter = RustAdapter(bridgeApi: fakeBridge);
        final secondAdapter = RustAdapter(bridgeApi: fakeBridge);

        await firstAdapter.initializeEngine(
          options: const RustEngineInitOptions(cacheMaxNamespaceBytes: 4096),
        );

        await expectLater(
          secondAdapter.initializeEngine(
            options: const RustEngineInitOptions(cacheMaxNamespaceBytes: 8192),
          ),
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
                  isFalse,
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains('cacheMaxNamespaceBytes=4096 -> 8192'),
                ),
          ),
        );
        expect(secondAdapter.isInitialized, isFalse);
        expect(fakeBridge.initCalls, 1);
      },
    );

    test(
      'rejects conflicting response cache namespace on shared initialized scope',
      () async {
        final fakeBridge = FakeRustBridgeApi();
        final firstAdapter = RustAdapter(bridgeApi: fakeBridge);
        final secondAdapter = RustAdapter(bridgeApi: fakeBridge);

        await firstAdapter.initializeEngine(
          options: const RustEngineInitOptions(
            cacheResponseNamespace: 'responses_a',
          ),
        );

        await expectLater(
          secondAdapter.initializeEngine(
            options: const RustEngineInitOptions(
              cacheResponseNamespace: 'responses_b',
            ),
          ),
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
                  isFalse,
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains(
                    'cacheResponseNamespace="responses_a" -> "responses_b"',
                  ),
                ),
          ),
        );
        expect(secondAdapter.isInitialized, isFalse);
        expect(fakeBridge.initCalls, 1);
      },
    );

    test(
      'reuses shared initialized scope when response cache namespace only differs by trim',
      () async {
        final fakeBridge = FakeRustBridgeApi();
        final firstAdapter = RustAdapter(bridgeApi: fakeBridge);
        final secondAdapter = RustAdapter(bridgeApi: fakeBridge);

        await firstAdapter.initializeEngine(
          options: const RustEngineInitOptions(
            cacheResponseNamespace: ' tenant_cache ',
          ),
        );
        await secondAdapter.initializeEngine(
          options: const RustEngineInitOptions(
            cacheResponseNamespace: 'tenant_cache',
          ),
        );

        expect(firstAdapter.isInitialized, isTrue);
        expect(secondAdapter.isInitialized, isTrue);
        expect(fakeBridge.initCalls, 1);
        expect(
          fakeBridge.lastInitConfig?.cacheResponseNamespace,
          'tenant_cache',
        );
      },
    );

    test(
      'ignores response cache namespace differences when cache is disabled',
      () async {
        final fakeBridge = FakeRustBridgeApi();
        final firstAdapter = RustAdapter(bridgeApi: fakeBridge);
        final secondAdapter = RustAdapter(bridgeApi: fakeBridge);

        await firstAdapter.initializeEngine(
          options: const RustEngineInitOptions(
            cacheDir: '',
            cacheResponseNamespace: '../outside',
          ),
        );
        await secondAdapter.initializeEngine(
          options: const RustEngineInitOptions(
            cacheDir: '',
            cacheResponseNamespace: 'tenant_cache',
          ),
        );

        expect(firstAdapter.isInitialized, isTrue);
        expect(secondAdapter.isInitialized, isTrue);
        expect(fakeBridge.initCalls, 1);
        expect(fakeBridge.lastInitConfig?.cacheResponseNamespace, 'responses');
      },
    );

    test(
      'allows matching reinitialization when actual config is unknown',
      () async {
        final fakeBridge = FakeRustBridgeApi(
          initError: Exception(
            'AnyhowException(NetEngine already initialized)',
          ),
        );
        final adapter = RustAdapter(bridgeApi: fakeBridge);
        const options = RustEngineInitOptions(cacheDefaultTtlSeconds: 12);

        await adapter.initializeEngine(options: options);
        await adapter.initializeEngine(options: options);
        expect(adapter.isInitialized, isTrue);
        expect(fakeBridge.initCalls, 1);
      },
    );

    test(
      'rejects conflicting config after accepting unknown actual config',
      () async {
        final fakeBridge = FakeRustBridgeApi(
          initError: Exception(
            'AnyhowException(NetEngine already initialized)',
          ),
        );
        final firstAdapter = RustAdapter(bridgeApi: fakeBridge);
        final secondAdapter = RustAdapter(bridgeApi: fakeBridge);

        await firstAdapter.initializeEngine(
          options: const RustEngineInitOptions(cacheDefaultTtlSeconds: 12),
        );

        await expectLater(
          secondAdapter.initializeEngine(
            options: const RustEngineInitOptions(cacheDefaultTtlSeconds: 30),
          ),
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
                  isFalse,
                )
                .having(
                  (error) => error.message,
                  'message',
                  allOf(
                    contains('already initialized before Dart could observe'),
                    contains('cacheDefaultTtlSeconds=12 -> 30'),
                  ),
                ),
          ),
        );

        expect(firstAdapter.isInitialized, isTrue);
        expect(secondAdapter.isInitialized, isFalse);
        expect(fakeBridge.initCalls, 1);
      },
    );

    test(
      'rejects conflicting reinitialization on same adapter when actual config is unknown',
      () async {
        final fakeBridge = FakeRustBridgeApi(
          initError: Exception(
            'AnyhowException(NetEngine already initialized)',
          ),
        );
        final adapter = RustAdapter(bridgeApi: fakeBridge);

        await adapter.initializeEngine(
          options: const RustEngineInitOptions(cacheDefaultTtlSeconds: 12),
        );

        await expectLater(
          adapter.initializeEngine(
            options: const RustEngineInitOptions(cacheDefaultTtlSeconds: 30),
          ),
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
                  isFalse,
                )
                .having(
                  (error) => error.message,
                  'message',
                  allOf(
                    contains('already initialized before Dart could observe'),
                    contains('cacheDefaultTtlSeconds=12 -> 30'),
                  ),
                ),
          ),
        );

        expect(adapter.isInitialized, isTrue);
        expect(fakeBridge.initCalls, 1);
      },
    );

    test('adds rebuild hint when rust init reports bridge payload mismatch', () {
      final fakeBridge = FakeRustBridgeApi(
        initError: Exception(
          'PanicException(called `Result::unwrap()` on an `Err` value: '
          'Error { kind: UnexpectedEof, message: "failed to fill whole buffer" })',
        ),
      );
      final adapter = RustAdapter(bridgeApi: fakeBridge);

      expect(
        adapter.initializeEngine(),
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
                contains('cargo build --release -p net_engine'),
              ),
        ),
      );
    });
  });
}
