import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_net/network/benchmark/network_benchmark_harness.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  try {
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
  } catch (error) {
    stderr.writeln('[network-bench] failed: $error');
    stderr.writeln('use --help to view all options.');
    exitCode = 2;
  }
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
    initializeRust: _parseBool(kvArgs['initialize-rust'], fallback: true),
    requireRust: _parseBool(kvArgs['require-rust'], fallback: false),
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
    rustMaxInFlightTasks: _parseInt(kvArgs['rust-max-in-flight'], fallback: 32),
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

void _printUsage() {
  stdout.writeln('''
network_bench.dart - realistic local benchmark for Dio vs Rust channels

Usage:
  dart run tool/network_bench.dart [options]

Options:
  --scenario=small_json|large_json|large_payload|jitter_latency|flaky_http
  --consume-mode=none|json_decode|json_model
  --channels=dio,rust             default: dio,rust
  --requests=120                  measured requests per channel
  --warmup=12                     warmup requests per channel
  --concurrency=12                parallel workers
  --initialize-rust=true|false    default: true
  --require-rust=true|false       default: false
  --fallback=true|false           gateway fallback switch, default: true
  --verbose=true|false            default: true
  --output=build/network_bench.json
  --base-url=http://127.0.0.1:18080

Scenario knobs:
  --large-bytes=2097152           for large_payload / large_json
  --jitter-base-ms=12             for jitter_latency
  --jitter-extra-ms=80            for jitter_latency
  --flaky-every=5                 for flaky_http

Client knobs:
  --connect-timeout-ms=5000
  --receive-timeout-ms=15000
  --rust-max-in-flight=32
  --request-key-space=0            0=disable reuse; >0 reuses request ids for cache probing

Examples:
  dart run tool/network_bench.dart --scenario=small_json --requests=400 --concurrency=16 --output=build/small.json
  dart run tool/network_bench.dart --scenario=large_payload --channels=dio,rust --initialize-rust=true --output=build/large.json
  dart run tool/network_bench.dart --scenario=flaky_http --channels=dio --flaky-every=4
  dart run tool/network_bench.dart --base-url=http://47.110.52.208:7777 --scenario=jitter_latency --channels=dio,rust
''');
}
