import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/benchmark/network_benchmark_harness.dart';
import 'package:flutter_rust_net/network/rhttp_adapter.dart';
import 'package:flutter_rust_net/rust_bridge/api.dart' as rust_api;

import 'rust_adapter/fake_rust_bridge_api.dart';

void main() {
  group('benchmark runner thin-gateway rust channel', () {
    test(
      'preflights the rust request channel without using rust bridge lifecycle',
      () async {
        final requestAdapter = _buildBenchmarkRequestAdapter();
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
          rustAdapter: requestAdapter,
        );
        final second = await runNetworkBenchmark(
          config,
          rustAdapter: requestAdapter,
        );

        expect(first.rustChannelPreflighted, isTrue);
        expect(second.rustChannelPreflighted, isTrue);
        expect(first.channelResults.single.exceptions, 0);
        expect(second.channelResults.single.exceptions, 0);
        expect(first.channelResults.single.completedRequests, 4);
        expect(second.channelResults.single.completedRequests, 4);
        expect(first.rustCacheObservation, isNull);
        expect(second.rustCacheObservation, isNull);
        expect(first.channelResults.single.responseChannels['rust'], 4);
        expect(second.channelResults.single.responseChannels['rust'], 4);
        expect(first.toJson()['rustChannelPreflighted'], isTrue);
        expect(first.toJson().containsKey('rustInitialized'), isFalse);
        expect(first.toPrettyText(), contains('rustChannelPreflighted=true'));
        expect(first.toPrettyText(), isNot(contains('rustInitialized=')));
      },
    );

    test(
      'rust benchmark request path does not require explicit initialization',
      () async {
        final requestAdapter = _buildBenchmarkRequestAdapter();

        final report = await runNetworkBenchmark(
          const BenchmarkConfig(
            scenario: BenchmarkScenario.smallJson,
            requests: 4,
            warmupRequests: 0,
            concurrency: 1,
            channels: {BenchmarkChannel.rust},
            initializeRust: false,
            requireRust: false,
            enableFallback: false,
            verbose: false,
          ),
          rustAdapter: requestAdapter,
        );

        expect(report.rustChannelPreflighted, isFalse);
        expect(report.channelResults.single.exceptions, 0);
        expect(report.channelResults.single.completedRequests, 4);
        expect(report.channelResults.single.responseChannels['rust'], 4);
        expect(report.rustCacheObservation, isNull);
        expect(report.toJson()['rustChannelPreflighted'], isFalse);
        expect(report.toJson().containsKey('rustInitialized'), isFalse);
        expect(report.toPrettyText(), contains('rustChannelPreflighted=false'));
      },
    );

    test('rejects rustBridgeApi-only benchmark wiring in thin-gateway V1', () {
      final fakeBridge = _buildBenchmarkBridge();

      expect(
        () => runNetworkBenchmark(
          const BenchmarkConfig(
            scenario: BenchmarkScenario.smallJson,
            requests: 1,
            warmupRequests: 0,
            concurrency: 1,
            channels: {BenchmarkChannel.rust},
            initializeRust: false,
            requireRust: false,
            enableFallback: false,
            verbose: false,
          ),
          rustBridgeApi: fakeBridge,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('inject rustAdapter explicitly'),
          ),
        ),
      );
      expect(fakeBridge.initCalls, 0);
      expect(fakeBridge.shutdownCalls, 0);
    });
  });
}

RhttpAdapter _buildBenchmarkRequestAdapter() {
  return RhttpAdapter(
    requestHandler: (request) async {
      final uri = Uri.parse(request.url);
      final body = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'ok': true,
            'path': uri.path,
            'requestId': uri.queryParameters['id'],
          }),
        ),
      );
      return RhttpAdapterResponse(
        statusCode: HttpStatus.ok,
        headers: const [('content-type', 'application/json')],
        bodyBytes: body,
      );
    },
  );
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
