import '../net_models.dart';
import 'benchmark_response_consumer.dart';
import 'benchmark_types.dart';

class ChannelRunAccumulator {
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
  int cacheHitCount = 0;
  int cacheMissCount = 0;
  int repeatedMissCount = 0;

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
  final Set<String> _seenRequestKeys = <String>{};

  ChannelRunAccumulator({
    required this.channelName,
    required this.totalRequests,
    required this.warmupRequests,
  });

  void recordResponse({
    required NetResponse response,
    required int requestMs,
    required int endToEndMs,
    required ConsumeMetrics consume,
    required String requestKey,
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
    final isRepeatedRequest = !_seenRequestKeys.add(requestKey);
    if (response.fromCache) {
      cacheHitCount += 1;
    } else {
      cacheMissCount += 1;
      if (isRepeatedRequest) {
        repeatedMissCount += 1;
      }
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
      cacheHitCount: cacheHitCount,
      cacheMissCount: cacheMissCount,
      repeatedMissCount: repeatedMissCount,
      cacheRevalidateCount: null,
      cacheEvictCount: null,
    );
  }
}

Map<String, int> _sortedView(Map<String, int> source) {
  final entries = source.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return Map<String, int>.fromEntries(entries);
}

void _increment(Map<String, int> map, String key) {
  map[key] = (map[key] ?? 0) + 1;
}
