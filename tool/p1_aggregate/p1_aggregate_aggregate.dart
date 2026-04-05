part of '../p1_aggregate.dart';

Map<_ChannelGroupKey, _ChannelStats> _aggregateChannelStats(
  List<_ChannelSample> samples,
) {
  final grouped = <_ChannelGroupKey, List<_ChannelSample>>{};

  for (final sample in samples) {
    final key = _ChannelGroupKey(
      scenario: sample.scenario,
      consumeMode: sample.consumeMode,
      concurrency: sample.concurrency,
      variantLabel: sample.variantLabel,
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
      variantLabel: stats.key.variantLabel,
    );
    final row = pairs.putIfAbsent(key, () => _PairRow(key));
    if (stats.key.channel == 'dio') {
      row.dio = stats;
    } else if (stats.key.channel == 'rust') {
      row.primary = stats;
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
    return left.key.variantLabel.compareTo(right.key.variantLabel);
  });
  return rows;
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

_Verdict _evaluate({
  required _ChannelStats dio,
  required _ChannelStats primary,
}) {
  final reasons = <String>[];
  if (primary.exceptionRateMax > 0) {
    reasons.add('primary exceptionRate > 0');
  }
  if (primary.fallbackCountMax > 0) {
    reasons.add('primary fallbackCount > 0');
  }
  if (dio.requestP95MedianMs > 0 &&
      primary.requestP95MedianMs > dio.requestP95MedianMs * 1.05) {
    reasons.add('primary reqP95 > dio*1.05');
  }
  if (primary.throughputMedianRps < dio.throughputMedianRps) {
    reasons.add('primary throughput < dio');
  }
  if (primary.queueGapMedianMs > 10) {
    reasons.add('primary queueGap > 10ms');
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
