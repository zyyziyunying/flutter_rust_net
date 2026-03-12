import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/net_models.dart';
import 'package:flutter_rust_net/network/rust_adapter.dart';
import 'package:flutter_rust_net/network/rust_bridge_api.dart';
import 'package:flutter_rust_net/rust_bridge/api.dart' as rust_api;

void main() {
  group('RustAdapter shared Frb scope', () {
    test(
      'reuses initialized scope across different FrbRustBridgeApi instances',
      () async {
        final firstBridge = _ProbeFrbRustBridgeApi();
        final secondBridge = _ProbeFrbRustBridgeApi();
        final firstAdapter = RustAdapter(bridgeApi: firstBridge);
        final secondAdapter = RustAdapter(bridgeApi: secondBridge);
        addTearDown(() => _shutdownIfReady([firstAdapter, secondAdapter]));

        const options = RustEngineInitOptions(cacheDefaultTtlSeconds: 12);

        await firstAdapter.initializeEngine(options: options);
        await secondAdapter.initializeEngine(options: options);

        expect(firstAdapter.isReady, isTrue);
        expect(secondAdapter.isReady, isTrue);
        expect(firstBridge.initCalls, 1);
        expect(secondBridge.initCalls, 0);
        expect(firstBridge.initConfigs.single.cacheDefaultTtlSeconds, 12);
        expect(secondBridge.initConfigs, isEmpty);
      },
    );

    test(
      'coalesces concurrent initialization across different FrbRustBridgeApi instances',
      () async {
        final gate = Completer<void>();
        final firstBridge = _ProbeFrbRustBridgeApi(
          initResponder: (_) => gate.future,
        );
        final secondBridge = _ProbeFrbRustBridgeApi();
        final firstAdapter = RustAdapter(bridgeApi: firstBridge);
        final secondAdapter = RustAdapter(bridgeApi: secondBridge);
        addTearDown(() => _shutdownIfReady([firstAdapter, secondAdapter]));

        const options = RustEngineInitOptions(cacheDefaultTtlSeconds: 18);

        final firstInit = firstAdapter.initializeEngine(options: options);
        final secondInit = secondAdapter.initializeEngine(options: options);

        await Future<void>.delayed(Duration.zero);

        expect(firstBridge.initCalls, 1);
        expect(secondBridge.initCalls, 0);

        gate.complete();
        await Future.wait([firstInit, secondInit]);

        expect(firstAdapter.isReady, isTrue);
        expect(secondAdapter.isReady, isTrue);
        expect(firstBridge.initCalls, 1);
        expect(secondBridge.initCalls, 0);
      },
    );

    test(
      'shutdown invalidates other Frb instances and allows restart with new config',
      () async {
        final firstBridge = _ProbeFrbRustBridgeApi();
        final secondBridge = _ProbeFrbRustBridgeApi();
        final firstAdapter = RustAdapter(bridgeApi: firstBridge);
        final secondAdapter = RustAdapter(bridgeApi: secondBridge);
        addTearDown(() => _shutdownIfReady([firstAdapter, secondAdapter]));

        await firstAdapter.initializeEngine(
          options: const RustEngineInitOptions(cacheDefaultTtlSeconds: 20),
        );
        await secondAdapter.initializeEngine(
          options: const RustEngineInitOptions(cacheDefaultTtlSeconds: 20),
        );

        expect(firstBridge.initCalls, 1);
        expect(secondBridge.initCalls, 0);

        await firstAdapter.shutdownEngine();

        expect(firstAdapter.isReady, isFalse);
        expect(secondAdapter.isReady, isFalse);
        expect(firstBridge.shutdownCalls, 1);
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

        await secondAdapter.initializeEngine(
          options: const RustEngineInitOptions(cacheDefaultTtlSeconds: 30),
        );

        expect(firstAdapter.isReady, isFalse);
        expect(secondAdapter.isReady, isTrue);
        expect(firstBridge.initCalls, 1);
        expect(secondBridge.initCalls, 1);
        expect(secondBridge.initConfigs.single.cacheDefaultTtlSeconds, 30);
      },
    );
  });
}

Future<void> _shutdownIfReady(List<RustAdapter> adapters) async {
  for (final adapter in adapters) {
    if (!adapter.isReady) {
      continue;
    }
    await adapter.shutdownEngine();
  }
}

class _ProbeFrbRustBridgeApi extends FrbRustBridgeApi {
  int ensureLoadedCalls = 0;
  int initCalls = 0;
  int shutdownCalls = 0;
  final List<rust_api.NetEngineConfig> initConfigs =
      <rust_api.NetEngineConfig>[];
  final Future<void> Function(rust_api.NetEngineConfig config)? initResponder;

  _ProbeFrbRustBridgeApi({this.initResponder});

  @override
  Future<void> ensureBridgeLoaded() async {
    ensureLoadedCalls += 1;
  }

  @override
  Future<void> initNetEngine({required rust_api.NetEngineConfig config}) async {
    initCalls += 1;
    initConfigs.add(config);
    final responder = initResponder;
    if (responder != null) {
      await responder(config);
    }
  }

  @override
  Future<void> shutdownNetEngine() async {
    shutdownCalls += 1;
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
