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

    test('maps rust timeout error as fallback eligible', () async {
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
            error: 'timeout: request timeout',
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

    test('maps rust internal error as non-fallback internal', () async {
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
            error: 'internal: scheduler closed',
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

    test('treats already initialized init error as success', () async {
      final fakeBridge = _FakeRustBridgeApi(
        initError: Exception('AnyhowException(NetEngine already initialized)'),
      );
      final adapter = RustAdapter(bridgeApi: fakeBridge);

      await adapter.initializeEngine();
      expect(adapter.isInitialized, isTrue);
      expect(fakeBridge.initCalls, 1);
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
  final Exception? initError;
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
