import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/benchmark/download_benchmark_config.dart';
import 'package:flutter_rust_net/network/benchmark/download_benchmark_harness.dart';

const String _kDownloadBenchArgsEnv = 'FRN_RHTTP_DOWNLOAD_BENCH_ARGS_JSON';

void main() {
  test('rhttp_download_bench_driver', () async {
    final rawArgs = Platform.environment[_kDownloadBenchArgsEnv];
    if (rawArgs == null || rawArgs.isEmpty) {
      throw StateError('missing $_kDownloadBenchArgsEnv');
    }

    final decoded = jsonDecode(rawArgs);
    if (decoded is! List) {
      throw StateError('$_kDownloadBenchArgsEnv must decode to a JSON array');
    }

    final args = decoded.map((item) => '$item').toList(growable: false);
    final kvArgs = _parseArgs(args);
    final config = _buildConfig(kvArgs);
    final report = await runDownloadBenchmark(
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
      stdout.writeln('[rhttp-download-bench] report saved to ${file.path}');
    }
  });
}

DownloadBenchConfig _buildConfig(Map<String, String> kvArgs) {
  final channels = kvArgs['channels'] == null
      ? const {DownloadBenchChannel.dio, DownloadBenchChannel.rhttp}
      : DownloadBenchChannelX.parseList(kvArgs['channels']!);

  return DownloadBenchConfig(
    baseUrl: kvArgs['base-url'] ?? '',
    channels: channels,
    fileBytes: _parseInt(kvArgs['file-bytes'], fallback: 16 * 1024 * 1024),
    requests: _parseInt(kvArgs['requests'], fallback: 3),
    warmupRequests: _parseInt(kvArgs['warmup'], fallback: 1),
    concurrency: _parseInt(kvArgs['concurrency'], fallback: 1),
    chunkBytes: _parseInt(kvArgs['chunk-bytes'], fallback: 64 * 1024),
    chunkDelayMs: _parseInt(kvArgs['chunk-delay-ms'], fallback: 0),
    verbose: _parseBool(kvArgs['verbose'], fallback: true),
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
