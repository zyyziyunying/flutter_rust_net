import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/net_models.dart';
import 'package:flutter_rust_net/network/rust_adapter.dart';
import 'package:flutter_rust_net/network/rust_bridge_api.dart';
import 'package:flutter_rust_net/rust_bridge/api.dart' as rust_api;

void main() {
  group('RustAdapter', () {
    test('throws infrastructure error before initialization', () async {
      final adapter = RustAdapter(bridgeApi: _FakeRustBridgeApi());

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
              ),
        ),
      );
    });

    test('initializes and maps rust success response', () async {
      final fakeBridge = _FakeRustBridgeApi(
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
      final fakeBridge = _FakeRustBridgeApi();
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
      final fakeBridge = _FakeRustBridgeApi(
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
        final fakeBridge = _FakeRustBridgeApi(
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
      final fakeBridge = _FakeRustBridgeApi(
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
      final fakeBridge = _FakeRustBridgeApi(
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
      final fakeBridge = _FakeRustBridgeApi(
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
        final fakeBridge = _FakeRustBridgeApi(
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
      final fakeBridge = _FakeRustBridgeApi(
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

    test('allows same adapter reinitialization when config matches', () async {
      final fakeBridge = _FakeRustBridgeApi();
      final adapter = RustAdapter(bridgeApi: fakeBridge);
      const options = RustEngineInitOptions(cacheDefaultTtlSeconds: 12);

      await adapter.initializeEngine(options: options);
      await adapter.initializeEngine(options: options);

      expect(adapter.isInitialized, isTrue);
      expect(fakeBridge.initCalls, 1);
    });

    test('rejects conflicting reinitialization on same adapter', () async {
      final fakeBridge = _FakeRustBridgeApi();
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
      final fakeBridge = _FakeRustBridgeApi(
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
        final fakeBridge = _FakeRustBridgeApi(
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

        await expectLater(
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

        expect(firstAdapter.isInitialized, isTrue);
        expect(secondAdapter.isInitialized, isFalse);
        expect(fakeBridge.initCalls, 1);
      },
    );

    test('allows already initialized branch when config matches', () async {
      var initAttempt = 0;
      final fakeBridge = _FakeRustBridgeApi(
        initResponder: (config) async {
          initAttempt += 1;
          if (initAttempt >= 2) {
            throw Exception('AnyhowException(NetEngine already initialized)');
          }
        },
      );
      final firstAdapter = RustAdapter(bridgeApi: fakeBridge);
      final secondAdapter = RustAdapter(bridgeApi: fakeBridge);
      const options = RustEngineInitOptions(cacheDefaultTtlSeconds: 12);

      await firstAdapter.initializeEngine(options: options);
      await secondAdapter.initializeEngine(options: options);

      expect(firstAdapter.isInitialized, isTrue);
      expect(secondAdapter.isInitialized, isTrue);
      expect(fakeBridge.initCalls, 2);
    });

    test(
      'rejects conflicting config when bridge reports already initialized',
      () async {
        var initAttempt = 0;
        final fakeBridge = _FakeRustBridgeApi(
          initResponder: (config) async {
            initAttempt += 1;
            if (initAttempt >= 2) {
              throw Exception('AnyhowException(NetEngine already initialized)');
            }
          },
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
                  contains('cacheDefaultTtlSeconds=12 -> 30'),
                ),
          ),
        );
        expect(secondAdapter.isInitialized, isFalse);
        expect(fakeBridge.initCalls, 2);
      },
    );

    test(
      'allows matching reinitialization when actual config is unknown',
      () async {
        final fakeBridge = _FakeRustBridgeApi(
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
        final fakeBridge = _FakeRustBridgeApi(
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
        expect(fakeBridge.initCalls, 2);
      },
    );

    test(
      'rejects conflicting reinitialization on same adapter when actual config is unknown',
      () async {
        final fakeBridge = _FakeRustBridgeApi(
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
      final fakeBridge = _FakeRustBridgeApi(
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

    test(
      'starts transfer task and maps events/cancel through bridge',
      () async {
        final fakeBridge = _FakeRustBridgeApi(
          startTransferResponder: (spec) async {
            expect(spec.taskId, 'transfer-1');
            expect(spec.kind, NetTransferKind.download.name);
            expect(spec.url, 'https://example.com/file.bin');
            expect(spec.localPath, '/tmp/file.bin');
            expect(spec.expectedTotal, BigInt.from(2048));
            expect(spec.priority, 7);
            return spec.taskId;
          },
          pollEventsResponder: (limit) async {
            expect(limit, 8);
            return [
              rust_api.NetEvent(
                id: 'transfer-1',
                kind: rust_api.NetEventKind.progress,
                transferred: BigInt.one,
                total: BigInt.one,
                statusCode: null,
                message: null,
                costMs: null,
              ),
            ];
          },
          cancelResponder: (id) async {
            expect(id, 'transfer-1');
            return true;
          },
        );
        final adapter = RustAdapter(bridgeApi: fakeBridge);

        await adapter.initializeEngine();
        final taskId = await adapter.startTransferTask(
          const NetTransferTaskRequest(
            taskId: 'transfer-1',
            kind: NetTransferKind.download,
            url: 'https://example.com/file.bin',
            localPath: '/tmp/file.bin',
            expectedTotal: 2048,
            priority: 7,
          ),
        );
        final events = await adapter.pollTransferEvents(limit: 8);
        final canceled = await adapter.cancelTransferTask('transfer-1');

        expect(taskId, 'transfer-1');
        expect(events, hasLength(1));
        expect(events.first.id, 'transfer-1');
        expect(events.first.kind, NetTransferEventKind.progress);
        expect(events.first.transferred, 1);
        expect(events.first.total, 1);
        expect(events.first.channel, NetChannel.rust);
        expect(canceled, isTrue);
        expect(fakeBridge.startTransferCalls, 1);
        expect(fakeBridge.pollEventsCalls, 1);
        expect(fakeBridge.cancelCalls, 1);
      },
    );

    test('clears cache through rust bridge', () async {
      final fakeBridge = _FakeRustBridgeApi(
        clearCacheResponder: (namespace) async {
          expect(namespace, 'responses');
          return 128;
        },
      );
      final adapter = RustAdapter(bridgeApi: fakeBridge);

      await adapter.initializeEngine();
      final removed = await adapter.clearCache(namespace: 'responses');

      expect(removed, 128);
      expect(fakeBridge.clearCacheCalls, 1);
    });
  });
}

class _FakeRustBridgeApi implements RustBridgeApi {
  int ensureLoadedCalls = 0;
  int initCalls = 0;
  int startTransferCalls = 0;
  int pollEventsCalls = 0;
  int cancelCalls = 0;
  int clearCacheCalls = 0;
  rust_api.NetEngineConfig? lastInitConfig;
  final Exception? initError;
  final Future<void> Function(rust_api.NetEngineConfig config)? initResponder;
  final Future<rust_api.ResponseMeta> Function(rust_api.RequestSpec spec)?
  requestResponder;
  final Future<String> Function(rust_api.TransferTaskSpec spec)?
  startTransferResponder;
  final Future<List<rust_api.NetEvent>> Function(int limit)?
  pollEventsResponder;
  final Future<bool> Function(String id)? cancelResponder;
  final Future<int> Function(String? namespace)? clearCacheResponder;

  _FakeRustBridgeApi({
    this.initError,
    this.initResponder,
    this.requestResponder,
    this.startTransferResponder,
    this.pollEventsResponder,
    this.cancelResponder,
    this.clearCacheResponder,
  });

  @override
  Future<void> ensureBridgeLoaded() async {
    ensureLoadedCalls += 1;
  }

  @override
  Future<void> initNetEngine({required rust_api.NetEngineConfig config}) async {
    initCalls += 1;
    lastInitConfig = config;
    final responder = initResponder;
    if (responder != null) {
      await responder(config);
      return;
    }
    if (initError != null) {
      throw initError!;
    }
  }

  @override
  Future<rust_api.ResponseMeta> request({required rust_api.RequestSpec spec}) {
    final responder = requestResponder;
    if (responder != null) {
      return responder(spec);
    }
    throw UnimplementedError('requestResponder not set');
  }

  @override
  Future<String> startTransferTask({required rust_api.TransferTaskSpec spec}) {
    startTransferCalls += 1;
    final responder = startTransferResponder;
    if (responder != null) {
      return responder(spec);
    }
    throw UnimplementedError('startTransferResponder not set');
  }

  @override
  Future<List<rust_api.NetEvent>> pollEvents({required int limit}) {
    pollEventsCalls += 1;
    final responder = pollEventsResponder;
    if (responder != null) {
      return responder(limit);
    }
    return Future.value(const []);
  }

  @override
  Future<bool> cancel({required String id}) {
    cancelCalls += 1;
    final responder = cancelResponder;
    if (responder != null) {
      return responder(id);
    }
    return Future.value(false);
  }

  @override
  Future<int> clearCache({String? namespace}) {
    clearCacheCalls += 1;
    final responder = clearCacheResponder;
    if (responder != null) {
      return responder(namespace);
    }
    return Future.value(0);
  }
}
