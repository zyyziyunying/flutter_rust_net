import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';

import '../dio_adapter.dart';
import '../net_feature_flag.dart';
import '../net_models.dart';
import '../network_gateway.dart';
import '../routing_policy.dart';
import '../rust_adapter.dart';
import '../rust_bridge_api.dart';
import 'benchmark_accumulator.dart';
import 'benchmark_response_consumer.dart';
import 'benchmark_scenario_server.dart';
import 'benchmark_types.dart';

int _benchmarkCacheRunSequence = 0;

Future<BenchmarkReport> runNetworkBenchmark(
  BenchmarkConfig config, {
  BenchLogger? log,
  RustBridgeApi? rustBridgeApi,
}) async {
  config.validate();
  final logger = log ?? (_) {};
  final startedAt = DateTime.now();
  ScenarioServer? scenarioServer;
  final skippedChannels = <String, String>{};
  var rustInitialized = false;
  var benchmarkOwnsRustEngine = false;
  var runtimeConfig = config;
  String? ownedAutoRustCacheDir;
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
  final rustAdapter = RustAdapter(bridgeApi: rustBridgeApi);

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
        config.initializeRust) {
      logger('[network-bench] initializing rust engine...');
      try {
        final defaultRustCacheDir = config.rustCacheDir == null
            ? _defaultBenchmarkRustCacheDir(startedAt)
            : null;
        runtimeConfig = config.resolveRuntimeConfig(
          defaultRustCacheDir: defaultRustCacheDir,
        );
        ownedAutoRustCacheDir =
            config.rustCacheDir == null && runtimeConfig.rustCacheEnabled
            ? runtimeConfig.resolvedRustCacheDir
            : null;
        await rustAdapter.initializeEngine(
          options: runtimeConfig.toRustEngineInitOptions(),
        );
        rustInitialized = true;
        benchmarkOwnsRustEngine = rustAdapter.ownsEngineScope;
        logger(
          '[network-bench] rust engine initialized'
          '${benchmarkOwnsRustEngine ? ' (owned)' : ' (reused scope)'}',
        );
      } catch (error) {
        final reason = 'rust init failed: $error';
        if (config.requireRust) {
          rethrow;
        }
        skippedChannels[BenchmarkChannel.rust.cliName] = reason;
        logger('[network-bench] skip rust channel, $reason');
      }
    }

    final gateway = NetworkGateway(
      routingPolicy: const RoutingPolicy(),
      featureFlag: NetFeatureFlag(
        enableRustChannel: true,
        enableFallback: config.enableFallback,
      ),
      dioAdapter: dioAdapter,
      rustAdapter: rustAdapter,
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
        config: runtimeConfig,
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
    final rustCacheObservation = rustInitialized
        ? await _observeRustCache(runtimeConfig)
        : null;
    report = BenchmarkReport(
      startedAt: startedAt,
      finishedAt: finishedAt,
      config: runtimeConfig,
      baseUrl: benchmarkBaseUrl,
      rustInitialized: rustInitialized,
      rustCacheObservation: rustCacheObservation,
      skippedChannels: Map.unmodifiable(skippedChannels),
      channelResults: List.unmodifiable(results),
    );
  } catch (error, stackTrace) {
    pendingError = error;
    pendingStackTrace = stackTrace;
  } finally {
    Object? cleanupError;
    StackTrace? cleanupStackTrace;

    if (benchmarkOwnsRustEngine && rustAdapter.isReady) {
      try {
        logger('[network-bench] shutting down owned rust engine...');
        await rustAdapter.shutdownEngine();
        logger('[network-bench] owned rust engine shut down');
      } catch (error, stackTrace) {
        cleanupError = error;
        cleanupStackTrace = stackTrace;
        if (pendingError != null) {
          logger('[network-bench] owned rust engine shutdown failed: $error');
        }
      }
    }

    if (ownedAutoRustCacheDir != null &&
        (!benchmarkOwnsRustEngine || cleanupError == null)) {
      await _deleteDirectoryBestEffort(
        Directory(ownedAutoRustCacheDir),
        logger: logger,
      );
    }

    if (scenarioServer != null) {
      try {
        await scenarioServer.close();
      } catch (error, stackTrace) {
        if (cleanupError == null) {
          cleanupError = error;
          cleanupStackTrace = stackTrace;
        } else if (pendingError != null) {
          logger('[network-bench] scenario server close failed: $error');
        }
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

String _defaultBenchmarkRustCacheDir(DateTime startedAt) {
  final runId =
      '${startedAt.toUtc().microsecondsSinceEpoch}_${_benchmarkCacheRunSequence++}';
  final sharedDefaultRoot = resolveRustCacheDirPath(null);
  final separator = Platform.pathSeparator;
  if (sharedDefaultRoot.endsWith(separator)) {
    return '${sharedDefaultRoot}benchmark_$runId';
  }
  return '$sharedDefaultRoot${Platform.pathSeparator}benchmark_$runId';
}

Future<RustCacheObservation?> _observeRustCache(BenchmarkConfig config) async {
  if (!config.rustCacheEnabled) {
    return null;
  }
  final cacheDir = config.resolvedRustCacheDir;
  final rootBytes = await _directoryFileBytes(Directory(cacheDir));
  return RustCacheObservation(cacheDir: cacheDir, rootBytes: rootBytes);
}

Future<int> _directoryFileBytes(Directory root) async {
  if (!await root.exists()) {
    return 0;
  }

  var total = 0;
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    final metadata = await entity.stat();
    total += metadata.size;
  }
  return total;
}

Future<void> _deleteDirectoryBestEffort(
  Directory directory, {
  required BenchLogger logger,
}) async {
  try {
    if (!await directory.exists()) {
      return;
    }
    await directory.delete(recursive: true);
    logger('[network-bench] deleted owned rust cache dir ${directory.path}');
  } catch (error) {
    logger(
      '[network-bench] failed to delete owned rust cache dir '
      '${directory.path}: $error',
    );
  }
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
