import 'dart:convert';
import 'dart:io';
import 'dart:math';

const Set<String> _supportedChannels = {'dio', 'rust'};

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  try {
    final kvArgs = _parseArgs(args);
    final options = _buildOptions(kvArgs);
    final allFiles = _collectJsonFiles(options.inputDir);
    final reports = <_BenchReport>[];
    final samples = <_ChannelSample>[];

    for (final file in allFiles) {
      final parsed = _tryParseReport(file.path, options: options);
      if (parsed == null) {
        continue;
      }
      reports.add(parsed);
      samples.addAll(parsed.samples);
    }

    stdout.writeln(
      '[p1-aggregate] scannedFiles=${allFiles.length} '
      'matchedReports=${reports.length} '
      'samples=${samples.length}',
    );

    if (samples.isEmpty) {
      stderr.writeln('[p1-aggregate] no matched benchmark reports found.');
      stderr.writeln(
        '[p1-aggregate] input=${options.inputDir.path} '
        'scenario=${options.scenario} '
        'consumeMode=${options.consumeModeFilter ?? 'any'}',
      );
      exitCode = 2;
      return;
    }

    final statsByChannelKey = _aggregateChannelStats(samples);
    final pairRows = _buildPairRows(statsByChannelKey);
    final markdown = _buildMarkdown(
      options: options,
      reports: reports,
      samples: samples,
      pairRows: pairRows,
    );

    stdout.writeln(markdown);

    if (options.outputMarkdown != null) {
      await options.outputMarkdown!.parent.create(recursive: true);
      await options.outputMarkdown!.writeAsString(markdown);
      stdout.writeln(
        '[p1-aggregate] markdown saved to ${options.outputMarkdown!.path}',
      );
    }

    if (options.outputJson != null) {
      final summary = _buildJsonSummary(
        options: options,
        reports: reports,
        samples: samples,
        pairRows: pairRows,
      );
      await options.outputJson!.parent.create(recursive: true);
      await options.outputJson!.writeAsString(
        const JsonEncoder.withIndent('  ').convert(summary),
      );
      stdout.writeln(
        '[p1-aggregate] json saved to ${options.outputJson!.path}',
      );
    }
  } catch (error) {
    stderr.writeln('[p1-aggregate] failed: $error');
    stderr.writeln('use --help to view all options.');
    exitCode = 2;
  }
}

class _CliOptions {
  final Directory inputDir;
  final String scenario;
  final String? consumeModeFilter;
  final File? outputMarkdown;
  final File? outputJson;

  const _CliOptions({
    required this.inputDir,
    required this.scenario,
    required this.consumeModeFilter,
    required this.outputMarkdown,
    required this.outputJson,
  });
}

class _BenchReport {
  final String path;
  final String scenario;
  final String consumeMode;
  final int concurrency;
  final int rustMaxInFlightTasks;
  final List<_ChannelSample> samples;

  const _BenchReport({
    required this.path,
    required this.scenario,
    required this.consumeMode,
    required this.concurrency,
    required this.rustMaxInFlightTasks,
    required this.samples,
  });
}

class _ChannelSample {
  final String reportPath;
  final String scenario;
  final String consumeMode;
  final int concurrency;
  final int rustMaxInFlightTasks;
  final String channel;
  final double requestP95Ms;
  final double requestP99Ms;
  final double endToEndP95Ms;
  final double throughputRps;
  final double exceptionRate;
  final int fallbackCount;
  final double queueGapAvgMs;
  final double consumeP95Ms;

  const _ChannelSample({
    required this.reportPath,
    required this.scenario,
    required this.consumeMode,
    required this.concurrency,
    required this.rustMaxInFlightTasks,
    required this.channel,
    required this.requestP95Ms,
    required this.requestP99Ms,
    required this.endToEndP95Ms,
    required this.throughputRps,
    required this.exceptionRate,
    required this.fallbackCount,
    required this.queueGapAvgMs,
    required this.consumeP95Ms,
  });
}

class _ChannelGroupKey {
  final String scenario;
  final String consumeMode;
  final int concurrency;
  final int rustMaxInFlightTasks;
  final String channel;

  const _ChannelGroupKey({
    required this.scenario,
    required this.consumeMode,
    required this.concurrency,
    required this.rustMaxInFlightTasks,
    required this.channel,
  });

  @override
  bool operator ==(Object other) {
    return other is _ChannelGroupKey &&
        scenario == other.scenario &&
        consumeMode == other.consumeMode &&
        concurrency == other.concurrency &&
        rustMaxInFlightTasks == other.rustMaxInFlightTasks &&
        channel == other.channel;
  }

  @override
  int get hashCode => Object.hash(
    scenario,
    consumeMode,
    concurrency,
    rustMaxInFlightTasks,
    channel,
  );
}

class _ChannelStats {
  final _ChannelGroupKey key;
  final int runCount;
  final double requestP95MedianMs;
  final double requestP99MedianMs;
  final double endToEndP95MedianMs;
  final double throughputMedianRps;
  final double exceptionRateMax;
  final int fallbackCountMax;
  final double queueGapMedianMs;
  final double consumeP95MedianMs;

  const _ChannelStats({
    required this.key,
    required this.runCount,
    required this.requestP95MedianMs,
    required this.requestP99MedianMs,
    required this.endToEndP95MedianMs,
    required this.throughputMedianRps,
    required this.exceptionRateMax,
    required this.fallbackCountMax,
    required this.queueGapMedianMs,
    required this.consumeP95MedianMs,
  });
}

class _PairKey {
  final String scenario;
  final String consumeMode;
  final int concurrency;
  final int rustMaxInFlightTasks;

  const _PairKey({
    required this.scenario,
    required this.consumeMode,
    required this.concurrency,
    required this.rustMaxInFlightTasks,
  });

  @override
  bool operator ==(Object other) {
    return other is _PairKey &&
        scenario == other.scenario &&
        consumeMode == other.consumeMode &&
        concurrency == other.concurrency &&
        rustMaxInFlightTasks == other.rustMaxInFlightTasks;
  }

  @override
  int get hashCode =>
      Object.hash(scenario, consumeMode, concurrency, rustMaxInFlightTasks);
}

class _PairRow {
  final _PairKey key;
  _ChannelStats? dio;
  _ChannelStats? rust;

  _PairRow(this.key);
}

class _Verdict {
  final bool pass;
  final List<String> reasons;

  const _Verdict({required this.pass, required this.reasons});
}

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

Map<_ChannelGroupKey, _ChannelStats> _aggregateChannelStats(
  List<_ChannelSample> samples,
) {
  final grouped = <_ChannelGroupKey, List<_ChannelSample>>{};

  for (final sample in samples) {
    final key = _ChannelGroupKey(
      scenario: sample.scenario,
      consumeMode: sample.consumeMode,
      concurrency: sample.concurrency,
      rustMaxInFlightTasks: sample.rustMaxInFlightTasks,
      channel: sample.channel,
    );
    grouped.putIfAbsent(key, () => <_ChannelSample>[]).add(sample);
  }

  final result = <_ChannelGroupKey, _ChannelStats>{};
  grouped.forEach((key, group) {
    final exceptionRateMax = group
        .map((item) => item.exceptionRate)
        .fold<double>(0, max);
    final fallbackCountMax = group
        .map((item) => item.fallbackCount)
        .fold<int>(0, max);
    result[key] = _ChannelStats(
      key: key,
      runCount: group.length,
      requestP95MedianMs: _median(group.map((item) => item.requestP95Ms)),
      requestP99MedianMs: _median(group.map((item) => item.requestP99Ms)),
      endToEndP95MedianMs: _median(group.map((item) => item.endToEndP95Ms)),
      throughputMedianRps: _median(group.map((item) => item.throughputRps)),
      exceptionRateMax: exceptionRateMax,
      fallbackCountMax: fallbackCountMax,
      queueGapMedianMs: _median(group.map((item) => item.queueGapAvgMs)),
      consumeP95MedianMs: _median(group.map((item) => item.consumeP95Ms)),
    );
  });

  return result;
}

List<_PairRow> _buildPairRows(Map<_ChannelGroupKey, _ChannelStats> statsByKey) {
  final pairs = <_PairKey, _PairRow>{};
  for (final stats in statsByKey.values) {
    final key = _PairKey(
      scenario: stats.key.scenario,
      consumeMode: stats.key.consumeMode,
      concurrency: stats.key.concurrency,
      rustMaxInFlightTasks: stats.key.rustMaxInFlightTasks,
    );
    final row = pairs.putIfAbsent(key, () => _PairRow(key));
    if (stats.key.channel == 'dio') {
      row.dio = stats;
    } else if (stats.key.channel == 'rust') {
      row.rust = stats;
    }
  }

  final rows = pairs.values.toList();
  rows.sort((left, right) {
    final byScenario = left.key.scenario.compareTo(right.key.scenario);
    if (byScenario != 0) {
      return byScenario;
    }
    final byConsume = left.key.consumeMode.compareTo(right.key.consumeMode);
    if (byConsume != 0) {
      return byConsume;
    }
    final byConcurrency = left.key.concurrency.compareTo(right.key.concurrency);
    if (byConcurrency != 0) {
      return byConcurrency;
    }
    return left.key.rustMaxInFlightTasks.compareTo(
      right.key.rustMaxInFlightTasks,
    );
  });
  return rows;
}

String _buildMarkdown({
  required _CliOptions options,
  required List<_BenchReport> reports,
  required List<_ChannelSample> samples,
  required List<_PairRow> pairRows,
}) {
  final lines = <String>[
    '# P1 Aggregation Summary',
    '',
    '- generatedAt: ${DateTime.now().toIso8601String()}',
    '- input: `${options.inputDir.path}`',
    '- scenario: `${options.scenario}`',
    '- consumeModeFilter: `${options.consumeModeFilter ?? 'any'}`',
    '- matchedReports: ${reports.length}',
    '- samples: ${samples.length}',
    '',
    '| concurrency | maxInFlight | consumeMode | dioRuns | rustRuns | dio reqP95 | rust reqP95 | reqP95 delta | dio tp | rust tp | tp delta | rust queueGap | rust exRate(max) | rust fallback(max) | verdict |',
    '| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |',
  ];

  final failures = <String>[];
  for (final row in pairRows) {
    final dio = row.dio;
    final rust = row.rust;
    if (dio == null || rust == null) {
      lines.add(
        '| ${row.key.concurrency} | ${row.key.rustMaxInFlightTasks} | '
        '${row.key.consumeMode} | ${dio?.runCount ?? 0} | ${rust?.runCount ?? 0} | '
        '- | - | - | - | - | - | - | - | - | MISSING_CHANNEL |',
      );
      failures.add(
        'c${row.key.concurrency}/mif${row.key.rustMaxInFlightTasks}/'
        '${row.key.consumeMode}: missing dio or rust data',
      );
      continue;
    }

    final reqP95Delta = _deltaPercent(
      base: dio.requestP95MedianMs,
      value: rust.requestP95MedianMs,
    );
    final throughputDelta = _deltaPercent(
      base: dio.throughputMedianRps,
      value: rust.throughputMedianRps,
    );
    final verdict = _evaluate(dio: dio, rust: rust);

    lines.add(
      '| ${row.key.concurrency} | ${row.key.rustMaxInFlightTasks} | ${row.key.consumeMode} | '
      '${dio.runCount} | ${rust.runCount} | '
      '${_fmtMs(dio.requestP95MedianMs)} | ${_fmtMs(rust.requestP95MedianMs)} | ${_fmtPercent(reqP95Delta)} | '
      '${_fmtRps(dio.throughputMedianRps)} | ${_fmtRps(rust.throughputMedianRps)} | ${_fmtPercent(throughputDelta)} | '
      '${_fmtMs(rust.queueGapMedianMs)} | ${_fmtRate(rust.exceptionRateMax)} | ${rust.fallbackCountMax} | '
      '${verdict.pass ? 'PASS' : 'FAIL'} |',
    );

    if (!verdict.pass) {
      failures.add(
        'c${row.key.concurrency}/mif${row.key.rustMaxInFlightTasks}/'
        '${row.key.consumeMode}: ${verdict.reasons.join('; ')}',
      );
    }
  }

  lines.add('');
  if (failures.isEmpty) {
    lines.add('- verdict: all pairs pass current thresholds.');
  } else {
    lines.add('- failed pairs: ${failures.length}');
    for (final failure in failures) {
      lines.add('  - $failure');
    }
  }
  lines.add('');
  lines.add(
    '- thresholds: rust exceptionRate==0, rust fallbackCount==0, '
    'rust reqP95<=dio*1.05, rust throughput>=dio, rust queueGap<=10ms.',
  );

  return lines.join('\n');
}

Map<String, Object?> _buildJsonSummary({
  required _CliOptions options,
  required List<_BenchReport> reports,
  required List<_ChannelSample> samples,
  required List<_PairRow> pairRows,
}) {
  final rows = <Map<String, Object?>>[];
  for (final row in pairRows) {
    final dio = row.dio;
    final rust = row.rust;
    final verdict = dio == null || rust == null
        ? const _Verdict(pass: false, reasons: ['missing_dio_or_rust'])
        : _evaluate(dio: dio, rust: rust);
    rows.add({
      'scenario': row.key.scenario,
      'consumeMode': row.key.consumeMode,
      'concurrency': row.key.concurrency,
      'rustMaxInFlightTasks': row.key.rustMaxInFlightTasks,
      'dio': dio == null ? null : _statsToJson(dio),
      'rust': rust == null ? null : _statsToJson(rust),
      'verdict': {'pass': verdict.pass, 'reasons': verdict.reasons},
    });
  }

  return {
    'generatedAt': DateTime.now().toIso8601String(),
    'inputDir': options.inputDir.path,
    'scenario': options.scenario,
    'consumeModeFilter': options.consumeModeFilter,
    'matchedReports': reports.length,
    'samples': samples.length,
    'pairs': rows,
  };
}

Map<String, Object?> _statsToJson(_ChannelStats stats) {
  return {
    'runCount': stats.runCount,
    'requestP95MedianMs': stats.requestP95MedianMs,
    'requestP99MedianMs': stats.requestP99MedianMs,
    'endToEndP95MedianMs': stats.endToEndP95MedianMs,
    'throughputMedianRps': stats.throughputMedianRps,
    'exceptionRateMax': stats.exceptionRateMax,
    'fallbackCountMax': stats.fallbackCountMax,
    'queueGapMedianMs': stats.queueGapMedianMs,
    'consumeP95MedianMs': stats.consumeP95MedianMs,
  };
}

_Verdict _evaluate({required _ChannelStats dio, required _ChannelStats rust}) {
  final reasons = <String>[];
  if (rust.exceptionRateMax > 0) {
    reasons.add('rust exceptionRate > 0');
  }
  if (rust.fallbackCountMax > 0) {
    reasons.add('rust fallbackCount > 0');
  }
  if (dio.requestP95MedianMs > 0 &&
      rust.requestP95MedianMs > dio.requestP95MedianMs * 1.05) {
    reasons.add('rust reqP95 > dio*1.05');
  }
  if (rust.throughputMedianRps < dio.throughputMedianRps) {
    reasons.add('rust throughput < dio');
  }
  if (rust.queueGapMedianMs > 10) {
    reasons.add('rust queueGap > 10ms');
  }
  return _Verdict(pass: reasons.isEmpty, reasons: reasons);
}

double _median(Iterable<double> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) {
    return 0;
  }
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[mid];
  }
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

double? _deltaPercent({required double base, required double value}) {
  if (base == 0) {
    return null;
  }
  return (value - base) * 100 / base;
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

String _fmtMs(double value) => value.toStringAsFixed(2);

String _fmtRps(double value) => value.toStringAsFixed(2);

String _fmtRate(double value) => value.toStringAsFixed(4);

String _fmtPercent(double? value) {
  if (value == null) {
    return '-';
  }
  final sign = value > 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(2)}%';
}

void _printUsage() {
  stdout.writeln('''
p1_aggregate.dart - aggregate jitter benchmark reports for P1 decisions

Usage:
  dart run tool/p1_aggregate.dart [options]

Options:
  --input=build/p1_jitter          root directory that contains benchmark JSON files
  --scenario=jitter_latency        benchmark scenario to aggregate
  --consume-mode=none|json_model   optional exact consumeMode filter
  --output-md=build/p1_summary.md  optional markdown output path
  --output-json=build/p1_summary.json  optional json output path

Examples:
  dart run tool/p1_aggregate.dart --input=build/p1_jitter
  dart run tool/p1_aggregate.dart --input=build/p1_jitter --consume-mode=none --output-md=build/p1_jitter/summary_none.md
  dart run tool/p1_aggregate.dart --input=build/p1_jitter --output-json=build/p1_jitter/summary.json
''');
}
