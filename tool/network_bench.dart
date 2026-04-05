import 'dart:convert';
import 'dart:io';

const String _kBenchArgsEnv = 'FRN_NETWORK_BENCH_ARGS_JSON';

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
        'tool/network_bench_driver_test.dart',
        '--plain-name=network_bench_driver',
      ],
      workingDirectory: Directory.current.path,
      runInShell: true,
      environment: {...Platform.environment, _kBenchArgsEnv: jsonEncode(args)},
    );

    final stdoutDone = stdout.addStream(process.stdout);
    final stderrDone = stderr.addStream(process.stderr);
    final resultExitCode = await process.exitCode;
    await stdoutDone;
    await stderrDone;
    exit(resultExitCode);
  } on ProcessException catch (error) {
    stderr.writeln('[network-bench] failed: $error');
    stderr.writeln(
      'Failed to start `flutter test`. Ensure Flutter is installed and on PATH.',
    );
    exitCode = 2;
  }
}

void _printUsage() {
  stdout.writeln('''
network_bench.dart - realistic local benchmark for Dio vs the primary request channel (`rust` alias)

Usage:
  dart run tool/network_bench.dart [options]

Options:
  --scenario=small_json|large_json|large_payload|jitter_latency|flaky_http
  --consume-mode=none|json_decode|json_model
  --channels=dio,rust             default: dio,rust (`rust` = primary-channel alias)
  --requests=120                  measured requests per channel
  --warmup=12                     warmup requests per channel
  --concurrency=12                parallel workers
  --preflight-primary-channel=true|false  default: true
  --require-primary-channel=true|false    default: false
  --fallback=true|false           gateway fallback switch, default: true
  --verbose=true|false            default: true
  --output=build/network_bench.json
  --base-url=http://127.0.0.1:18080

Scenario knobs:
  --large-bytes=2097152           for large_payload / large_json
  --jitter-base-ms=12             for jitter_latency
  --jitter-extra-ms=80            for jitter_latency
  --flaky-every=5                 for flaky_http

Client knobs:
  --connect-timeout-ms=5000
  --receive-timeout-ms=15000
  --request-key-space=0            0=disable reuse; >0 reuses request ids for cache probing

Examples:
  dart run tool/network_bench.dart --scenario=small_json --requests=400 --concurrency=16 --output=build/small.json
  dart run tool/network_bench.dart --scenario=large_payload --channels=dio,rust --preflight-primary-channel=true --output=build/large.json
  dart run tool/network_bench.dart --scenario=flaky_http --channels=dio --flaky-every=4
  dart run tool/network_bench.dart --base-url=http://47.110.52.208:7777 --scenario=jitter_latency --channels=dio,rust
''');
}
