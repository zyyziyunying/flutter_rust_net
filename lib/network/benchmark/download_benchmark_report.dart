import 'dart:convert';

class DownloadBenchReport {
  final DateTime startedAt;
  final DateTime finishedAt;
  final String baseUrl;
  final String serverMode;
  final int fileBytes;
  final int requests;
  final int warmupRequests;
  final int concurrency;
  final int chunkBytes;
  final int chunkDelayMs;
  final Map<String, String> skippedChannels;
  final List<DownloadBenchChannelResult> channelResults;

  const DownloadBenchReport({
    required this.startedAt,
    required this.finishedAt,
    required this.baseUrl,
    required this.serverMode,
    required this.fileBytes,
    required this.requests,
    required this.warmupRequests,
    required this.concurrency,
    required this.chunkBytes,
    required this.chunkDelayMs,
    required this.skippedChannels,
    required this.channelResults,
  });

  Map<String, dynamic> toJson() {
    return {
      'baseUrl': baseUrl,
      'serverMode': serverMode,
      'fileBytes': fileBytes,
      'requests': requests,
      'warmup': warmupRequests,
      'concurrency': concurrency,
      'chunkBytes': chunkBytes,
      'chunkDelayMs': chunkDelayMs,
      'skippedChannels': skippedChannels,
      'startedAt': startedAt.toIso8601String(),
      'finishedAt': finishedAt.toIso8601String(),
      'channelResults': channelResults.map((item) => item.toJson()).toList(),
    };
  }

  String toPrettyText() {
    final lines = <String>[
      '[rhttp-download-bench] baseUrl=$baseUrl '
          'serverMode=$serverMode fileBytes=$fileBytes requests=$requests '
          'warmup=$warmupRequests concurrency=$concurrency '
          'chunkBytes=$chunkBytes chunkDelayMs=$chunkDelayMs',
    ];
    if (skippedChannels.isNotEmpty) {
      lines.add(
        '[rhttp-download-bench] skipped=${jsonEncode(skippedChannels)}',
      );
    }
    for (final result in channelResults) {
      lines.add(
        '[rhttp-download-bench][${result.channel}] '
        '${result.toOneLineSummary()}',
      );
    }
    return lines.join('\n');
  }
}

class DownloadBenchChannelResult {
  final String channel;
  final int successCount;
  final int failureCount;
  final int fileSizeVerifiedCount;
  final int checksumVerifiedCount;
  final int downloadP50Ms;
  final int downloadP95Ms;
  final double avgMs;
  final int bytesPerSecond;
  final double throughputMbps;
  final String outputFileMode;

  const DownloadBenchChannelResult({
    required this.channel,
    required this.successCount,
    required this.failureCount,
    required this.fileSizeVerifiedCount,
    required this.checksumVerifiedCount,
    required this.downloadP50Ms,
    required this.downloadP95Ms,
    required this.avgMs,
    required this.bytesPerSecond,
    required this.throughputMbps,
    required this.outputFileMode,
  });

  Map<String, dynamic> toJson() {
    return {
      'channel': channel,
      'successCount': successCount,
      'failureCount': failureCount,
      'downloadP50Ms': downloadP50Ms,
      'downloadP95Ms': downloadP95Ms,
      'avgMs': avgMs,
      'bytesPerSecond': bytesPerSecond,
      'throughputMbps': throughputMbps,
      'fileSizeVerifiedCount': fileSizeVerifiedCount,
      'checksumVerifiedCount': checksumVerifiedCount,
      'outputFileMode': outputFileMode,
    };
  }

  String toOneLineSummary() {
    return [
      'success=$successCount',
      'failure=$failureCount',
      'sizeVerified=$fileSizeVerifiedCount',
      'checksumVerified=$checksumVerifiedCount',
      'p50=${downloadP50Ms}ms',
      'p95=${downloadP95Ms}ms',
      'avg=${avgMs.toStringAsFixed(2)}ms',
      'throughput=${throughputMbps.toStringAsFixed(2)} Mbps',
      'output=$outputFileMode',
    ].join(', ');
  }
}
