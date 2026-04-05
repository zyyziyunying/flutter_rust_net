part of '../p1_aggregate.dart';

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
    '| concurrency | variant | consumeMode | dioRuns | primaryRuns | dio reqP95 | primary reqP95 | reqP95 delta | dio tp | primary tp | tp delta | primary queueGap | primary exRate(max) | primary fallback(max) | verdict |',
    '| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |',
  ];

  final failures = <String>[];
  for (final row in pairRows) {
    final dio = row.dio;
    final primary = row.primary;
    if (dio == null || primary == null) {
      lines.add(
        '| ${row.key.concurrency} | ${row.key.variantLabel} | '
        '${row.key.consumeMode} | ${dio?.runCount ?? 0} | ${primary?.runCount ?? 0} | '
        '- | - | - | - | - | - | - | - | - | MISSING_CHANNEL |',
      );
      failures.add(
        'c${row.key.concurrency}/${row.key.variantLabel}/'
        '${row.key.consumeMode}: missing dio or primary data',
      );
      continue;
    }

    final reqP95Delta = _deltaPercent(
      base: dio.requestP95MedianMs,
      value: primary.requestP95MedianMs,
    );
    final throughputDelta = _deltaPercent(
      base: dio.throughputMedianRps,
      value: primary.throughputMedianRps,
    );
    final verdict = _evaluate(dio: dio, primary: primary);

    lines.add(
      '| ${row.key.concurrency} | ${row.key.variantLabel} | ${row.key.consumeMode} | '
      '${dio.runCount} | ${primary.runCount} | '
      '${_fmtMs(dio.requestP95MedianMs)} | ${_fmtMs(primary.requestP95MedianMs)} | ${_fmtPercent(reqP95Delta)} | '
      '${_fmtRps(dio.throughputMedianRps)} | ${_fmtRps(primary.throughputMedianRps)} | ${_fmtPercent(throughputDelta)} | '
      '${_fmtMs(primary.queueGapMedianMs)} | ${_fmtRate(primary.exceptionRateMax)} | ${primary.fallbackCountMax} | '
      '${verdict.pass ? 'PASS' : 'FAIL'} |',
    );

    if (!verdict.pass) {
      failures.add(
        'c${row.key.concurrency}/${row.key.variantLabel}/'
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
    '- thresholds: primary exceptionRate==0, primary fallbackCount==0, '
    'primary reqP95<=dio*1.05, primary throughput>=dio, primary queueGap<=10ms.',
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
    final primary = row.primary;
    final verdict = dio == null || primary == null
        ? const _Verdict(pass: false, reasons: ['missing_dio_or_primary'])
        : _evaluate(dio: dio, primary: primary);
    rows.add({
      'scenario': row.key.scenario,
      'consumeMode': row.key.consumeMode,
      'concurrency': row.key.concurrency,
      'variant': row.key.variantLabel,
      'dio': dio == null ? null : _statsToJson(dio),
      'primary': primary == null ? null : _statsToJson(primary),
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
p1_aggregate.dart - aggregate benchmark reports for primary-channel decisions

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
