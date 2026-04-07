import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/benchmark/download_benchmark_config.dart';
import 'package:flutter_rust_net/network/benchmark/download_benchmark_harness.dart';

import '../test_support/real_rhttp_test_support.dart';

void main() {
  group('runDownloadBenchmark', () {
    test('aggregates local dio and rhttp results', () async {
      final report = await runDownloadBenchmark(
        const DownloadBenchConfig(
          fileBytes: 128 * 1024,
          requests: 1,
          warmupRequests: 0,
          channels: {DownloadBenchChannel.dio, DownloadBenchChannel.rhttp},
          verbose: false,
        ),
        attemptRunner:
            ({
              required channel,
              required baseUrl,
              required fileBytes,
              required outputPath,
              required chunkBytes,
              required chunkDelayMs,
              dioClient,
              rhttpClient,
            }) async {
              return DownloadAttemptResult(
                channel: channel.cliName,
                success: true,
                elapsedMs: channel == DownloadBenchChannel.dio ? 12 : 18,
                statusCode: 200,
                fileSizeVerified: true,
                checksumVerified: true,
                bytesPerSecond: fileBytes * 1000,
                throughputMbps: 8,
                outputFileMode: 'download_to_file',
                errorMessage: null,
              );
            },
      );

      expect(report.serverMode, 'local');
      expect(report.channelResults, hasLength(2));
      expect(
        report.channelResults.every((item) => item.successCount == 1),
        isTrue,
      );
      expect(
        report.channelResults.every(
          (item) => item.outputFileMode == 'download_to_file',
        ),
        isTrue,
      );
      expect(
        report.channelResults.every((item) => item.downloadP50Ms > 0),
        isTrue,
      );
      expect(
        report.channelResults.every((item) => item.downloadP95Ms > 0),
        isTrue,
      );
      expect(report.channelResults.every((item) => item.avgMs > 0), isTrue);
    });

    test('records failures and still serializes to json', () async {
      final report = await runDownloadBenchmark(
        const DownloadBenchConfig(
          fileBytes: 64 * 1024,
          requests: 1,
          warmupRequests: 0,
          channels: {DownloadBenchChannel.dio},
          verbose: false,
        ),
        attemptRunner:
            ({
              required channel,
              required baseUrl,
              required fileBytes,
              required outputPath,
              required chunkBytes,
              required chunkDelayMs,
              dioClient,
              rhttpClient,
            }) async {
              return const DownloadAttemptResult(
                channel: 'dio',
                success: false,
                elapsedMs: 0,
                statusCode: 503,
                fileSizeVerified: false,
                checksumVerified: false,
                bytesPerSecond: 0,
                throughputMbps: 0,
                outputFileMode: 'download_to_file',
                errorMessage: 'forced failure',
              );
            },
      );

      final json = report.toJson();
      expect(report.channelResults.single.failureCount, 1);
      expect(json['serverMode'], 'local');
      expect(json['channelResults'], isA<List<dynamic>>());
    });

    test('skips unavailable rhttp channel and still runs dio', () async {
      final missingRhttpReason = realRhttpSkipReason();
      if (missingRhttpReason == null) {
        return;
      }

      final report = await runDownloadBenchmark(
        const DownloadBenchConfig(
          fileBytes: 64 * 1024,
          requests: 1,
          warmupRequests: 0,
          channels: {DownloadBenchChannel.dio, DownloadBenchChannel.rhttp},
          verbose: false,
        ),
      );

      expect(report.channelResults.map((item) => item.channel), ['dio']);
      expect(report.skippedChannels.keys, ['rhttp']);
      expect(
        report.skippedChannels['rhttp'],
        contains('download request channel setup failed'),
      );
    });
  });
}
