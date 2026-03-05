import 'dart:convert';

import '../net_models.dart';

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
  final int requestKeySpace;
  final String scenarioBaseUrl;

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
    this.rustMaxInFlightTasks = 32,
    this.requestKeySpace = 0,
    this.scenarioBaseUrl = '',
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
    int? requestKeySpace,
    String? scenarioBaseUrl,
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
      requestKeySpace: requestKeySpace ?? this.requestKeySpace,
      scenarioBaseUrl: scenarioBaseUrl ?? this.scenarioBaseUrl,
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
    if (requestKeySpace < 0) {
      throw ArgumentError.value(
        requestKeySpace,
        'requestKeySpace',
        'must be >= 0',
      );
    }
    final normalizedBaseUrl = resolveScenarioBaseUrl(scenarioBaseUrl);
    if (normalizedBaseUrl != null) {
      final uri = Uri.tryParse(normalizedBaseUrl);
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
        throw ArgumentError.value(
          scenarioBaseUrl,
          'scenarioBaseUrl',
          'must be an absolute URL, e.g. http://127.0.0.1:18080',
        );
      }
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        throw ArgumentError.value(
          scenarioBaseUrl,
          'scenarioBaseUrl',
          'only http/https are supported',
        );
      }
      if (uri.hasQuery || uri.hasFragment) {
        throw ArgumentError.value(
          scenarioBaseUrl,
          'scenarioBaseUrl',
          'query and fragment are not allowed',
        );
      }
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
      'requestKeySpace': requestKeySpace,
      'scenarioBaseUrl': scenarioBaseUrl,
    };
  }
}

String? resolveScenarioBaseUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  var normalized = trimmed;
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
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
  final int cacheHitCount;
  final int cacheMissCount;
  final int cacheRevalidateCount;
  final int cacheEvictCount;

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
    required this.cacheHitCount,
    required this.cacheMissCount,
    required this.cacheRevalidateCount,
    required this.cacheEvictCount,
  });

  int get successRequests => completedRequests - exceptions;

  double get exceptionRate =>
      completedRequests == 0 ? 0 : exceptions / completedRequests.toDouble();

  int get cacheObservedRequests => cacheHitCount + cacheMissCount;

  double get cacheHitRate => cacheObservedRequests == 0
      ? 0
      : cacheHitCount / cacheObservedRequests.toDouble();

  ChannelBenchmarkResult copyWith({
    int? cacheRevalidateCount,
    int? cacheEvictCount,
  }) {
    return ChannelBenchmarkResult(
      channel: channel,
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
      throughputRps: throughputRps,
      requestLatencyMs: requestLatencyMs,
      endToEndLatencyMs: endToEndLatencyMs,
      adapterCostLatencyMs: adapterCostLatencyMs,
      consumeAttempted: consumeAttempted,
      consumeSucceeded: consumeSucceeded,
      consumeBytesTotal: consumeBytesTotal,
      consumeLatencyMs: consumeLatencyMs,
      materializeBodyLatencyMs: materializeBodyLatencyMs,
      utf8DecodeLatencyMs: utf8DecodeLatencyMs,
      jsonDecodeLatencyMs: jsonDecodeLatencyMs,
      modelBuildLatencyMs: modelBuildLatencyMs,
      consumeSkippedReasons: consumeSkippedReasons,
      responseChannels: responseChannels,
      routeReasons: routeReasons,
      fallbackReasons: fallbackReasons,
      statusCodes: statusCodes,
      exceptionCodes: exceptionCodes,
      exceptionChannels: exceptionChannels,
      cacheHitCount: cacheHitCount,
      cacheMissCount: cacheMissCount,
      cacheRevalidateCount: cacheRevalidateCount ?? this.cacheRevalidateCount,
      cacheEvictCount: cacheEvictCount ?? this.cacheEvictCount,
    );
  }

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
      'cacheHit=$cacheHitCount',
      'cacheMiss=$cacheMissCount',
      'cacheRevalidate=$cacheRevalidateCount',
      'cacheEvict=$cacheEvictCount',
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
      'cache': {
        'hitCount': cacheHitCount,
        'missCount': cacheMissCount,
        'hitRate': cacheHitRate,
        'revalidateCount': cacheRevalidateCount,
        'evictCount': cacheEvictCount,
      },
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

int _percentile(List<int> sorted, double ratio) {
  if (sorted.isEmpty) {
    return 0;
  }
  final int rank = ((sorted.length - 1) * ratio).round();
  final int safeIndex = rank.clamp(0, sorted.length - 1);
  return sorted[safeIndex];
}
