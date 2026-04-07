import 'dart:convert';
import 'dart:io';

const String _kDownloadBenchArgsEnv = 'FRN_RHTTP_DOWNLOAD_BENCH_ARGS_JSON';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  try {
    final process = await Process.start(
      'flutter',
      [
        'test',
        'tool/rhttp_download_bench_driver_test.dart',
        '--plain-name=rhttp_download_bench_driver',
      ],
      workingDirectory: Directory.current.path,
      runInShell: true,
      environment: {
        ...Platform.environment,
        _kDownloadBenchArgsEnv: jsonEncode(args),
      },
    );

    final stdoutDone = stdout.addStream(process.stdout);
    final stderrDone = stderr.addStream(process.stderr);
    final resultExitCode = await process.exitCode;
    await stdoutDone;
    await stderrDone;
    exit(resultExitCode);
  } on ProcessException catch (error) {
    stderr.writeln('[rhttp-download-bench] failed: $error');
    stderr.writeln(
      'Failed to start `flutter test`. Ensure Flutter is installed and on PATH.',
    );
    exitCode = 2;
  }
}

void _printUsage() {
  stdout.writeln('''
rhttp_download_bench.dart - standalone local benchmark for Dio vs rhttp download-to-file

Usage:
  dart run tool/rhttp_download_bench.dart [options]

Options:
  --base-url=http://127.0.0.1:18080
  --channels=dio,rhttp           default: dio,rhttp
  --file-bytes=16777216          default: 16 MiB
  --requests=3                   measured downloads per channel
  --warmup=1                     warmup downloads per channel
  --concurrency=1                parallel workers
  --chunk-bytes=65536            local server chunk size
  --chunk-delay-ms=0             local server per-chunk delay
  --verbose=true|false           default: true
  --output=build/rhttp_download_bench.json

Examples:
  dart run tool/rhttp_download_bench.dart --file-bytes=1048576 --requests=2 --warmup=1 --output=build/local.json
  dart run tool/rhttp_download_bench.dart --base-url=http://127.0.0.1:18080 --channels=dio,rhttp --file-bytes=4194304
''');
}
