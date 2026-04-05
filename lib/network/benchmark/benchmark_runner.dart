import 'dart:math';

import 'package:dio/dio.dart';

import '../dio_adapter.dart';
import '../net_adapter.dart';
import '../net_feature_flag.dart';
import '../net_models.dart';
import '../network_gateway.dart';
import '../rhttp_adapter.dart';
import '../routing_policy.dart';
import 'benchmark_accumulator.dart';
import 'benchmark_response_consumer.dart';
import 'benchmark_scenario_server.dart';
import 'benchmark_types.dart';

Future<BenchmarkReport> runNetworkBenchmark(
  BenchmarkConfig config, {
  BenchLogger? log,
  NetAdapter? primaryRequestAdapter,
}) async {
  config.validate();
  final logger = log ?? (_) {};
  final startedAt = DateTime.now();
  ScenarioServer? scenarioServer;
  final skippedChannels = <String, String>{};
  var primaryChannelPreflighted = false;
  BenchmarkReport? report;
  Object? pendingError;
  StackTrace? pendingStackTrace;

  final dioAdapter = DioAdapter(
    client: Dio(
      BaseOptions(
        connectTimeout: config.dioConnectTimeout,
        receiveTimeout: config.dioReceiveTimeout,
        sendTimeout: config.dioConnectTimeout,
      ),
    ),
  );
  final resolvedPrimaryRequestAdapter = primaryRequestAdapter ?? RhttpAdapter();

  try {
    final resolvedScenarioBaseUrl = resolveScenarioBaseUrl(
      config.scenarioBaseUrl,
    );
    late final String benchmarkBaseUrl;
    if (resolvedScenarioBaseUrl != null) {
      benchmarkBaseUrl = resolvedScenarioBaseUrl;
      logger(
        '[network-bench] using external scenario server at $benchmarkBaseUrl',
      );
    } else {
      scenarioServer = await ScenarioServer.start(config, logger: logger);
      benchmarkBaseUrl = scenarioServer.baseUrl;
    }

    if (config.channels.contains(BenchmarkChannel.rust) &&
        (config.preflightPrimaryChannel || config.requirePrimaryChannel)) {
      logger(
        '[network-bench] preparing primary request channel '
        '(BenchmarkChannel.rust compatibility label)...',
      );
      try {
        primaryChannelPreflighted = await _preparePrimaryRequestAdapter(
          resolvedPrimaryRequestAdapter,
        );
        if (!primaryChannelPreflighted) {
          throw StateError('primary request channel is not ready');
        }
        logger('[network-bench] primary request channel ready');
      } catch (error) {
        final reason = 'primary request channel setup failed: $error';
        if (config.requirePrimaryChannel) {
          rethrow;
        }
        skippedChannels[BenchmarkChannel.rust.cliName] = reason;
        logger(
          '[network-bench] skip primary request channel (`rust` alias), $reason',
        );
      }
    }

    final gateway = NetworkGateway(
      routingPolicy: const RoutingPolicy(),
      featureFlag: NetFeatureFlag(
        enableRustChannel: true,
        enableFallback: config.enableFallback,
      ),
      dioAdapter: dioAdapter,
      primaryRequestAdapter: resolvedPrimaryRequestAdapter,
    );

    final orderedChannels = [...config.channels]
      ..sort((left, right) => left.cliName.compareTo(right.cliName));

    final results = <ChannelBenchmarkResult>[];
    final includeBenchChannelHeader = scenarioServer != null;
    for (final channel in orderedChannels) {
      final skippedReason = skippedChannels[channel.cliName];
      if (skippedReason != null) {
        continue;
      }

      logger(
        '[network-bench] run channel=${channel.cliName} '
        'scenario=${config.scenario.cliName}',
      );
      final result = await _runChannelBenchmark(
        config: config,
        gateway: gateway,
        channel: channel,
        baseUrl: benchmarkBaseUrl,
        includeBenchChannelHeader: includeBenchChannelHeader,
        logger: logger,
      );
      ChannelBenchmarkResult mergedResult = result;
      if (scenarioServer != null) {
        final telemetry = scenarioServer.cacheTelemetryForChannel(
          channel.cliName,
        );
        mergedResult = result.copyWith(
          cacheRevalidateCount: telemetry.conditionalRequests,
          cacheEvictCount: telemetry.repeatedOriginRequests,
        );
      }
      results.add(mergedResult);
      logger(
        '[network-bench][${channel.cliName}] ${mergedResult.toOneLineSummary()}',
      );
    }

    final finishedAt = DateTime.now();
    report = BenchmarkReport(
      startedAt: startedAt,
      finishedAt: finishedAt,
      config: config,
      baseUrl: benchmarkBaseUrl,
      primaryChannelPreflighted: primaryChannelPreflighted,
      skippedChannels: Map.unmodifiable(skippedChannels),
      channelResults: List.unmodifiable(results),
    );
  } catch (error, stackTrace) {
    pendingError = error;
    pendingStackTrace = stackTrace;
  } finally {
    Object? cleanupError;
    StackTrace? cleanupStackTrace;

    if (scenarioServer != null) {
      try {
        await scenarioServer.close();
      } catch (error, stackTrace) {
        cleanupError = error;
        cleanupStackTrace = stackTrace;
      }
    }

    if (pendingError == null && cleanupError != null) {
      Error.throwWithStackTrace(cleanupError, cleanupStackTrace!);
    }
  }

  if (pendingError != null) {
    Error.throwWithStackTrace(pendingError, pendingStackTrace!);
  }
  return report!;
}

Future<bool> _preparePrimaryRequestAdapter(NetAdapter adapter) async {
  if (adapter is RhttpAdapter) {
    return adapter.ensureRequestReady();
  }
  return adapter.isReady;
}

Future<ChannelBenchmarkResult> _runChannelBenchmark({
  required BenchmarkConfig config,
  required NetworkGateway gateway,
  required BenchmarkChannel channel,
  required String baseUrl,
  required bool includeBenchChannelHeader,
  required BenchLogger logger,
}) async {
  final accumulator = ChannelRunAccumulator(
    channelName: channel.cliName,
    totalRequests: config.requests,
    warmupRequests: config.warmupRequests,
  );

  await _runWarmup(
    config: config,
    gateway: gateway,
    channel: channel,
    baseUrl: baseUrl,
    includeBenchChannelHeader: includeBenchChannelHeader,
    logger: logger,
  );

  var issued = 0;
  final wallWatch = Stopwatch()..start();
  final progressStep = max(1, config.requests ~/ 10);

  Future<void> worker() async {
    while (true) {
      final requestIndex = issued++;
      if (requestIndex >= config.requests) {
        return;
      }

      final request = _buildRequest(
        config: config,
        channel: channel,
        baseUrl: baseUrl,
        requestIndex: requestIndex,
        includeBenchChannelHeader: includeBenchChannelHeader,
      );
      final totalWatch = Stopwatch()..start();
      try {
        final response = await gateway.request(request);
        final requestMs = totalWatch.elapsedMilliseconds;
        final consume = await consumeResponse(
          config: config,
          response: response,
        );
        totalWatch.stop();
        accumulator.recordResponse(
          response: response,
          requestMs: requestMs,
          endToEndMs: totalWatch.elapsedMilliseconds,
          consume: consume,
          requestKey: '${request.method.toUpperCase()} ${request.url}',
        );
      } catch (error) {
        totalWatch.stop();
        accumulator.recordError(
          error: error,
          requestMs: totalWatch.elapsedMilliseconds,
          endToEndMs: totalWatch.elapsedMilliseconds,
        );
      }

      if (config.verbose && (requestIndex + 1) % progressStep == 0) {
        logger(
          '[network-bench][${channel.cliName}] progress='
          '${requestIndex + 1}/${config.requests}',
        );
      }
    }
  }

  await Future.wait(List.generate(config.concurrency, (_) => worker()));
  wallWatch.stop();

  return accumulator.finish(wallElapsedMs: wallWatch.elapsedMilliseconds);
}

Future<void> _runWarmup({
  required BenchmarkConfig config,
  required NetworkGateway gateway,
  required BenchmarkChannel channel,
  required String baseUrl,
  required bool includeBenchChannelHeader,
  required BenchLogger logger,
}) async {
  if (config.warmupRequests <= 0) {
    return;
  }

  logger('[network-bench][${channel.cliName}] warmup=${config.warmupRequests}');
  for (var i = 0; i < config.warmupRequests; i += 1) {
    final request = _buildRequest(
      config: config,
      channel: channel,
      baseUrl: baseUrl,
      requestIndex: -1 - i,
      includeBenchChannelHeader: includeBenchChannelHeader,
    );
    try {
      await gateway.request(request);
    } catch (_) {
      // Warmup is best-effort; ignore transient failures to keep benchmark startup lightweight.
    }
  }
}

NetRequest _buildRequest({
  required BenchmarkConfig config,
  required BenchmarkChannel channel,
  required String baseUrl,
  required int requestIndex,
  required bool includeBenchChannelHeader,
}) {
  final int keyId;
  if (config.requestKeySpace > 0) {
    final normalizedIndex = requestIndex < 0 ? -requestIndex - 1 : requestIndex;
    keyId = normalizedIndex % config.requestKeySpace;
  } else {
    keyId = requestIndex;
  }

  final query = <String, dynamic>{'id': keyId};
  if (config.scenario == BenchmarkScenario.jitterLatency) {
    query['baseDelayMs'] = config.jitterBaseDelayMs;
    query['extraDelayMs'] = config.jitterExtraDelayMs;
  } else if (config.scenario == BenchmarkScenario.flakyHttp) {
    query['failureEvery'] = config.flakyFailureEvery;
  }

  final uri = Uri.parse('$baseUrl${config.scenario.path}').replace(
    queryParameters: query.map((key, value) => MapEntry(key, value.toString())),
  );
  final isLarge =
      config.scenario == BenchmarkScenario.largePayload ||
      config.scenario == BenchmarkScenario.largeJson;
  final headers = includeBenchChannelHeader
      ? <String, String>{scenarioBenchChannelHeader: channel.cliName}
      : const <String, String>{};

  return NetRequest(
    method: 'GET',
    url: uri.toString(),
    headers: headers,
    expectLargeResponse: isLarge,
    forceChannel: channel.netChannel,
  );
}
