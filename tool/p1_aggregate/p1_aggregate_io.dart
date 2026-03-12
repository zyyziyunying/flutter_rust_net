part of '../p1_aggregate.dart';

_CliOptions _buildOptions(Map<String, String> kvArgs) {
  final input = kvArgs['input']?.trim().isNotEmpty == true
      ? kvArgs['input']!.trim()
      : 'build/p1_jitter';
  final scenario = kvArgs['scenario']?.trim().isNotEmpty == true
      ? kvArgs['scenario']!.trim()
      : 'jitter_latency';
  final consumeModeFilter = kvArgs['consume-mode']?.trim().isNotEmpty == true
      ? kvArgs['consume-mode']!.trim()
      : null;
  final outputMarkdown = kvArgs['output-md']?.trim().isNotEmpty == true
      ? File(kvArgs['output-md']!.trim())
      : null;
  final outputJson = kvArgs['output-json']?.trim().isNotEmpty == true
      ? File(kvArgs['output-json']!.trim())
      : null;

  return _CliOptions(
    inputDir: Directory(input),
    scenario: scenario,
    consumeModeFilter: consumeModeFilter,
    outputMarkdown: outputMarkdown,
    outputJson: outputJson,
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

List<File> _collectJsonFiles(Directory inputDir) {
  if (!inputDir.existsSync()) {
    return const [];
  }

  return inputDir
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.toLowerCase().endsWith('.json'))
      .toList(growable: false);
}

_BenchReport? _tryParseReport(String filePath, {required _CliOptions options}) {
  Map<String, Object?>? root;
  try {
    final raw = File(filePath).readAsStringSync();
    final decoded = jsonDecode(raw);
    root = _asMap(decoded);
    if (root == null) {
      return null;
    }
  } catch (_) {
    return null;
  }

  final config = _asMap(root['config']);
  final channelResults = _asList(root['channelResults']);
  if (config == null || channelResults.isEmpty) {
    return null;
  }

  final scenario = '${config['scenario'] ?? ''}';
  if (scenario != options.scenario) {
    return null;
  }

  final consumeMode = '${config['consumeMode'] ?? 'unknown'}';
  if (options.consumeModeFilter != null &&
      consumeMode != options.consumeModeFilter) {
    return null;
  }

  final concurrency = _toInt(config['concurrency']);
  final rustMaxInFlightTasks = _toInt(config['rustMaxInFlightTasks']);
  final samples = <_ChannelSample>[];

  for (final entry in channelResults) {
    final row = _asMap(entry);
    if (row == null) {
      continue;
    }
    final channel = '${row['channel'] ?? ''}';
    if (!_supportedChannels.contains(channel)) {
      continue;
    }
    final requestLatency = _asMap(row['requestLatencyMs']);
    final endToEndLatency = _asMap(row['endToEndLatencyMs']);
    final adapterCostLatency = _asMap(row['adapterCostLatencyMs']);
    final consume = _asMap(row['consume']);
    final consumeLatency = _asMap(consume?['latencyMs']);

    final endToEndAvgMs = _toDouble(endToEndLatency?['avgMs']);
    final adapterAvgMs = _toDouble(adapterCostLatency?['avgMs']);

    samples.add(
      _ChannelSample(
        reportPath: filePath,
        scenario: scenario,
        consumeMode: consumeMode,
        concurrency: concurrency,
        rustMaxInFlightTasks: rustMaxInFlightTasks,
        channel: channel,
        requestP95Ms: _toDouble(requestLatency?['p95Ms']),
        requestP99Ms: _toDouble(requestLatency?['p99Ms']),
        endToEndP95Ms: _toDouble(endToEndLatency?['p95Ms']),
        throughputRps: _toDouble(row['throughputRps']),
        exceptionRate: _toDouble(row['exceptionRate']),
        fallbackCount: _toInt(row['fallbackCount']),
        queueGapAvgMs: endToEndAvgMs - adapterAvgMs,
        consumeP95Ms: _toDouble(consumeLatency?['p95Ms']),
      ),
    );
  }

  if (samples.isEmpty) {
    return null;
  }

  return _BenchReport(
    path: filePath,
    scenario: scenario,
    consumeMode: consumeMode,
    concurrency: concurrency,
    rustMaxInFlightTasks: rustMaxInFlightTasks,
    samples: samples,
  );
}

double _toDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? 0;
  }
  return 0;
}

int _toInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is Map) {
    return value.cast<String, Object?>();
  }
  return null;
}

List<Object?> _asList(Object? value) {
  if (value is List) {
    return value.cast<Object?>();
  }
  return const <Object?>[];
}
