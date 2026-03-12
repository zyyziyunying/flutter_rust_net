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
