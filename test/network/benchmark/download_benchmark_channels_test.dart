import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/benchmark/benchmark_config.dart';
import 'package:flutter_rust_net/network/benchmark/benchmark_scenario_server.dart';
import 'package:flutter_rust_net/network/benchmark/download_benchmark_config.dart';
import 'package:flutter_rust_net/network/benchmark/download_benchmark_harness.dart';

import '../test_support/real_rhttp_test_support.dart';

void main() {
  final realRhttpSkip = realRhttpSkipReason();

  group('download benchmark channel runners', () {
    late ScenarioServer server;
    late Directory tempDir;

    setUp(() async {
      server = await ScenarioServer.start(
        const BenchmarkConfig(largePayloadBytes: 256 * 1024),
        logger: (_) {},
      );
      tempDir = await Directory.systemTemp.createTemp('download-bench-test-');
    });

    tearDown(() async {
      await server.close();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'dio channel downloads file with verified size and checksum',
      () async {
        final outputPath = '${tempDir.path}/dio.bin';

        final result = await runSingleDownloadAttempt(
          channel: DownloadBenchChannel.dio,
          baseUrl: server.baseUrl,
          fileBytes: 256 * 1024,
          outputPath: outputPath,
        );

        expect(result.success, isTrue);
        expect(result.fileSizeVerified, isTrue);
        expect(result.checksumVerified, isTrue);
        expect(await File(outputPath).length(), 256 * 1024);
      },
    );

    test(
      'rhttp channel downloads file with verified size and checksum',
      () async {
        final outputPath = '${tempDir.path}/rhttp.bin';

        final result = await runSingleDownloadAttempt(
          channel: DownloadBenchChannel.rhttp,
          baseUrl: server.baseUrl,
          fileBytes: 256 * 1024,
          outputPath: outputPath,
        );

        expect(result.success, isTrue);
        expect(result.fileSizeVerified, isTrue);
        expect(result.checksumVerified, isTrue);
        expect(await File(outputPath).length(), 256 * 1024);
      },
      skip: realRhttpSkip,
    );
  });
}
