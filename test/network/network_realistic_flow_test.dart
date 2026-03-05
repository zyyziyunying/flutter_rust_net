import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/benchmark/network_benchmark_harness.dart';
import 'package:flutter_rust_net/network/net_models.dart';

void main() {
  group('network realistic flow', () {
    test('small json burst on dio keeps full success', () async {
      final report = await runNetworkBenchmark(
        const BenchmarkConfig(
          scenario: BenchmarkScenario.smallJson,
          requests: 80,
          warmupRequests: 8,
          concurrency: 8,
          channels: {BenchmarkChannel.dio},
          initializeRust: false,
          verbose: false,
        ),
      );
      _logReport(report);

      expect(report.channelResults, hasLength(1));
      final dio = report.channelResults.single;
      expect(dio.channel, BenchmarkChannel.dio.cliName);
      expect(dio.totalRequests, 80);
      expect(dio.completedRequests, 80);
      expect(dio.exceptions, 0);
      expect(dio.http2xx, 80);
      expect(dio.fallbackCount, 0);
      expect(dio.responseChannels[NetChannel.dio.name], 80);
      expect(dio.endToEndLatencyMs.count, 80);
      expect(dio.cacheHitCount, 0);
      expect(dio.cacheMissCount, 80);
      expect(dio.cacheRevalidateCount, 0);
      expect(dio.cacheEvictCount, 0);
    });

    test(
        'request key-space exposes cache evict signals on repeated origin hits',
        () async {
      final report = await runNetworkBenchmark(
        const BenchmarkConfig(
          scenario: BenchmarkScenario.smallJson,
          requests: 12,
          warmupRequests: 0,
          concurrency: 1,
          channels: {BenchmarkChannel.dio},
          initializeRust: false,
          verbose: false,
          requestKeySpace: 3,
        ),
      );
      _logReport(report);

      final dio = report.channelResults.single;
      expect(dio.completedRequests, 12);
      expect(dio.cacheHitCount, 0);
      expect(dio.cacheMissCount, 12);
      expect(dio.cacheRevalidateCount, 0);
      expect(dio.cacheEvictCount, 9);
    });

    test('small json with json_model consume collects L2 metrics', () async {
      final report = await runNetworkBenchmark(
        const BenchmarkConfig(
          scenario: BenchmarkScenario.smallJson,
          consumeMode: BenchmarkConsumeMode.jsonModel,
          requests: 30,
          warmupRequests: 6,
          concurrency: 6,
          channels: {BenchmarkChannel.dio},
          initializeRust: false,
          verbose: false,
        ),
      );
      _logReport(report);

      final dio = report.channelResults.single;
      expect(dio.exceptions, 0);
      expect(dio.consumeAttempted, 30);
      expect(dio.consumeSucceeded, 30);
      expect(dio.consumeLatencyMs.count, 30);
      expect(dio.jsonDecodeLatencyMs.count, 30);
      expect(dio.modelBuildLatencyMs.count, 30);
      expect(dio.consumeSkippedReasons, isEmpty);
    });

    test('large json with json_model consume keeps full success', () async {
      final report = await runNetworkBenchmark(
        const BenchmarkConfig(
          scenario: BenchmarkScenario.largeJson,
          consumeMode: BenchmarkConsumeMode.jsonModel,
          requests: 20,
          warmupRequests: 4,
          concurrency: 4,
          channels: {BenchmarkChannel.dio},
          initializeRust: false,
          verbose: false,
          largePayloadBytes: 256 * 1024,
        ),
      );
      _logReport(report);

      final dio = report.channelResults.single;
      expect(dio.exceptions, 0);
      expect(dio.consumeAttempted, 20);
      expect(dio.consumeSucceeded, 20);
      expect(dio.consumeLatencyMs.count, 20);
      expect(dio.jsonDecodeLatencyMs.count, 20);
      expect(dio.modelBuildLatencyMs.count, 20);
      expect(dio.consumeSkippedReasons, isEmpty);
      expect(dio.consumeBytesTotal, greaterThan(20 * 128 * 1024));
    });

    test(
      'large payload with json consume mode is skipped on non-json',
      () async {
        final report = await runNetworkBenchmark(
          const BenchmarkConfig(
            scenario: BenchmarkScenario.largePayload,
            consumeMode: BenchmarkConsumeMode.jsonDecode,
            requests: 24,
            warmupRequests: 4,
            concurrency: 6,
            channels: {BenchmarkChannel.dio},
            initializeRust: false,
            verbose: false,
            largePayloadBytes: 128 * 1024,
          ),
        );
        _logReport(report);

        final dio = report.channelResults.single;
        expect(dio.exceptions, 0);
        expect(dio.consumeAttempted, 24);
        expect(dio.consumeSucceeded, 0);
        expect(dio.consumeSkippedReasons['non_json_content_type'], 24);
        expect(dio.consumeLatencyMs.count, 0);
      },
    );

    test(
      'flaky http exposes expected 5xx ratio without transport errors',
      () async {
        final report = await runNetworkBenchmark(
          const BenchmarkConfig(
            scenario: BenchmarkScenario.flakyHttp,
            requests: 50,
            warmupRequests: 5,
            concurrency: 10,
            channels: {BenchmarkChannel.dio},
            initializeRust: false,
            verbose: false,
            flakyFailureEvery: 5,
          ),
        );
        _logReport(report);

        final dio = report.channelResults.single;
        expect(dio.exceptions, 0);
        expect(dio.http2xx, 40);
        expect(dio.http5xx, 10);
        expect(dio.statusCodes['200'], 40);
        expect(dio.statusCodes['503'], 10);
        expect(
          dio.endToEndLatencyMs.p99Ms >= dio.endToEndLatencyMs.p95Ms,
          isTrue,
        );
        expect(
          dio.endToEndLatencyMs.p95Ms >= dio.endToEndLatencyMs.p50Ms,
          isTrue,
        );
      },
    );

    test(
      'force rust without init uses readiness gate and avoids fallback churn',
      () async {
        final report = await runNetworkBenchmark(
          const BenchmarkConfig(
            scenario: BenchmarkScenario.jitterLatency,
            requests: 40,
            warmupRequests: 5,
            concurrency: 8,
            channels: {BenchmarkChannel.rust},
            initializeRust: false,
            enableFallback: true,
            verbose: false,
            jitterBaseDelayMs: 4,
            jitterExtraDelayMs: 24,
          ),
        );
        _logReport(report);

        final rust = report.channelResults.single;
        expect(rust.channel, BenchmarkChannel.rust.cliName);
        expect(rust.exceptions, 0);
        expect(rust.completedRequests, 40);
        expect(rust.fallbackCount, 0);
        expect(rust.responseChannels[NetChannel.dio.name], 40);
        expect(rust.routeReasons['force_channel -> rust_not_ready_dio'], 40);
        expect(rust.fallbackReasons, isEmpty);
      },
    );
  });
}

void _logReport(BenchmarkReport report) {
  debugPrint(report.toPrettyText());
}
