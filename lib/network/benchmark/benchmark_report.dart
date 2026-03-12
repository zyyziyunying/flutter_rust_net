import 'dart:convert';

import 'benchmark_config.dart';
import 'benchmark_enums.dart';

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
