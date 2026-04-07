import 'dart:io';

import 'package:dio/dio.dart';
import 'package:rhttp/rhttp.dart' as rhttp;

import 'download_benchmark_config.dart';
import 'download_benchmark_report.dart';
import 'download_benchmark_support.dart';
import 'benchmark_report.dart';
import 'benchmark_scenario_server.dart';
import 'benchmark_config.dart';

Future<void>? _rhttpInitFuture;

typedef DownloadAttemptRunner =
    Future<DownloadAttemptResult> Function({
      required DownloadBenchChannel channel,
      required String baseUrl,
      required int fileBytes,
      required String outputPath,
      required int chunkBytes,
      required int chunkDelayMs,
      Dio? dioClient,
      rhttp.RhttpClient? rhttpClient,
    });

class DownloadAttemptResult {
  final String channel;
  final bool success;
  final int elapsedMs;
  final int? statusCode;
  final bool fileSizeVerified;
  final bool checksumVerified;
  final int bytesPerSecond;
  final double throughputMbps;
  final String outputFileMode;
  final String? errorMessage;

  const DownloadAttemptResult({
    required this.channel,
    required this.success,
    required this.elapsedMs,
    required this.statusCode,
    required this.fileSizeVerified,
    required this.checksumVerified,
    required this.bytesPerSecond,
    required this.throughputMbps,
    required this.outputFileMode,
    required this.errorMessage,
  });
}

Future<DownloadBenchReport> runDownloadBenchmark(
  DownloadBenchConfig config, {
  void Function(String message)? log,
  DownloadAttemptRunner? attemptRunner,
}) async {
  config.validate();
  final logger = log ?? (_) {};
  final startedAt = DateTime.now();
  final runner = attemptRunner ?? runSingleDownloadAttempt;
  final skippedChannels = <String, String>{};
  final tempDir = await Directory.systemTemp.createTemp(
    'rhttp-download-bench-',
  );
  final orderedChannels = [...config.channels]
    ..sort((left, right) => left.cliName.compareTo(right.cliName));

  ScenarioServer? scenarioServer;
  Dio? sharedDio;
  rhttp.RhttpClient? sharedRhttpClient;

  try {
    final resolvedBaseUrl = resolveDownloadBenchBaseUrl(config.baseUrl);
    late final String baseUrl;
    late final String serverMode;
    if (resolvedBaseUrl != null) {
      baseUrl = resolvedBaseUrl;
      serverMode = 'remote';
      logger('[rhttp-download-bench] using external server at $baseUrl');
    } else {
      scenarioServer = await ScenarioServer.start(
        BenchmarkConfig(
          largePayloadBytes: config.fileBytes < 64 * 1024
              ? 64 * 1024
              : config.fileBytes,
        ),
        logger: logger,
      );
      baseUrl = scenarioServer.baseUrl;
      serverMode = 'local';
    }

    if (attemptRunner == null) {
      sharedDio = Dio();
      if (config.channels.contains(DownloadBenchChannel.rhttp)) {
        try {
          await _ensureRhttpInitialized();
          sharedRhttpClient = await rhttp.RhttpClient.create(
            settings: const rhttp.ClientSettings(throwOnStatusCode: false),
          );
        } catch (error) {
          final reason = 'download request channel setup failed: $error';
          skippedChannels[DownloadBenchChannel.rhttp.cliName] = reason;
          logger(
            '[rhttp-download-bench] skip download request channel '
            '(`${DownloadBenchChannel.rhttp.cliName}`), $reason',
          );
        }
      }
    }

    final results = <DownloadBenchChannelResult>[];
    for (final channel in orderedChannels) {
      if (skippedChannels.containsKey(channel.cliName)) {
        continue;
      }

      await _runWarmup(
        config: config,
        channel: channel,
        baseUrl: baseUrl,
        tempDir: tempDir,
        runner: runner,
        dioClient: sharedDio,
        rhttpClient: sharedRhttpClient,
      );

      final attempts = <DownloadAttemptResult>[];
      var issued = 0;

      Future<void> worker() async {
        while (true) {
          final requestIndex = issued++;
          if (requestIndex >= config.requests) {
            return;
          }

          final outputFile = File(
            '${tempDir.path}/${channel.cliName}-$requestIndex.bin',
          );
          final result = await runner(
            channel: channel,
            baseUrl: baseUrl,
            fileBytes: config.fileBytes,
            outputPath: outputFile.path,
            chunkBytes: config.chunkBytes,
            chunkDelayMs: config.chunkDelayMs,
            dioClient: sharedDio,
            rhttpClient: sharedRhttpClient,
          );
          attempts.add(result);
          await _cleanupTempFile(outputFile);
          if (config.verbose && !result.success) {
            logger(
              '[rhttp-download-bench][${channel.cliName}] failure: '
              '${result.errorMessage ?? 'status=${result.statusCode}'}',
            );
          }
        }
      }

      await Future.wait(List.generate(config.concurrency, (_) => worker()));
      results.add(_aggregateChannelResults(channel, attempts));
    }

    return DownloadBenchReport(
      startedAt: startedAt,
      finishedAt: DateTime.now(),
      baseUrl: baseUrl,
      serverMode: serverMode,
      fileBytes: config.fileBytes,
      requests: config.requests,
      warmupRequests: config.warmupRequests,
      concurrency: config.concurrency,
      chunkBytes: config.chunkBytes,
      chunkDelayMs: config.chunkDelayMs,
      skippedChannels: Map.unmodifiable(skippedChannels),
      channelResults: List.unmodifiable(results),
    );
  } finally {
    sharedDio?.close(force: true);
    sharedRhttpClient?.dispose();
    if (scenarioServer != null) {
      await scenarioServer.close();
    }
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  }
}

Future<DownloadAttemptResult> runSingleDownloadAttempt({
  required DownloadBenchChannel channel,
  required String baseUrl,
  required int fileBytes,
  required String outputPath,
  int chunkBytes = 64 * 1024,
  int chunkDelayMs = 0,
  Dio? dioClient,
  rhttp.RhttpClient? rhttpClient,
}) async {
  final uri = buildDownloadBenchUri(
    baseUrl,
    fileBytes: fileBytes,
    chunkBytes: chunkBytes,
    chunkDelayMs: chunkDelayMs,
  );
  final outputFile = File(outputPath);
  await outputFile.parent.create(recursive: true);

  try {
    return switch (channel) {
      DownloadBenchChannel.dio => _downloadWithDio(
        uri: uri,
        outputFile: outputFile,
        fileBytes: fileBytes,
        dioClient: dioClient,
      ),
      DownloadBenchChannel.rhttp => _downloadWithRhttp(
        uri: uri,
        outputFile: outputFile,
        fileBytes: fileBytes,
        rhttpClient: rhttpClient,
      ),
    };
  } catch (error) {
    return DownloadAttemptResult(
      channel: channel.cliName,
      success: false,
      elapsedMs: 0,
      statusCode: null,
      fileSizeVerified: false,
      checksumVerified: false,
      bytesPerSecond: 0,
      throughputMbps: 0,
      outputFileMode: 'download_to_file',
      errorMessage: '$error',
    );
  }
}

Future<void> _runWarmup({
  required DownloadBenchConfig config,
  required DownloadBenchChannel channel,
  required String baseUrl,
  required Directory tempDir,
  required DownloadAttemptRunner runner,
  Dio? dioClient,
  rhttp.RhttpClient? rhttpClient,
}) async {
  for (var i = 0; i < config.warmupRequests; i += 1) {
    final outputFile = File('${tempDir.path}/${channel.cliName}-warmup-$i.bin');
    try {
      await runner(
        channel: channel,
        baseUrl: baseUrl,
        fileBytes: config.fileBytes,
        outputPath: outputFile.path,
        chunkBytes: config.chunkBytes,
        chunkDelayMs: config.chunkDelayMs,
        dioClient: dioClient,
        rhttpClient: rhttpClient,
      );
    } catch (_) {
      // Warmup is best-effort to keep benchmark startup lightweight.
    } finally {
      await _cleanupTempFile(outputFile);
    }
  }
}

Future<DownloadAttemptResult> _downloadWithDio({
  required Uri uri,
  required File outputFile,
  required int fileBytes,
  Dio? dioClient,
}) async {
  final client = dioClient ?? Dio();
  final ownsClient = dioClient == null;
  final watch = Stopwatch()..start();
  try {
    final response = await client.downloadUri(uri, outputFile.path);
    watch.stop();
    return _finalizeAttempt(
      channel: DownloadBenchChannel.dio,
      outputFile: outputFile,
      fileBytes: fileBytes,
      elapsedMs: watch.elapsedMilliseconds,
      statusCode: response.statusCode,
    );
  } finally {
    if (ownsClient) {
      client.close(force: true);
    }
  }
}

Future<DownloadAttemptResult> _downloadWithRhttp({
  required Uri uri,
  required File outputFile,
  required int fileBytes,
  rhttp.RhttpClient? rhttpClient,
}) async {
  await _ensureRhttpInitialized();
  final client =
      rhttpClient ??
      await rhttp.RhttpClient.create(
        settings: const rhttp.ClientSettings(throwOnStatusCode: false),
      );
  final ownsClient = rhttpClient == null;
  final sink = outputFile.openWrite();
  final watch = Stopwatch()..start();
  try {
    final response = await client.getStream(uri.toString());
    await for (final chunk in response.body) {
      sink.add(chunk);
    }
    await sink.flush();
    watch.stop();
    return _finalizeAttempt(
      channel: DownloadBenchChannel.rhttp,
      outputFile: outputFile,
      fileBytes: fileBytes,
      elapsedMs: watch.elapsedMilliseconds,
      statusCode: response.statusCode,
    );
  } finally {
    await sink.close();
    if (ownsClient) {
      client.dispose();
    }
  }
}

Future<DownloadAttemptResult> _finalizeAttempt({
  required DownloadBenchChannel channel,
  required File outputFile,
  required int fileBytes,
  required int elapsedMs,
  required int? statusCode,
}) async {
  final actualSize = await outputFile.length();
  final fileSizeVerified = actualSize == fileBytes;
  final actualChecksum = await rollingDownloadChecksumForFile(outputFile);
  final checksumVerified =
      fileSizeVerified && actualChecksum == expectedDownloadChecksum(fileBytes);
  final statusOk = statusCode != null && statusCode >= 200 && statusCode < 300;
  final safeElapsedMs = elapsedMs <= 0 ? 1 : elapsedMs;
  final bytesPerSecond = ((actualSize * 1000) / safeElapsedMs).round();
  final throughputMbps = bytesPerSecond * 8 / 1000 / 1000;

  return DownloadAttemptResult(
    channel: channel.cliName,
    success: statusOk && fileSizeVerified && checksumVerified,
    elapsedMs: elapsedMs,
    statusCode: statusCode,
    fileSizeVerified: fileSizeVerified,
    checksumVerified: checksumVerified,
    bytesPerSecond: bytesPerSecond,
    throughputMbps: throughputMbps,
    outputFileMode: 'download_to_file',
    errorMessage: null,
  );
}

Future<void> _ensureRhttpInitialized() async {
  final future = _rhttpInitFuture ??= rhttp.Rhttp.init();
  try {
    await future;
  } catch (_) {
    if (identical(_rhttpInitFuture, future)) {
      _rhttpInitFuture = null;
    }
    rethrow;
  }
}

DownloadBenchChannelResult _aggregateChannelResults(
  DownloadBenchChannel channel,
  List<DownloadAttemptResult> attempts,
) {
  final successful = attempts.where((item) => item.success).toList();
  final latencies = successful.map((item) => item.elapsedMs).toList();
  final latency = LatencySnapshot.fromSamples(latencies);
  final bytesPerSecond = successful.isEmpty
      ? 0
      : (successful
                    .map((item) => item.bytesPerSecond)
                    .reduce((left, right) => left + right) /
                successful.length)
            .round();
  final double throughputMbps = successful.isEmpty
      ? 0
      : successful
                .map((item) => item.throughputMbps)
                .reduce((left, right) => left + right) /
            successful.length;

  return DownloadBenchChannelResult(
    channel: channel.cliName,
    successCount: successful.length,
    failureCount: attempts.length - successful.length,
    fileSizeVerifiedCount: attempts
        .where((item) => item.fileSizeVerified)
        .length,
    checksumVerifiedCount: attempts
        .where((item) => item.checksumVerified)
        .length,
    downloadP50Ms: latency.p50Ms,
    downloadP95Ms: latency.p95Ms,
    avgMs: latency.avgMs,
    bytesPerSecond: bytesPerSecond,
    throughputMbps: throughputMbps,
    outputFileMode: 'download_to_file',
  );
}

Future<void> _cleanupTempFile(File file) async {
  if (!file.existsSync()) {
    return;
  }
  await file.delete();
}
