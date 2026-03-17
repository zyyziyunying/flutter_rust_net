import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/benchmark/network_benchmark_harness.dart';
import 'package:flutter_rust_net/network/rust_adapter.dart';
import 'package:flutter_rust_net/rust_bridge/api.dart' as rust_api;

import 'rust_adapter/fake_rust_bridge_api.dart';

void main() {
  group('benchmark runner rust ownership', () {
    test(
      'auto cache benchmark shuts down owned rust engine between runs',
      () async {
        final fakeBridge = _buildBenchmarkBridge();
        const config = BenchmarkConfig(
          scenario: BenchmarkScenario.smallJson,
          requests: 4,
          warmupRequests: 0,
          concurrency: 1,
          channels: {BenchmarkChannel.rust},
          initializeRust: true,
          requireRust: true,
          enableFallback: false,
          verbose: false,
        );

        final first = await runNetworkBenchmark(
          config,
          rustBridgeApi: fakeBridge,
        );
        final second = await runNetworkBenchmark(
          config,
          rustBridgeApi: fakeBridge,
        );

        expect(fakeBridge.initCalls, 2);
        expect(fakeBridge.shutdownCalls, 2);
        expect(first.rustInitialized, isTrue);
        expect(second.rustInitialized, isTrue);
        expect(first.channelResults.single.exceptions, 0);
        expect(second.channelResults.single.exceptions, 0);
        expect(first.channelResults.single.completedRequests, 4);
        expect(second.channelResults.single.completedRequests, 4);
        expect(
          first.config.resolvedRustCacheDir,
          isNot(equals(second.config.resolvedRustCacheDir)),
        );
        expect(first.rustCacheObservation?.rootBytes, greaterThan(0));
        expect(second.rustCacheObservation?.rootBytes, greaterThan(0));
        expect(
          Directory(first.config.resolvedRustCacheDir).existsSync(),
          isFalse,
        );
        expect(
          Directory(second.config.resolvedRustCacheDir).existsSync(),
          isFalse,
        );
      },
    );

    test(
      'benchmark reuses external rust scope without shutting it down',
      () async {
        final fakeBridge = _buildBenchmarkBridge();
        final tempRoot = await Directory.systemTemp.createTemp(
          'flutter_rust_net_benchmark_runner_',
        );
        final cacheDir =
            '${tempRoot.path}${Platform.pathSeparator}externally_owned_cache';
        final externalAdapter = RustAdapter(bridgeApi: fakeBridge);
        addTearDown(() async {
          if (externalAdapter.isReady) {
            await externalAdapter.shutdownEngine();
          }
          if (tempRoot.existsSync()) {
            await tempRoot.delete(recursive: true);
          }
        });

        await externalAdapter.initializeEngine(
          options: RustEngineInitOptions(cacheDir: cacheDir),
        );

        final report = await runNetworkBenchmark(
          BenchmarkConfig(
            scenario: BenchmarkScenario.smallJson,
            requests: 4,
            warmupRequests: 0,
            concurrency: 1,
            channels: const {BenchmarkChannel.rust},
            initializeRust: true,
            requireRust: true,
            enableFallback: false,
            verbose: false,
            rustCacheDir: cacheDir,
          ),
          rustBridgeApi: fakeBridge,
        );

        expect(report.rustInitialized, isTrue);
        expect(report.channelResults.single.exceptions, 0);
        expect(fakeBridge.initCalls, 1);
        expect(fakeBridge.shutdownCalls, 0);
        expect(externalAdapter.isReady, isTrue);
        expect(Directory(cacheDir).existsSync(), isTrue);
      },
    );
  });
}

FakeRustBridgeApi _buildBenchmarkBridge() {
  return FakeRustBridgeApi(
    initResponder: (config) async {
      final cacheDir = config.cacheDir;
      if (cacheDir.isEmpty) {
        return;
      }
      final root = Directory(cacheDir);
      await root.create(recursive: true);
      final probeFile = File(
        '${root.path}${Platform.pathSeparator}benchmark_probe.bin',
      );
      await probeFile.writeAsBytes(List<int>.filled(64, 0x42));
    },
    requestResponder: (spec) async {
      final body = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'ok': true,
            'path': spec.path,
            'requestId': spec.requestId,
          }),
        ),
      );
      return rust_api.ResponseMeta(
        requestId: spec.requestId,
        statusCode: HttpStatus.ok,
        headers: const [('content-type', 'application/json')],
        bodyInline: body,
        bodyFilePath: null,
        fromCache: false,
        costMs: 1,
        errorKind: null,
        error: null,
      );
    },
  );
}
