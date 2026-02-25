import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../dio_adapter.dart';
import '../net_feature_flag.dart';
import '../net_models.dart';
import '../network_gateway.dart';
import '../routing_policy.dart';
import '../rust_adapter.dart';

enum BenchmarkScenario {
  smallJson,
  largeJson,
  largePayload,
  jitterLatency,
  flakyHttp,
}

extension BenchmarkScenarioX on BenchmarkScenario {
  String get cliName {
    switch (this) {
      case BenchmarkScenario.smallJson:
        return 'small_json';
      case BenchmarkScenario.largeJson:
        return 'large_json';
      case BenchmarkScenario.largePayload:
        return 'large_payload';
      case BenchmarkScenario.jitterLatency:
        return 'jitter_latency';
      case BenchmarkScenario.flakyHttp:
        return 'flaky_http';
    }
  }

  String get path {
    switch (this) {
      case BenchmarkScenario.smallJson:
        return '/bench/small-json';
      case BenchmarkScenario.largeJson:
        return '/bench/large-json';
      case BenchmarkScenario.largePayload:
        return '/bench/large-payload';
      case BenchmarkScenario.jitterLatency:
        return '/bench/jitter';
      case BenchmarkScenario.flakyHttp:
        return '/bench/flaky';
    }
  }

  static BenchmarkScenario parse(String raw) {
    for (final candidate in BenchmarkScenario.values) {
      if (candidate.cliName == raw) {
        return candidate;
      }
    }
    throw ArgumentError(
      'unsupported scenario: $raw. '
      'supported: ${BenchmarkScenario.values.map((item) => item.cliName).join(', ')}',
    );
  }
}

enum BenchmarkChannel { dio, rust }

extension BenchmarkChannelX on BenchmarkChannel {
  String get cliName {
    switch (this) {
      case BenchmarkChannel.dio:
        return 'dio';
      case BenchmarkChannel.rust:
        return 'rust';
    }
  }

  NetChannel get netChannel {
    switch (this) {
      case BenchmarkChannel.dio:
        return NetChannel.dio;
      case BenchmarkChannel.rust:
        return NetChannel.rust;
    }
  }

  static Set<BenchmarkChannel> parseList(String raw) {
    final channels = <BenchmarkChannel>{};
    for (final token in raw.split(',')) {
      final value = token.trim();
      if (value.isEmpty) {
        continue;
      }
      channels.add(parse(value));
    }
    if (channels.isEmpty) {
      throw ArgumentError('channels cannot be empty');
    }
    return channels;
  }

  static BenchmarkChannel parse(String raw) {
    for (final candidate in BenchmarkChannel.values) {
      if (candidate.cliName == raw) {
        return candidate;
      }
    }
    throw ArgumentError(
      'unsupported channel: $raw. '
      'supported: ${BenchmarkChannel.values.map((item) => item.cliName).join(', ')}',
    );
  }
}

enum BenchmarkConsumeMode { none, jsonDecode, jsonModel }

extension BenchmarkConsumeModeX on BenchmarkConsumeMode {
  String get cliName {
    switch (this) {
      case BenchmarkConsumeMode.none:
        return 'none';
      case BenchmarkConsumeMode.jsonDecode:
        return 'json_decode';
      case BenchmarkConsumeMode.jsonModel:
        return 'json_model';
    }
  }

  static BenchmarkConsumeMode parse(String raw) {
    for (final candidate in BenchmarkConsumeMode.values) {
      if (candidate.cliName == raw) {
        return candidate;
      }
    }
    throw ArgumentError(
      'unsupported consume mode: $raw. '
      'supported: ${BenchmarkConsumeMode.values.map((item) => item.cliName).join(', ')}',
    );
  }
}

class BenchmarkConfig {
  final BenchmarkScenario scenario;
  final BenchmarkConsumeMode consumeMode;
  final int requests;
  final int warmupRequests;
  final int concurrency;
  final Set<BenchmarkChannel> channels;
  final bool initializeRust;
  final bool requireRust;
  final bool enableFallback;
  final bool verbose;
  final int largePayloadBytes;
  final int jitterBaseDelayMs;
  final int jitterExtraDelayMs;
  final int flakyFailureEvery;
  final Duration dioConnectTimeout;
  final Duration dioReceiveTimeout;
  final int rustMaxInFlightTasks;

  const BenchmarkConfig({
    this.scenario = BenchmarkScenario.smallJson,
    this.consumeMode = BenchmarkConsumeMode.none,
    this.requests = 120,
    this.warmupRequests = 12,
    this.concurrency = 12,
    this.channels = const {BenchmarkChannel.dio, BenchmarkChannel.rust},
    this.initializeRust = true,
    this.requireRust = false,
    this.enableFallback = true,
    this.verbose = true,
    this.largePayloadBytes = 2 * 1024 * 1024,
    this.jitterBaseDelayMs = 12,
    this.jitterExtraDelayMs = 80,
    this.flakyFailureEvery = 5,
    this.dioConnectTimeout = const Duration(seconds: 5),
    this.dioReceiveTimeout = const Duration(seconds: 15),
    this.rustMaxInFlightTasks = 12,
  });

  BenchmarkConfig copyWith({
    BenchmarkScenario? scenario,
    BenchmarkConsumeMode? consumeMode,
    int? requests,
    int? warmupRequests,
    int? concurrency,
    Set<BenchmarkChannel>? channels,
    bool? initializeRust,
    bool? requireRust,
    bool? enableFallback,
    bool? verbose,
    int? largePayloadBytes,
    int? jitterBaseDelayMs,
    int? jitterExtraDelayMs,
    int? flakyFailureEvery,
    Duration? dioConnectTimeout,
    Duration? dioReceiveTimeout,
    int? rustMaxInFlightTasks,
  }) {
    return BenchmarkConfig(
      scenario: scenario ?? this.scenario,
      consumeMode: consumeMode ?? this.consumeMode,
      requests: requests ?? this.requests,
      warmupRequests: warmupRequests ?? this.warmupRequests,
      concurrency: concurrency ?? this.concurrency,
      channels: channels ?? this.channels,
      initializeRust: initializeRust ?? this.initializeRust,
      requireRust: requireRust ?? this.requireRust,
      enableFallback: enableFallback ?? this.enableFallback,
      verbose: verbose ?? this.verbose,
      largePayloadBytes: largePayloadBytes ?? this.largePayloadBytes,
      jitterBaseDelayMs: jitterBaseDelayMs ?? this.jitterBaseDelayMs,
      jitterExtraDelayMs: jitterExtraDelayMs ?? this.jitterExtraDelayMs,
      flakyFailureEvery: flakyFailureEvery ?? this.flakyFailureEvery,
      dioConnectTimeout: dioConnectTimeout ?? this.dioConnectTimeout,
      dioReceiveTimeout: dioReceiveTimeout ?? this.dioReceiveTimeout,
      rustMaxInFlightTasks: rustMaxInFlightTasks ?? this.rustMaxInFlightTasks,
    );
  }

  void validate() {
    if (requests <= 0) {
      throw ArgumentError.value(requests, 'requests', 'must be > 0');
    }
    if (warmupRequests < 0) {
      throw ArgumentError.value(
        warmupRequests,
        'warmupRequests',
        'must be >= 0',
      );
    }
    if (concurrency <= 0) {
      throw ArgumentError.value(concurrency, 'concurrency', 'must be > 0');
    }
    if (channels.isEmpty) {
      throw ArgumentError.value(channels, 'channels', 'cannot be empty');
    }
    if (largePayloadBytes < 64 * 1024) {
      throw ArgumentError.value(
        largePayloadBytes,
        'largePayloadBytes',
        'must be >= 65536',
      );
    }
    if (jitterBaseDelayMs < 0 || jitterExtraDelayMs < 0) {
      throw ArgumentError(
        'jitterBaseDelayMs and jitterExtraDelayMs must be >= 0',
      );
    }
    if (flakyFailureEvery < 2) {
      throw ArgumentError.value(
        flakyFailureEvery,
        'flakyFailureEvery',
        'must be >= 2',
      );
    }
    if (rustMaxInFlightTasks <= 0) {
      throw ArgumentError.value(
        rustMaxInFlightTasks,
        'rustMaxInFlightTasks',
        'must be > 0',
      );
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'scenario': scenario.cliName,
      'consumeMode': consumeMode.cliName,
      'requests': requests,
      'warmupRequests': warmupRequests,
      'concurrency': concurrency,
      'channels': channels.map((item) => item.cliName).toList()..sort(),
      'initializeRust': initializeRust,
      'requireRust': requireRust,
      'enableFallback': enableFallback,
      'verbose': verbose,
      'largePayloadBytes': largePayloadBytes,
      'jitterBaseDelayMs': jitterBaseDelayMs,
      'jitterExtraDelayMs': jitterExtraDelayMs,
      'flakyFailureEvery': flakyFailureEvery,
      'dioConnectTimeoutMs': dioConnectTimeout.inMilliseconds,
      'dioReceiveTimeoutMs': dioReceiveTimeout.inMilliseconds,
      'rustMaxInFlightTasks': rustMaxInFlightTasks,
    };
  }
}

class BenchmarkReport {
  final DateTime startedAt;
  final DateTime finishedAt;
  final BenchmarkConfig config;
  final String baseUrl;
  final bool rustInitialized;
  final Map<String, String> skippedChannels;
  final List<ChannelBenchmarkResult> channelResults;

  const BenchmarkReport({
    required this.startedAt,
    required this.finishedAt,
    required this.config,
    required this.baseUrl,
    required this.rustInitialized,
    required this.skippedChannels,
    required this.channelResults,
  });

  Duration get wallClockDuration => finishedAt.difference(startedAt);

  Map<String, dynamic> toJson() {
    return {
      'startedAt': startedAt.toIso8601String(),
      'finishedAt': finishedAt.toIso8601String(),
      'wallClockMs': wallClockDuration.inMilliseconds,
      'baseUrl': baseUrl,
      'rustInitialized': rustInitialized,
      'config': config.toJson(),
      'skippedChannels': skippedChannels,
      'channelResults': channelResults.map((item) => item.toJson()).toList(),
    };
  }

  String toPrettyText() {
    final lines = <String>[
      '[network-bench] scenario=${config.scenario.cliName} '
          'consumeMode=${config.consumeMode.cliName} '
          'requests=${config.requests} '
          'concurrency=${config.concurrency} '
          'warmup=${config.warmupRequests}',
      '[network-bench] baseUrl=$baseUrl '
          'rustInitialized=$rustInitialized '
          'enableFallback=${config.enableFallback}',
    ];
    if (skippedChannels.isNotEmpty) {
      lines.add('[network-bench] skipped=${jsonEncode(skippedChannels)}');
    }
    for (final result in channelResults) {
      lines.add(
        '[network-bench][${result.channel}] ${result.toOneLineSummary()}',
      );
    }
    return lines.join('\n');
  }
}

class ChannelBenchmarkResult {
  final String channel;
  final int warmupRequests;
  final int totalRequests;
  final int completedRequests;
  final int exceptions;
  final int http2xx;
  final int http4xx;
  final int http5xx;
  final int fallbackCount;
  final int bridgeBytesTotal;
  final int inlineBodyResponses;
  final int fileBodyResponses;
  final double throughputRps;
  final LatencySnapshot requestLatencyMs;
  final LatencySnapshot endToEndLatencyMs;
  final LatencySnapshot adapterCostLatencyMs;
  final int consumeAttempted;
  final int consumeSucceeded;
  final int consumeBytesTotal;
  final LatencySnapshot consumeLatencyMs;
  final LatencySnapshot materializeBodyLatencyMs;
  final LatencySnapshot utf8DecodeLatencyMs;
  final LatencySnapshot jsonDecodeLatencyMs;
  final LatencySnapshot modelBuildLatencyMs;
  final Map<String, int> consumeSkippedReasons;
  final Map<String, int> responseChannels;
  final Map<String, int> routeReasons;
  final Map<String, int> fallbackReasons;
  final Map<String, int> statusCodes;
  final Map<String, int> exceptionCodes;
  final Map<String, int> exceptionChannels;

  const ChannelBenchmarkResult({
    required this.channel,
    required this.warmupRequests,
    required this.totalRequests,
    required this.completedRequests,
    required this.exceptions,
    required this.http2xx,
    required this.http4xx,
    required this.http5xx,
    required this.fallbackCount,
    required this.bridgeBytesTotal,
    required this.inlineBodyResponses,
    required this.fileBodyResponses,
    required this.throughputRps,
    required this.requestLatencyMs,
    required this.endToEndLatencyMs,
    required this.adapterCostLatencyMs,
    required this.consumeAttempted,
    required this.consumeSucceeded,
    required this.consumeBytesTotal,
    required this.consumeLatencyMs,
    required this.materializeBodyLatencyMs,
    required this.utf8DecodeLatencyMs,
    required this.jsonDecodeLatencyMs,
    required this.modelBuildLatencyMs,
    required this.consumeSkippedReasons,
    required this.responseChannels,
    required this.routeReasons,
    required this.fallbackReasons,
    required this.statusCodes,
    required this.exceptionCodes,
    required this.exceptionChannels,
  });

  int get successRequests => completedRequests - exceptions;

  double get exceptionRate =>
      completedRequests == 0 ? 0 : exceptions / completedRequests.toDouble();

  String toOneLineSummary() {
    return [
      'completed=$completedRequests/$totalRequests',
      'exceptions=$exceptions',
      'http2xx=$http2xx',
      'http4xx=$http4xx',
      'http5xx=$http5xx',
      'fallback=$fallbackCount',
      'bridgeBytes=$bridgeBytesTotal',
      'inline=$inlineBodyResponses',
      'file=$fileBodyResponses',
      'reqP95=${requestLatencyMs.p95Ms}ms',
      'e2eP95=${endToEndLatencyMs.p95Ms}ms',
      if (consumeAttempted > 0) 'consumeP95=${consumeLatencyMs.p95Ms}ms',
      'throughput=${throughputRps.toStringAsFixed(2)} req/s',
    ].join(', ');
  }

  Map<String, dynamic> toJson() {
    return {
      'channel': channel,
      'warmupRequests': warmupRequests,
      'totalRequests': totalRequests,
      'completedRequests': completedRequests,
      'exceptions': exceptions,
      'exceptionRate': exceptionRate,
      'http2xx': http2xx,
      'http4xx': http4xx,
      'http5xx': http5xx,
      'fallbackCount': fallbackCount,
      'bridgeBytesTotal': bridgeBytesTotal,
      'inlineBodyResponses': inlineBodyResponses,
      'fileBodyResponses': fileBodyResponses,
      'throughputRps': throughputRps,
      'requestLatencyMs': requestLatencyMs.toJson(),
      'endToEndLatencyMs': endToEndLatencyMs.toJson(),
      'adapterCostLatencyMs': adapterCostLatencyMs.toJson(),
      'consume': {
        'attempted': consumeAttempted,
        'succeeded': consumeSucceeded,
        'bytesTotal': consumeBytesTotal,
        'latencyMs': consumeLatencyMs.toJson(),
        'materializeBodyLatencyMs': materializeBodyLatencyMs.toJson(),
        'utf8DecodeLatencyMs': utf8DecodeLatencyMs.toJson(),
        'jsonDecodeLatencyMs': jsonDecodeLatencyMs.toJson(),
        'modelBuildLatencyMs': modelBuildLatencyMs.toJson(),
        'skippedReasons': consumeSkippedReasons,
      },
      'responseChannels': responseChannels,
      'routeReasons': routeReasons,
      'fallbackReasons': fallbackReasons,
      'statusCodes': statusCodes,
      'exceptionCodes': exceptionCodes,
      'exceptionChannels': exceptionChannels,
    };
  }
}

class LatencySnapshot {
  final int count;
  final int minMs;
  final int maxMs;
  final int p50Ms;
  final int p95Ms;
  final int p99Ms;
  final double avgMs;

  const LatencySnapshot({
    required this.count,
    required this.minMs,
    required this.maxMs,
    required this.p50Ms,
    required this.p95Ms,
    required this.p99Ms,
    required this.avgMs,
  });

  factory LatencySnapshot.fromSamples(List<int> samples) {
    if (samples.isEmpty) {
      return const LatencySnapshot(
        count: 0,
        minMs: 0,
        maxMs: 0,
        p50Ms: 0,
        p95Ms: 0,
        p99Ms: 0,
        avgMs: 0,
      );
    }

    final sorted = [...samples]..sort();
    final sum = sorted.fold<int>(0, (acc, item) => acc + item);
    return LatencySnapshot(
      count: sorted.length,
      minMs: sorted.first,
      maxMs: sorted.last,
      p50Ms: _percentile(sorted, 0.50),
      p95Ms: _percentile(sorted, 0.95),
      p99Ms: _percentile(sorted, 0.99),
      avgMs: sum / sorted.length,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'count': count,
      'minMs': minMs,
      'maxMs': maxMs,
      'p50Ms': p50Ms,
      'p95Ms': p95Ms,
      'p99Ms': p99Ms,
      'avgMs': avgMs,
    };
  }
}

typedef BenchLogger = void Function(String message);

Future<BenchmarkReport> runNetworkBenchmark(
  BenchmarkConfig config, {
  BenchLogger? log,
}) async {
  config.validate();
  final logger = log ?? (_) {};
  final startedAt = DateTime.now();
  final scenarioServer = await _ScenarioServer.start(config, logger: logger);
  final skippedChannels = <String, String>{};
  var rustInitialized = false;

  final dioAdapter = DioAdapter(
    client: Dio(
      BaseOptions(
        connectTimeout: config.dioConnectTimeout,
        receiveTimeout: config.dioReceiveTimeout,
        sendTimeout: config.dioConnectTimeout,
      ),
    ),
  );
  final rustAdapter = RustAdapter();

  try {
    if (config.channels.contains(BenchmarkChannel.rust) &&
        config.initializeRust) {
      logger('[network-bench] initializing rust engine...');
      try {
        await rustAdapter.initializeEngine(
          options: RustEngineInitOptions(
            maxInFlightTasks: config.rustMaxInFlightTasks,
          ),
        );
        rustInitialized = true;
        logger('[network-bench] rust engine initialized');
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
        baseUrl: scenarioServer.baseUrl,
        logger: logger,
      );
      results.add(result);
      logger(
        '[network-bench][${channel.cliName}] ${result.toOneLineSummary()}',
      );
    }

    final finishedAt = DateTime.now();
    return BenchmarkReport(
      startedAt: startedAt,
      finishedAt: finishedAt,
      config: config,
      baseUrl: scenarioServer.baseUrl,
      rustInitialized: rustInitialized,
      skippedChannels: Map.unmodifiable(skippedChannels),
      channelResults: List.unmodifiable(results),
    );
  } finally {
    await scenarioServer.close();
  }
}

Future<ChannelBenchmarkResult> _runChannelBenchmark({
  required BenchmarkConfig config,
  required NetworkGateway gateway,
  required BenchmarkChannel channel,
  required String baseUrl,
  required BenchLogger logger,
}) async {
  final accumulator = _ChannelRunAccumulator(
    channelName: channel.cliName,
    totalRequests: config.requests,
    warmupRequests: config.warmupRequests,
  );

  await _runWarmup(
    config: config,
    gateway: gateway,
    channel: channel,
    baseUrl: baseUrl,
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
      );
      final totalWatch = Stopwatch()..start();
      try {
        final response = await gateway.request(request);
        final requestMs = totalWatch.elapsedMilliseconds;
        final consume = await _consumeResponse(
          config: config,
          response: response,
        );
        totalWatch.stop();
        accumulator.recordResponse(
          response: response,
          requestMs: requestMs,
          endToEndMs: totalWatch.elapsedMilliseconds,
          consume: consume,
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
}) {
  final query = <String, dynamic>{'id': requestIndex};
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

  return NetRequest(
    method: 'GET',
    url: uri.toString(),
    expectLargeResponse: isLarge,
    contentLengthHint: isLarge ? config.largePayloadBytes : null,
    forceChannel: channel.netChannel,
  );
}

class _ConsumeMetrics {
  final bool attempted;
  final bool succeeded;
  final int totalMs;
  final int materializeBodyMs;
  final int utf8DecodeMs;
  final int jsonDecodeMs;
  final int modelBuildMs;
  final int bodyBytes;
  final String? skippedReason;

  const _ConsumeMetrics({
    required this.attempted,
    required this.succeeded,
    required this.totalMs,
    required this.materializeBodyMs,
    required this.utf8DecodeMs,
    required this.jsonDecodeMs,
    required this.modelBuildMs,
    required this.bodyBytes,
  }) : skippedReason = null;

  const _ConsumeMetrics.notAttempted()
    : attempted = false,
      succeeded = false,
      totalMs = 0,
      materializeBodyMs = 0,
      utf8DecodeMs = 0,
      jsonDecodeMs = 0,
      modelBuildMs = 0,
      bodyBytes = 0,
      skippedReason = null;

  const _ConsumeMetrics.skipped({
    required String reason,
    this.totalMs = 0,
    this.materializeBodyMs = 0,
    this.bodyBytes = 0,
  }) : attempted = true,
       succeeded = false,
       utf8DecodeMs = 0,
       jsonDecodeMs = 0,
       modelBuildMs = 0,
       skippedReason = reason;
}

Future<_ConsumeMetrics> _consumeResponse({
  required BenchmarkConfig config,
  required NetResponse response,
}) async {
  if (config.consumeMode == BenchmarkConsumeMode.none) {
    return const _ConsumeMetrics.notAttempted();
  }

  final contentType = _extractContentType(response.headers);
  if (!_isJsonContentType(contentType)) {
    return const _ConsumeMetrics.skipped(reason: 'non_json_content_type');
  }

  final totalWatch = Stopwatch()..start();
  final materializeWatch = Stopwatch()..start();
  final bodyBytes = await _materializeBodyBytes(response);
  materializeWatch.stop();

  if (bodyBytes.isEmpty) {
    totalWatch.stop();
    return _ConsumeMetrics.skipped(
      reason: 'empty_body',
      totalMs: totalWatch.elapsedMilliseconds,
      materializeBodyMs: materializeWatch.elapsedMilliseconds,
      bodyBytes: bodyBytes.length,
    );
  }

  final utf8Watch = Stopwatch()..start();
  final decoded = utf8.decode(bodyBytes);
  utf8Watch.stop();

  final jsonWatch = Stopwatch()..start();
  final jsonValue = jsonDecode(decoded);
  jsonWatch.stop();

  var modelBuildMs = 0;
  if (config.consumeMode == BenchmarkConsumeMode.jsonModel) {
    final modelWatch = Stopwatch()..start();
    final rebuilt = _rebuildJsonObjectGraph(jsonValue);
    if (rebuilt is Map || rebuilt is List) {}
    modelWatch.stop();
    modelBuildMs = modelWatch.elapsedMilliseconds;
  } else {
    if (jsonValue is Map || jsonValue is List) {}
  }

  totalWatch.stop();
  return _ConsumeMetrics(
    attempted: true,
    succeeded: true,
    totalMs: totalWatch.elapsedMilliseconds,
    materializeBodyMs: materializeWatch.elapsedMilliseconds,
    utf8DecodeMs: utf8Watch.elapsedMilliseconds,
    jsonDecodeMs: jsonWatch.elapsedMilliseconds,
    modelBuildMs: modelBuildMs,
    bodyBytes: bodyBytes.length,
  );
}

Future<List<int>> _materializeBodyBytes(NetResponse response) async {
  final inline = response.bodyBytes;
  if (inline != null) {
    return inline;
  }
  final filePath = response.bodyFilePath;
  if (filePath == null || filePath.isEmpty) {
    return const <int>[];
  }
  final file = File(filePath);
  try {
    return await file.readAsBytes();
  } finally {
    await _deleteMaterializedFileQuietly(file);
  }
}

Future<void> _deleteMaterializedFileQuietly(File file) async {
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } on FileSystemException {
    // best effort cleanup only
  }
}

String? _extractContentType(Map<String, String> headers) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == HttpHeaders.contentTypeHeader) {
      return entry.value.toLowerCase();
    }
  }
  return null;
}

bool _isJsonContentType(String? contentType) {
  if (contentType == null || contentType.isEmpty) {
    return true;
  }
  return contentType.contains('/json') || contentType.contains('+json');
}

Object? _rebuildJsonObjectGraph(Object? node) {
  if (node is Map) {
    final copied = <String, Object?>{};
    node.forEach((key, value) {
      copied[key.toString()] = _rebuildJsonObjectGraph(value);
    });
    return copied;
  }
  if (node is List) {
    return node.map<Object?>(_rebuildJsonObjectGraph).toList(growable: false);
  }
  return node;
}

class _ScenarioServer {
  final HttpServer _server;
  final BenchmarkConfig _config;
  final BenchLogger _logger;
  final Uint8List _largePayload;
  final List<int> _largeJsonPayload;
  final List<int> _smallJsonPayload;

  _ScenarioServer._({
    required HttpServer server,
    required BenchmarkConfig config,
    required BenchLogger logger,
    required Uint8List largePayload,
    required List<int> largeJsonPayload,
    required List<int> smallJsonPayload,
  }) : _server = server,
       _config = config,
       _logger = logger,
       _largePayload = largePayload,
       _largeJsonPayload = largeJsonPayload,
       _smallJsonPayload = smallJsonPayload;

  String get baseUrl => 'http://${_server.address.address}:${_server.port}';

  static Future<_ScenarioServer> start(
    BenchmarkConfig config, {
    required BenchLogger logger,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final largePayload = _buildLargePayload(config.largePayloadBytes);
    final largeJsonPayload = _buildLargeJsonPayload(config.largePayloadBytes);
    final smallJsonPayload = utf8.encode(
      jsonEncode({
        'title': 'network-bench',
        'ok': true,
        'payload': List.filled(160, 'x').join(),
      }),
    );

    final instance = _ScenarioServer._(
      server: server,
      config: config,
      logger: logger,
      largePayload: largePayload,
      largeJsonPayload: largeJsonPayload,
      smallJsonPayload: smallJsonPayload,
    );
    instance._listen();
    logger('[network-bench] local scenario server at ${instance.baseUrl}');
    return instance;
  }

  void _listen() {
    _server.listen((request) async {
      if (request.method != 'GET') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }

      try {
        switch (request.uri.path) {
          case '/bench/small-json':
            await _handleSmallJson(request);
            return;
          case '/bench/large-json':
            await _handleLargeJson(request);
            return;
          case '/bench/large-payload':
            await _handleLargePayload(request);
            return;
          case '/bench/jitter':
            await _handleJitter(request);
            return;
          case '/bench/flaky':
            await _handleFlaky(request);
            return;
          default:
            request.response.statusCode = HttpStatus.notFound;
            request.response.write('not found');
            await request.response.close();
        }
      } catch (error) {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('server_error:$error');
        await request.response.close();
      }
    });
  }

  Future<void> _handleSmallJson(HttpRequest request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..headers.set(HttpHeaders.contentLengthHeader, _smallJsonPayload.length)
      ..add(_smallJsonPayload);
    await request.response.close();
  }

  Future<void> _handleLargePayload(HttpRequest request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.binary
      ..headers.set(HttpHeaders.contentLengthHeader, _largePayload.length)
      ..add(_largePayload);
    await request.response.close();
  }

  Future<void> _handleLargeJson(HttpRequest request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..headers.set(HttpHeaders.contentLengthHeader, _largeJsonPayload.length)
      ..add(_largeJsonPayload);
    await request.response.close();
  }

  Future<void> _handleJitter(HttpRequest request) async {
    final id = _parseInt(request.uri.queryParameters['id'], fallback: 0);
    final baseDelayMs = _parseInt(
      request.uri.queryParameters['baseDelayMs'],
      fallback: _config.jitterBaseDelayMs,
    );
    final extraDelayMs = _parseInt(
      request.uri.queryParameters['extraDelayMs'],
      fallback: _config.jitterExtraDelayMs,
    );
    final delayMs = baseDelayMs + (id.abs() % (extraDelayMs + 1));

    await Future<void>.delayed(Duration(milliseconds: delayMs));
    final body = utf8.encode(
      jsonEncode({'id': id, 'delayMs': delayMs, 'kind': 'jitter'}),
    );
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..headers.set(HttpHeaders.contentLengthHeader, body.length)
      ..add(body);
    await request.response.close();
  }

  Future<void> _handleFlaky(HttpRequest request) async {
    final id = _parseInt(request.uri.queryParameters['id'], fallback: 0);
    final failureEvery = _parseInt(
      request.uri.queryParameters['failureEvery'],
      fallback: _config.flakyFailureEvery,
    );
    final shouldFail = ((id + 1).abs() % failureEvery) == 0;

    if (shouldFail) {
      request.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..headers.contentType = ContentType.text
        ..write('temporary_unavailable');
      await request.response.close();
      return;
    }

    final body = utf8.encode(
      jsonEncode({'id': id, 'kind': 'flaky', 'ok': true}),
    );
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..headers.set(HttpHeaders.contentLengthHeader, body.length)
      ..add(body);
    await request.response.close();
  }

  Future<void> close() async {
    _logger('[network-bench] closing local scenario server');
    await _server.close(force: true);
  }
}

class _ChannelRunAccumulator {
  final String channelName;
  final int totalRequests;
  final int warmupRequests;

  int completedRequests = 0;
  int exceptions = 0;
  int http2xx = 0;
  int http4xx = 0;
  int http5xx = 0;
  int fallbackCount = 0;
  int bridgeBytesTotal = 0;
  int inlineBodyResponses = 0;
  int fileBodyResponses = 0;
  int consumeAttempted = 0;
  int consumeSucceeded = 0;
  int consumeBytesTotal = 0;

  final List<int> _requestLatencyMs = [];
  final List<int> _endToEndLatencyMs = [];
  final List<int> _adapterCostLatencyMs = [];
  final List<int> _consumeLatencyMs = [];
  final List<int> _materializeBodyLatencyMs = [];
  final List<int> _utf8DecodeLatencyMs = [];
  final List<int> _jsonDecodeLatencyMs = [];
  final List<int> _modelBuildLatencyMs = [];
  final Map<String, int> _consumeSkippedReasons = {};
  final Map<String, int> _responseChannels = {};
  final Map<String, int> _routeReasons = {};
  final Map<String, int> _fallbackReasons = {};
  final Map<String, int> _statusCodes = {};
  final Map<String, int> _exceptionCodes = {};
  final Map<String, int> _exceptionChannels = {};

  _ChannelRunAccumulator({
    required this.channelName,
    required this.totalRequests,
    required this.warmupRequests,
  });

  void recordResponse({
    required NetResponse response,
    required int requestMs,
    required int endToEndMs,
    required _ConsumeMetrics consume,
  }) {
    completedRequests += 1;
    _requestLatencyMs.add(requestMs);
    _endToEndLatencyMs.add(endToEndMs);
    _adapterCostLatencyMs.add(response.costMs);
    bridgeBytesTotal += response.bridgeBytes;
    if (response.bodyFilePath != null && response.bodyFilePath!.isNotEmpty) {
      fileBodyResponses += 1;
    } else if (response.bodyBytes != null) {
      inlineBodyResponses += 1;
    }
    if (consume.attempted) {
      consumeAttempted += 1;
      if (consume.succeeded) {
        consumeSucceeded += 1;
        consumeBytesTotal += consume.bodyBytes;
        _consumeLatencyMs.add(consume.totalMs);
        _materializeBodyLatencyMs.add(consume.materializeBodyMs);
        _utf8DecodeLatencyMs.add(consume.utf8DecodeMs);
        _jsonDecodeLatencyMs.add(consume.jsonDecodeMs);
        _modelBuildLatencyMs.add(consume.modelBuildMs);
      } else {
        _increment(_consumeSkippedReasons, consume.skippedReason ?? 'unknown');
      }
    }
    _increment(_responseChannels, response.channel.name);
    _increment(_statusCodes, response.statusCode.toString());
    _increment(_routeReasons, response.routeReason ?? '-');
    if (response.fallbackReason != null &&
        response.fallbackReason!.isNotEmpty) {
      _increment(_fallbackReasons, response.fallbackReason!);
    }
    if (response.fromFallback) {
      fallbackCount += 1;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      http2xx += 1;
    } else if (response.statusCode >= 400 && response.statusCode < 500) {
      http4xx += 1;
    } else if (response.statusCode >= 500) {
      http5xx += 1;
    }
  }

  void recordError({
    required Object error,
    required int requestMs,
    required int endToEndMs,
  }) {
    completedRequests += 1;
    exceptions += 1;
    _requestLatencyMs.add(requestMs);
    _endToEndLatencyMs.add(endToEndMs);

    if (error is NetException) {
      _increment(_exceptionCodes, error.code.name);
      _increment(_exceptionChannels, error.channel.name);
      return;
    }
    _increment(_exceptionCodes, 'unknown');
    _increment(_exceptionChannels, 'unknown');
  }

  ChannelBenchmarkResult finish({required int wallElapsedMs}) {
    final throughput = wallElapsedMs <= 0
        ? 0.0
        : completedRequests * 1000 / wallElapsedMs;
    return ChannelBenchmarkResult(
      channel: channelName,
      warmupRequests: warmupRequests,
      totalRequests: totalRequests,
      completedRequests: completedRequests,
      exceptions: exceptions,
      http2xx: http2xx,
      http4xx: http4xx,
      http5xx: http5xx,
      fallbackCount: fallbackCount,
      bridgeBytesTotal: bridgeBytesTotal,
      inlineBodyResponses: inlineBodyResponses,
      fileBodyResponses: fileBodyResponses,
      throughputRps: throughput,
      requestLatencyMs: LatencySnapshot.fromSamples(_requestLatencyMs),
      endToEndLatencyMs: LatencySnapshot.fromSamples(_endToEndLatencyMs),
      adapterCostLatencyMs: LatencySnapshot.fromSamples(_adapterCostLatencyMs),
      consumeAttempted: consumeAttempted,
      consumeSucceeded: consumeSucceeded,
      consumeBytesTotal: consumeBytesTotal,
      consumeLatencyMs: LatencySnapshot.fromSamples(_consumeLatencyMs),
      materializeBodyLatencyMs: LatencySnapshot.fromSamples(
        _materializeBodyLatencyMs,
      ),
      utf8DecodeLatencyMs: LatencySnapshot.fromSamples(_utf8DecodeLatencyMs),
      jsonDecodeLatencyMs: LatencySnapshot.fromSamples(_jsonDecodeLatencyMs),
      modelBuildLatencyMs: LatencySnapshot.fromSamples(_modelBuildLatencyMs),
      consumeSkippedReasons: _sortedView(_consumeSkippedReasons),
      responseChannels: _sortedView(_responseChannels),
      routeReasons: _sortedView(_routeReasons),
      fallbackReasons: _sortedView(_fallbackReasons),
      statusCodes: _sortedView(_statusCodes),
      exceptionCodes: _sortedView(_exceptionCodes),
      exceptionChannels: _sortedView(_exceptionChannels),
    );
  }
}

Uint8List _buildLargePayload(int bytes) {
  final data = Uint8List(bytes);
  for (var i = 0; i < bytes; i += 1) {
    data[i] = i % 251;
  }
  return data;
}

List<int> _buildLargeJsonPayload(int targetBytes) {
  final safeTargetBytes = max(64 * 1024, targetBytes);
  var payloadChars = max(1024, safeTargetBytes - 256);
  var encoded = const <int>[];

  for (var i = 0; i < 3; i += 1) {
    final payload = List.filled(payloadChars, 'x').join();
    encoded = utf8.encode(
      jsonEncode({
        'title': 'network-bench-large-json',
        'ok': true,
        'payload': payload,
      }),
    );

    final delta = safeTargetBytes - encoded.length;
    if (delta.abs() <= 512) {
      break;
    }
    payloadChars = max(1024, payloadChars + delta);
  }

  return encoded;
}

int _parseInt(String? raw, {required int fallback}) {
  final value = int.tryParse(raw ?? '');
  return value ?? fallback;
}

int _percentile(List<int> sorted, double ratio) {
  if (sorted.isEmpty) {
    return 0;
  }
  final int rank = ((sorted.length - 1) * ratio).round();
  final int safeIndex = rank.clamp(0, sorted.length - 1);
  return sorted[safeIndex];
}

Map<String, int> _sortedView(Map<String, int> source) {
  final entries = source.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return Map<String, int>.fromEntries(entries);
}

void _increment(Map<String, int> map, String key) {
  map[key] = (map[key] ?? 0) + 1;
}
