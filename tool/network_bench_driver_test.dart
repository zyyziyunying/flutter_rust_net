import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/benchmark/network_benchmark_harness.dart';

const String _kBenchArgsEnv = 'FRN_NETWORK_BENCH_ARGS_JSON';

void main() {
  test('network_bench_driver', () async {
    final rawArgs = Platform.environment[_kBenchArgsEnv];
    if (rawArgs == null || rawArgs.isEmpty) {
      throw StateError('missing $_kBenchArgsEnv');
    }

    final decoded = jsonDecode(rawArgs);
    if (decoded is! List) {
      throw StateError('$_kBenchArgsEnv must decode to a JSON array');
    }

    final args = decoded.map((item) => '$item').toList(growable: false);
    final kvArgs = _parseArgs(args);
    final config = _buildConfig(kvArgs);
    final report = await runNetworkBenchmark(
      config,
      log: (message) {
        if (config.verbose) {
          stdout.writeln(message);
        }
      },
    );

    stdout.writeln(report.toPrettyText());

    final outputPath = kvArgs['output'];
    if (outputPath != null && outputPath.isNotEmpty) {
      final file = File(outputPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(report.toJson()),
      );
      stdout.writeln('[network-bench] report saved to ${file.path}');
    }
  });
}

BenchmarkConfig _buildConfig(Map<String, String> kvArgs) {
  final scenario = kvArgs['scenario'] == null
      ? BenchmarkScenario.smallJson
      : BenchmarkScenarioX.parse(kvArgs['scenario']!);

  final channels = kvArgs['channels'] == null
      ? const {BenchmarkChannel.dio, BenchmarkChannel.rust}
      : BenchmarkChannelX.parseList(kvArgs['channels']!);
  final consumeMode = kvArgs['consume-mode'] == null
      ? BenchmarkConsumeMode.none
      : BenchmarkConsumeModeX.parse(kvArgs['consume-mode']!);

  return BenchmarkConfig(
    scenario: scenario,
    consumeMode: consumeMode,
    requests: _parseInt(kvArgs['requests'], fallback: 120),
    warmupRequests: _parseInt(kvArgs['warmup'], fallback: 12),
    concurrency: _parseInt(kvArgs['concurrency'], fallback: 12),
    channels: channels,
    preflightPrimaryChannel: _parseBool(
      kvArgs['preflight-primary-channel'],
      fallback: true,
    ),
    requirePrimaryChannel: _parseBool(
      kvArgs['require-primary-channel'],
      fallback: false,
    ),
    enableFallback: _parseBool(kvArgs['fallback'], fallback: true),
    verbose: _parseBool(kvArgs['verbose'], fallback: true),
    largePayloadBytes: _parseInt(
      kvArgs['large-bytes'],
      fallback: 2 * 1024 * 1024,
    ),
    jitterBaseDelayMs: _parseInt(kvArgs['jitter-base-ms'], fallback: 12),
    jitterExtraDelayMs: _parseInt(kvArgs['jitter-extra-ms'], fallback: 80),
    flakyFailureEvery: _parseInt(kvArgs['flaky-every'], fallback: 5),
    dioConnectTimeout: Duration(
      milliseconds: _parseInt(kvArgs['connect-timeout-ms'], fallback: 5000),
    ),
    dioReceiveTimeout: Duration(
      milliseconds: _parseInt(kvArgs['receive-timeout-ms'], fallback: 15000),
    ),
    requestKeySpace: _parseInt(kvArgs['request-key-space'], fallback: 0),
    scenarioBaseUrl: kvArgs['base-url'] ?? '',
  );
}

Map<String, String> _parseArgs(List<String> args) {
  final kv = <String, String>{};
  for (final arg in args) {
    if (!arg.startsWith('--')) {
      throw ArgumentError('invalid argument: $arg');
    }
    final payload = arg.substring(2);
    if (payload.isEmpty) {
      continue;
    }
    final splitIndex = payload.indexOf('=');
    if (splitIndex < 0) {
      kv[payload] = 'true';
      continue;
    }
    final key = payload.substring(0, splitIndex);
    final value = payload.substring(splitIndex + 1);
    if (key.isEmpty) {
      throw ArgumentError('invalid argument: $arg');
    }
    kv[key] = value;
  }
  return kv;
}

int _parseInt(String? raw, {required int fallback}) {
  if (raw == null || raw.isEmpty) {
    return fallback;
  }
  final value = int.tryParse(raw);
  if (value == null) {
    throw ArgumentError('invalid int: $raw');
  }
  return value;
}

bool _parseBool(String? raw, {required bool fallback}) {
  if (raw == null || raw.isEmpty) {
    return fallback;
  }
  switch (raw.toLowerCase()) {
    case 'true':
    case '1':
    case 'yes':
    case 'on':
      return true;
    case 'false':
    case '0':
    case 'no':
    case 'off':
      return false;
    default:
      throw ArgumentError('invalid bool: $raw');
  }
}
