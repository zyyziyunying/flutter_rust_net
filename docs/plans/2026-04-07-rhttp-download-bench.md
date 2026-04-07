# Rhttp Download Bench Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a standalone repository-local benchmark that compares `dio` and `rhttp` on verified download-to-file workloads without touching the current gateway transfer abstraction.

**Architecture:** Reuse the existing local benchmark scenario server for loopback mode, add a dedicated binary download endpoint, and build a new download benchmark harness plus CLI wrapper that mirrors the existing `tool/network_bench.dart` driver pattern. Keep download execution explicit per channel so the benchmark measures raw client download capability instead of the current `NetworkGateway.startTransferTask()` routing model.

**Tech Stack:** Dart, Flutter test runner, Dio, rhttp 0.16.0 stream APIs, local `HttpServer`, file IO, JSON report serialization.

---

### Task 1: Add the local download endpoint contract

**Files:**
- Create: `test/network/benchmark/benchmark_scenario_server_test.dart`
- Modify: `lib/network/benchmark/benchmark_scenario_server.dart`

**Step 1: Write the failing test**

Use `@test-driven-development`.

Create a focused test that starts `ScenarioServer`, requests `/bench/download-file`, and verifies:

- `200 OK`
- `content-length` equals requested byte size
- streamed body length equals requested byte size
- deterministic checksum helper returns the expected value

```dart
test('download-file endpoint returns requested byte count and checksum', () async {
  final config = const BenchmarkConfig(
    scenario: BenchmarkScenario.smallJson,
    largePayloadBytes: 1024,
  );
  final server = await ScenarioServer.start(config, logger: (_) {});
  addTearDown(server.close);

  final client = HttpClient();
  addTearDown(client.close);

  final request = await client.getUrl(
    Uri.parse('${server.baseUrl}/bench/download-file?bytes=4096&chunkBytes=1024'),
  );
  final response = await request.close();
  final body = await response.fold<List<int>>(<int>[], (all, chunk) {
    all.addAll(chunk);
    return all;
  });

  expect(response.statusCode, HttpStatus.ok);
  expect(response.headers.value(HttpHeaders.contentLengthHeader), '4096');
  expect(body.length, 4096);
  expect(_rollingChecksum(body), _rollingChecksum(_expectedDownloadPayload(4096)));
});
```

**Step 2: Run test to verify it fails**

Run:

```bash
flutter test test/network/benchmark/benchmark_scenario_server_test.dart -r compact
```

Expected: FAIL because `/bench/download-file` does not exist yet.

**Step 3: Write minimal implementation**

In `lib/network/benchmark/benchmark_scenario_server.dart`:

- add a deterministic payload builder
- add `/bench/download-file`
- parse `bytes`, `chunkBytes`, `chunkDelayMs`
- write the body in chunks

```dart
case '/bench/download-file':
  await _handleDownloadFile(request);
  return;
```

```dart
Future<void> _handleDownloadFile(HttpRequest request) async {
  final totalBytes = _parseInt(request.uri.queryParameters['bytes'], fallback: _config.largePayloadBytes);
  final chunkBytes = _parseInt(request.uri.queryParameters['chunkBytes'], fallback: 64 * 1024);
  final chunkDelayMs = _parseInt(request.uri.queryParameters['chunkDelayMs'], fallback: 0);
  final payload = _buildDownloadPayload(totalBytes);

  request.response
    ..statusCode = HttpStatus.ok
    ..headers.contentType = ContentType.binary
    ..headers.set(HttpHeaders.contentLengthHeader, payload.length);

  for (var offset = 0; offset < payload.length; offset += chunkBytes) {
    final end = min(offset + chunkBytes, payload.length);
    request.response.add(payload.sublist(offset, end));
    await request.response.flush();
    if (chunkDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: chunkDelayMs));
    }
  }
  await request.response.close();
}
```

**Step 4: Run test to verify it passes**

Run:

```bash
flutter test test/network/benchmark/benchmark_scenario_server_test.dart -r compact
```

Expected: PASS.

**Step 5: Commit**

```bash
git add test/network/benchmark/benchmark_scenario_server_test.dart lib/network/benchmark/benchmark_scenario_server.dart
git commit -m "feat: add benchmark download endpoint"
```

### Task 2: Add channel-level download integration tests

**Files:**
- Create: `test/network/benchmark/download_benchmark_channels_test.dart`
- Create: `lib/network/benchmark/download_benchmark_config.dart`
- Create: `lib/network/benchmark/download_benchmark_harness.dart`

**Step 1: Write the failing tests**

Use `@test-driven-development`.

Create one `dio` test and one `rhttp` test. Each test should:

- start the local scenario server
- download a small binary file to a temp path
- verify file length
- verify checksum
- delete the temp file

```dart
test('dio channel downloads file with verified size and checksum', () async {
  final result = await runSingleDownloadAttempt(
    channel: DownloadBenchChannel.dio,
    baseUrl: server.baseUrl,
    fileBytes: 256 * 1024,
    outputPath: tempFile.path,
  );

  expect(result.success, isTrue);
  expect(result.fileSizeVerified, isTrue);
  expect(result.checksumVerified, isTrue);
});

test('rhttp channel downloads file with verified size and checksum', () async {
  final result = await runSingleDownloadAttempt(
    channel: DownloadBenchChannel.rhttp,
    baseUrl: server.baseUrl,
    fileBytes: 256 * 1024,
    outputPath: tempFile.path,
  );

  expect(result.success, isTrue);
  expect(result.fileSizeVerified, isTrue);
  expect(result.checksumVerified, isTrue);
});
```

**Step 2: Run test to verify it fails**

Run:

```bash
flutter test test/network/benchmark/download_benchmark_channels_test.dart -r compact
```

Expected: FAIL because the config, runner, and channel implementations do not exist yet.

**Step 3: Write minimal implementation**

Create:

- `DownloadBenchChannel` enum with `dio` and `rhttp`
- `DownloadBenchConfig`
- a low-level `runSingleDownloadAttempt(...)`

Implement channel-specific helpers inside `lib/network/benchmark/download_benchmark_harness.dart`:

```dart
Future<DownloadAttemptResult> _downloadWithDio(...) async {
  final dio = Dio();
  final watch = Stopwatch()..start();
  await dio.downloadUri(uri, outputPath);
  watch.stop();
  return _finalizeAttempt(..., elapsedMs: watch.elapsedMilliseconds);
}
```

```dart
Future<DownloadAttemptResult> _downloadWithRhttp(...) async {
  await rhttp.Rhttp.init();
  final client = await rhttp.RhttpClient.create();
  final response = await client.getStream(uri.toString());
  final sink = File(outputPath).openWrite();
  final watch = Stopwatch()..start();
  await for (final chunk in response.body) {
    sink.add(chunk);
  }
  await sink.close();
  watch.stop();
  return _finalizeAttempt(..., elapsedMs: watch.elapsedMilliseconds);
}
```

Use a simple in-repo deterministic checksum helper instead of adding a new package dependency.

**Step 4: Run test to verify it passes**

Run:

```bash
flutter test test/network/benchmark/download_benchmark_channels_test.dart -r compact
```

Expected: PASS for both channels.

**Step 5: Commit**

```bash
git add test/network/benchmark/download_benchmark_channels_test.dart lib/network/benchmark/download_benchmark_config.dart lib/network/benchmark/download_benchmark_harness.dart
git commit -m "feat: add dio and rhttp download bench runners"
```

### Task 3: Add harness aggregation and failure-accounting tests

**Files:**
- Create: `test/network/benchmark/download_benchmark_harness_test.dart`
- Create: `lib/network/benchmark/download_benchmark_report.dart`
- Modify: `lib/network/benchmark/download_benchmark_harness.dart`

**Step 1: Write the failing tests**

Use `@test-driven-development`.

Write one test for a successful local benchmark run and one test for a forced failure.

The success test should verify:

- `serverMode == local`
- both channels have `successCount == 1`
- `outputFileMode == 'download_to_file'`
- p50 / p95 / avg fields are present

The failure test should verify:

- failed attempts increment `failureCount`
- report still serializes to JSON

```dart
test('runDownloadBenchmark aggregates local dio and rhttp results', () async {
  final report = await runDownloadBenchmark(
    const DownloadBenchConfig(fileBytes: 128 * 1024, requests: 1, warmupRequests: 0),
  );

  expect(report.serverMode, 'local');
  expect(report.channelResults, hasLength(2));
  expect(report.channelResults.every((item) => item.successCount == 1), isTrue);
  expect(report.channelResults.every((item) => item.outputFileMode == 'download_to_file'), isTrue);
});
```

**Step 2: Run test to verify it fails**

Run:

```bash
flutter test test/network/benchmark/download_benchmark_harness_test.dart -r compact
```

Expected: FAIL because the report model and aggregate runner do not exist yet.

**Step 3: Write minimal implementation**

Create a report model with stable JSON fields:

```dart
class DownloadBenchReport {
  final String baseUrl;
  final String serverMode;
  final int fileBytes;
  final int requests;
  final int warmupRequests;
  final int concurrency;
  final int chunkBytes;
  final int chunkDelayMs;
  final List<DownloadBenchChannelResult> channelResults;
}
```

Add `runDownloadBenchmark(...)` to:

- optionally start `ScenarioServer`
- warm up per channel
- run measured attempts
- aggregate latency snapshots
- count size / checksum verification
- clean up temp files and local server

Prefer injection points for channel runners in the harness so failure accounting can be tested without network-only mocking.

**Step 4: Run test to verify it passes**

Run:

```bash
flutter test test/network/benchmark/download_benchmark_harness_test.dart -r compact
```

Expected: PASS.

**Step 5: Commit**

```bash
git add test/network/benchmark/download_benchmark_harness_test.dart lib/network/benchmark/download_benchmark_report.dart lib/network/benchmark/download_benchmark_harness.dart
git commit -m "feat: add download bench report aggregation"
```

### Task 4: Add the CLI wrapper and driver test

**Files:**
- Create: `tool/rhttp_download_bench.dart`
- Create: `tool/rhttp_download_bench_driver_test.dart`
- Modify: `lib/network/benchmark/download_benchmark_config.dart`
- Modify: `lib/network/benchmark/download_benchmark_report.dart`
- Modify: `lib/network/benchmark/download_benchmark_harness.dart`

**Step 1: Write the failing driver test**

Use `@test-driven-development`.

Follow the existing `tool/network_bench.dart` pattern:

- `tool/rhttp_download_bench.dart` should shell out to `flutter test`
- `tool/rhttp_download_bench_driver_test.dart` should parse CLI args from an env var
- the driver test should write the JSON report to `--output`

Driver test sketch:

```dart
test('rhttp_download_bench_driver', () async {
  final rawArgs = Platform.environment['FRN_RHTTP_DOWNLOAD_BENCH_ARGS_JSON'];
  expect(rawArgs, isNotNull);

  final config = _buildConfig(_parseArgs(...));
  final report = await runDownloadBenchmark(config);

  final output = kvArgs['output'];
  if (output != null && output.isNotEmpty) {
    await File(output).writeAsString(
      const JsonEncoder.withIndent('  ').convert(report.toJson()),
    );
  }
});
```

**Step 2: Run test to verify it fails**

Run:

```bash
flutter test tool/rhttp_download_bench_driver_test.dart --plain-name=rhttp_download_bench_driver
```

Expected: FAIL because the driver, env key, and config parsing are not implemented.

**Step 3: Write minimal implementation**

Implement:

- `tool/rhttp_download_bench.dart`
- `--help`
- env var handoff
- config parsing for:
  - `--base-url`
  - `--channels`
  - `--file-bytes`
  - `--requests`
  - `--warmup`
  - `--concurrency`
  - `--chunk-bytes`
  - `--chunk-delay-ms`
  - `--output`

Wrapper sketch:

```dart
final process = await Process.start(
  'flutter',
  [
    'test',
    'tool/rhttp_download_bench_driver_test.dart',
    '--plain-name=rhttp_download_bench_driver',
  ],
  environment: {
    ...Platform.environment,
    'FRN_RHTTP_DOWNLOAD_BENCH_ARGS_JSON': jsonEncode(args),
  },
  runInShell: true,
);
```

**Step 4: Run test to verify it passes**

Run:

```bash
flutter test tool/rhttp_download_bench_driver_test.dart --plain-name=rhttp_download_bench_driver
dart run tool/rhttp_download_bench.dart --help
```

Expected:

- driver test PASS
- help text prints the supported flags

**Step 5: Commit**

```bash
git add tool/rhttp_download_bench.dart tool/rhttp_download_bench_driver_test.dart lib/network/benchmark/download_benchmark_config.dart lib/network/benchmark/download_benchmark_report.dart lib/network/benchmark/download_benchmark_harness.dart
git commit -m "feat: add standalone rhttp download bench cli"
```

### Task 5: Run verification commands and capture baseline outputs

**Files:**
- Modify: `docs/plans/2026-04-07-rhttp-download-bench-design.md`
- Modify: `docs/plans/2026-04-07-rhttp-download-bench.md`

**Step 1: Run local verification**

Use `@verification-before-completion`.

Run:

```bash
flutter test test/network/benchmark/benchmark_scenario_server_test.dart -r compact
flutter test test/network/benchmark/download_benchmark_channels_test.dart -r compact
flutter test test/network/benchmark/download_benchmark_harness_test.dart -r compact
flutter test tool/rhttp_download_bench_driver_test.dart --plain-name=rhttp_download_bench_driver
FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR="$HOME/.pub-cache/hosted/pub.flutter-io.cn/rhttp-0.16.0/rust/target/release" dart run tool/rhttp_download_bench.dart --file-bytes=1048576 --requests=2 --warmup=1 --concurrency=1 --output=build/rhttp_download_local_smoke.json
```

Expected:

- all tests PASS
- local smoke writes `build/rhttp_download_local_smoke.json`
- report contains both `dio` and `rhttp`

**Step 2: Run optional remote verification**

Only if a compatible remote endpoint exists:

```bash
FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR="$HOME/.pub-cache/hosted/pub.flutter-io.cn/rhttp-0.16.0/rust/target/release" dart run tool/rhttp_download_bench.dart --base-url=http://<compatible-host>:<port> --file-bytes=1048576 --requests=2 --warmup=1 --concurrency=1 --output=build/rhttp_download_remote_smoke.json
```

Expected: JSON report writes successfully. If the endpoint is missing, record that remote verification is blocked instead of changing scope.

**Step 3: Update the plan documents with actual verification notes**

Append:

- exact commands run
- output paths
- whether remote verification was available

**Step 4: Commit**

```bash
git add docs/plans/2026-04-07-rhttp-download-bench-design.md docs/plans/2026-04-07-rhttp-download-bench.md build/rhttp_download_local_smoke.json
git commit -m "docs: record rhttp download bench verification"
```
