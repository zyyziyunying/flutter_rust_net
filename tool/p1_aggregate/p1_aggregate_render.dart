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
