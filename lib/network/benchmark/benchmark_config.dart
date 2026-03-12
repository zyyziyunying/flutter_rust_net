import 'benchmark_enums.dart';

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
