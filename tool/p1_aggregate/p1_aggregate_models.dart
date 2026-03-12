part of '../p1_aggregate.dart';

const Set<String> _supportedChannels = {'dio', 'rust'};

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
