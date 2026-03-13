import 'dart:convert';
import 'dart:io';

//TODO 拆分
const String _defaultBaseUrl = 'http://47.110.52.208:7777';
const String _defaultUploadEndpoint = '/upload';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  final startedAt = DateTime.now();
  final packageRoot = _resolvePackageRoot();
  final options = _parseOptions(
    args,
    startedAt: startedAt,
    packageRoot: packageRoot,
  );
  final outputDir = _resolveOutputDir(packageRoot, options.outputDirPath);
  final logsDir = Directory('${outputDir.path}/logs');
  await logsDir.create(recursive: true);

  final commandRuns = <Map<String, Object?>>[];
  final aggregateRuns = <Map<String, Object?>>[];
  Map<String, Object?>? uploadRun;
  String? failure;
  var manifestWritten = false;

  stdout.writeln(
    '[p1-non-loopback] preset=${options.preset.name} '
    'baseUrl=${options.baseUrl} runId=${options.runId}',
  );
  stdout.writeln('[p1-non-loopback] output=${outputDir.path}');

  final gitCommit = options.commit ?? await _readGitCommit(packageRoot);
  final gitDirty = await _readGitDirty(packageRoot);
  final archivePlan = _buildArchivePlan(
    options: options,
    gitCommit: gitCommit,
    startedAt: startedAt,
  );

  try {
    for (final bench in _buildBenchPlan(options, outputDir)) {
      final result = await _runCommand(
        label: bench.label,
        executable: 'dart',
        arguments: ['run', 'tool/network_bench.dart', ...bench.arguments],
        workingDirectory: packageRoot,
        logsDir: logsDir,
      );
      commandRuns.add({
        'label': bench.label,
        'kind': 'benchmark',
        'scenario': bench.scenario,
        'outputFile': bench.outputFile.path,
        'command': result.command,
        'startedAt': result.startedAt.toIso8601String(),
        'finishedAt': result.finishedAt.toIso8601String(),
        'durationMs': result.durationMs,
        'exitCode': result.exitCode,
        'stdoutLog': result.stdoutLog.path,
        'stderrLog': result.stderrLog.path,
      });
      if (result.exitCode != 0) {
        throw ProcessException(
          'dart',
          ['run', 'tool/network_bench.dart', ...bench.arguments],
          'benchmark failed: ${bench.label}',
          result.exitCode,
        );
      }
    }

    for (final aggregate in _buildAggregatePlan(options, outputDir)) {
      final result = await _runCommand(
        label: aggregate.label,
        executable: 'dart',
        arguments: ['run', 'tool/p1_aggregate.dart', ...aggregate.arguments],
        workingDirectory: packageRoot,
        logsDir: logsDir,
      );
      aggregateRuns.add({
        'label': aggregate.label,
        'kind': 'aggregate',
        'scenario': aggregate.scenario,
        'command': result.command,
        'startedAt': result.startedAt.toIso8601String(),
        'finishedAt': result.finishedAt.toIso8601String(),
        'durationMs': result.durationMs,
        'exitCode': result.exitCode,
        'stdoutLog': result.stdoutLog.path,
        'stderrLog': result.stderrLog.path,
        'outputMarkdown': aggregate.outputMarkdown.path,
        'outputJson': aggregate.outputJson.path,
      });
      if (result.exitCode != 0) {
        throw ProcessException(
          'dart',
          ['run', 'tool/p1_aggregate.dart', ...aggregate.arguments],
          'aggregation failed: ${aggregate.label}',
          result.exitCode,
        );
      }
    }

    if (options.upload) {
      final uploadArgs = <String>[
        'run',
        'tool/upload_bench_log.dart',
        '--input=${outputDir.path}',
        '--ext=json',
        '--base-url=${options.baseUrl}',
        '--endpoint=${options.uploadEndpoint}',
        '--remote-prefix=${archivePlan.remotePrefix}',
      ];
      for (final entry in archivePlan.extraFields.entries) {
        uploadArgs.add('--extra-field=${entry.key}=${entry.value}');
      }
      for (final header in options.uploadHeaders) {
        uploadArgs.add('--header=$header');
      }
      final result = await _runCommand(
        label: 'upload_json_reports',
        executable: 'dart',
        arguments: uploadArgs,
        displayArguments: _redactSensitiveArguments(uploadArgs),
        workingDirectory: packageRoot,
        logsDir: logsDir,
      );
      uploadRun = {
        'kind': 'upload',
        'command': result.command,
        'startedAt': result.startedAt.toIso8601String(),
        'finishedAt': result.finishedAt.toIso8601String(),
        'durationMs': result.durationMs,
        'exitCode': result.exitCode,
        'stdoutLog': result.stdoutLog.path,
        'stderrLog': result.stderrLog.path,
        'remotePrefix': archivePlan.remotePrefix,
        'extraFields': archivePlan.extraFields,
        'headers': _redactSensitiveArguments(options.uploadHeaders),
      };
      if (result.exitCode != 0) {
        throw ProcessException(
          'dart',
          uploadArgs,
          'upload failed',
          result.exitCode,
        );
      }
    }
  } catch (error) {
    failure = '$error';
    stderr.writeln('[p1-non-loopback] failed: $failure');
    exitCode = 1;
  } finally {
    final finishedAt = DateTime.now();
    final manifestFile = File('${outputDir.path}/run_manifest.json');
    final manifest = <String, Object?>{
      'startedAt': startedAt.toIso8601String(),
      'finishedAt': finishedAt.toIso8601String(),
      'durationMs': finishedAt.difference(startedAt).inMilliseconds,
      'status': failure == null ? 'success' : 'failed',
      'failure': failure,
      'packageRoot': packageRoot.path,
      'outputDir': outputDir.path,
      'baseUrl': options.baseUrl,
      'preset': options.preset.name,
      'runId': options.runId,
      'metadata': {
        'networkProfile': options.networkProfile,
        'device': options.device,
        'linkType': options.linkType,
        'operator': options.operator,
        'gitCommit': gitCommit,
        'gitDirty': gitDirty,
      },
      'archivePlan': {
        'remotePrefix': archivePlan.remotePrefix,
        'extraFields': archivePlan.extraFields,
        'uploadEndpoint': options.uploadEndpoint,
      },
      'commands': commandRuns,
      'aggregates': aggregateRuns,
      'upload': uploadRun,
    };
    await manifestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest),
    );
    manifestWritten = true;
    stdout.writeln('[p1-non-loopback] manifest saved to ${manifestFile.path}');
  }

  if (manifestWritten && failure == null) {
    stdout.writeln('[p1-non-loopback] completed successfully.');
  }
}

class _CliOptions {
  final _Preset preset;
  final String baseUrl;
  final String outputDirPath;
  final String runId;
  final int rustMaxInFlightTasks;
  final String networkProfile;
  final String device;
  final String linkType;
  final String? operator;
  final String? commit;
  final bool upload;
  final String uploadEndpoint;
  final List<String> uploadHeaders;

  const _CliOptions({
    required this.preset,
    required this.baseUrl,
    required this.outputDirPath,
    required this.runId,
    required this.rustMaxInFlightTasks,
    required this.networkProfile,
    required this.device,
    required this.linkType,
    required this.operator,
    required this.commit,
    required this.upload,
    required this.uploadEndpoint,
    required this.uploadHeaders,
  });
}

enum _Preset { smoke, standard }

class _BenchSpec {
  final String label;
  final String scenario;
  final List<String> arguments;
  final File outputFile;

  const _BenchSpec({
    required this.label,
    required this.scenario,
    required this.arguments,
    required this.outputFile,
  });
}

class _AggregateSpec {
  final String label;
  final String scenario;
  final List<String> arguments;
  final File outputMarkdown;
  final File outputJson;

  const _AggregateSpec({
    required this.label,
    required this.scenario,
    required this.arguments,
    required this.outputMarkdown,
    required this.outputJson,
  });
}

class _ArchivePlan {
  final String remotePrefix;
  final Map<String, String> extraFields;

  const _ArchivePlan({required this.remotePrefix, required this.extraFields});
}

class _CommandResult {
  final String command;
  final int exitCode;
  final DateTime startedAt;
  final DateTime finishedAt;
  final File stdoutLog;
  final File stderrLog;

  const _CommandResult({
    required this.command,
    required this.exitCode,
    required this.startedAt,
    required this.finishedAt,
    required this.stdoutLog,
    required this.stderrLog,
  });

  int get durationMs => finishedAt.difference(startedAt).inMilliseconds;
}

_CliOptions _parseOptions(
  List<String> args, {
  required DateTime startedAt,
  required Directory packageRoot,
}) {
  var preset = _Preset.standard;
  var baseUrl = _defaultBaseUrl;
  String? outputDirPath;
  String? runId;
  var rustMaxInFlightTasks = 32;
  var networkProfile = 'ethernet';
  var device = 'host_windows';
  var linkType = 'public_remote';
  String? operator;
  String? commit;
  var upload = false;
  var uploadEndpoint = _defaultUploadEndpoint;
  final uploadHeaders = <String>[];

  for (final arg in args) {
    if (!arg.startsWith('--')) {
      throw ArgumentError('invalid argument: $arg');
    }
    final payload = arg.substring(2);
    if (payload.isEmpty) {
      continue;
    }
    final splitIndex = payload.indexOf('=');
    if (splitIndex <= 0) {
      throw ArgumentError('invalid argument: $arg');
    }
    final key = payload.substring(0, splitIndex);
    final value = payload.substring(splitIndex + 1);
    switch (key) {
      case 'preset':
        preset = _parsePreset(value);
        break;
      case 'base-url':
        baseUrl = _normalizeBaseUrl(value);
        break;
      case 'output-dir':
        outputDirPath = value;
        break;
      case 'run-id':
        runId = value;
        break;
      case 'rust-max-in-flight':
        rustMaxInFlightTasks = _parseInt(value, label: 'rust-max-in-flight');
        break;
      case 'network-profile':
        networkProfile = value.trim();
        break;
      case 'device':
        device = value.trim();
        break;
      case 'link-type':
        linkType = value.trim();
        break;
      case 'operator':
        operator = value.trim().isEmpty ? null : value.trim();
        break;
      case 'commit':
        commit = value.trim().isEmpty ? null : value.trim();
        break;
      case 'upload':
        upload = _parseBool(value);
        break;
      case 'upload-endpoint':
        uploadEndpoint = value;
        break;
      case 'upload-header':
        uploadHeaders.add(value);
        break;
      default:
        throw ArgumentError('unsupported option: --$key');
    }
  }

  final resolvedRunId = (runId == null || runId.trim().isEmpty)
      ? _formatRunId(startedAt)
      : runId.trim();
  final resolvedOutputDir =
      outputDirPath == null || outputDirPath.trim().isEmpty
      ? 'build/remote_public_$resolvedRunId'
      : outputDirPath.trim();

  if (networkProfile.isEmpty) {
    throw ArgumentError('--network-profile cannot be empty');
  }
  if (device.isEmpty) {
    throw ArgumentError('--device cannot be empty');
  }
  if (linkType.isEmpty) {
    throw ArgumentError('--link-type cannot be empty');
  }
  if (rustMaxInFlightTasks <= 0) {
    throw ArgumentError('--rust-max-in-flight must be > 0');
  }
  if (!File('${packageRoot.path}/tool/network_bench.dart').existsSync()) {
    throw StateError(
      'tool/network_bench.dart not found under ${packageRoot.path}',
    );
  }

  return _CliOptions(
    preset: preset,
    baseUrl: baseUrl,
    outputDirPath: resolvedOutputDir,
    runId: resolvedRunId,
    rustMaxInFlightTasks: rustMaxInFlightTasks,
    networkProfile: networkProfile,
    device: device,
    linkType: linkType,
    operator: operator,
    commit: commit,
    upload: upload,
    uploadEndpoint: uploadEndpoint,
    uploadHeaders: List.unmodifiable(uploadHeaders),
  );
}

List<_BenchSpec> _buildBenchPlan(_CliOptions options, Directory outputDir) {
  final preset = options.preset;
  final smallRequests = preset == _Preset.smoke ? 20 : 40;
  final smallWarmup = preset == _Preset.smoke ? 2 : 4;
  final smallConcurrency = preset == _Preset.smoke ? 4 : 8;
  final jitterRequests = preset == _Preset.smoke ? 80 : 240;
  final jitterWarmup = preset == _Preset.smoke ? 8 : 24;
  final jitterConcurrency = preset == _Preset.smoke ? 8 : 16;

  return [
    _BenchSpec(
      label: 'remote_small_dio',
      scenario: 'small_json',
      outputFile: File('${outputDir.path}/remote_small_dio.json'),
      arguments: [
        '--base-url=${options.baseUrl}',
        '--scenario=small_json',
        '--channels=dio',
        '--requests=$smallRequests',
        '--warmup=$smallWarmup',
        '--concurrency=$smallConcurrency',
        '--output=${outputDir.path}/remote_small_dio.json',
      ],
    ),
    _BenchSpec(
      label: 'remote_small_rust',
      scenario: 'small_json',
      outputFile: File('${outputDir.path}/remote_small_rust.json'),
      arguments: [
        '--base-url=${options.baseUrl}',
        '--scenario=small_json',
        '--channels=rust',
        '--initialize-rust=true',
        '--require-rust=true',
        '--requests=$smallRequests',
        '--warmup=$smallWarmup',
        '--concurrency=$smallConcurrency',
        '--rust-max-in-flight=${options.rustMaxInFlightTasks}',
        '--output=${outputDir.path}/remote_small_rust.json',
      ],
    ),
    _BenchSpec(
      label: 'remote_jitter_mif${options.rustMaxInFlightTasks}',
      scenario: 'jitter_latency',
      outputFile: File(
        '${outputDir.path}/remote_jitter_mif${options.rustMaxInFlightTasks}.json',
      ),
      arguments: [
        '--base-url=${options.baseUrl}',
        '--scenario=jitter_latency',
        '--channels=dio,rust',
        '--initialize-rust=true',
        '--require-rust=true',
        '--requests=$jitterRequests',
        '--warmup=$jitterWarmup',
        '--concurrency=$jitterConcurrency',
        '--jitter-base-ms=12',
        '--jitter-extra-ms=80',
        '--rust-max-in-flight=${options.rustMaxInFlightTasks}',
        '--output=${outputDir.path}/remote_jitter_mif${options.rustMaxInFlightTasks}.json',
      ],
    ),
  ];
}

List<_AggregateSpec> _buildAggregatePlan(
  _CliOptions options,
  Directory outputDir,
) {
  return [
    _AggregateSpec(
      label: 'aggregate_small_json',
      scenario: 'small_json',
      outputMarkdown: File('${outputDir.path}/aggregate_small_json.md'),
      outputJson: File('${outputDir.path}/aggregate_small_json.json'),
      arguments: [
        '--input=${outputDir.path}',
        '--scenario=small_json',
        '--output-md=${outputDir.path}/aggregate_small_json.md',
        '--output-json=${outputDir.path}/aggregate_small_json.json',
      ],
    ),
    _AggregateSpec(
      label: 'aggregate_jitter_latency',
      scenario: 'jitter_latency',
      outputMarkdown: File('${outputDir.path}/aggregate_jitter_latency.md'),
      outputJson: File('${outputDir.path}/aggregate_jitter_latency.json'),
      arguments: [
        '--input=${outputDir.path}',
        '--scenario=jitter_latency',
        '--output-md=${outputDir.path}/aggregate_jitter_latency.md',
        '--output-json=${outputDir.path}/aggregate_jitter_latency.json',
      ],
    ),
  ];
}

_ArchivePlan _buildArchivePlan({
  required _CliOptions options,
  required String? gitCommit,
  required DateTime startedAt,
}) {
  final day = _formatDay(startedAt);
  final remotePrefix =
      'flutter_rust_net/$day/${options.networkProfile}/${options.device}/${options.runId}';
  final extraFields = <String, String>{
    'project': 'flutter_rust_net',
    'run_id': options.runId,
    'network_profile': options.networkProfile,
    'device': options.device,
    'link_type': options.linkType,
  };
  if (gitCommit != null && gitCommit.isNotEmpty) {
    extraFields['commit'] = gitCommit;
  }
  final operator = options.operator;
  if (operator != null && operator.isNotEmpty) {
    extraFields['operator'] = operator;
  }
  return _ArchivePlan(remotePrefix: remotePrefix, extraFields: extraFields);
}

Future<_CommandResult> _runCommand({
  required String label,
  required String executable,
  required List<String> arguments,
  List<String>? displayArguments,
  required Directory workingDirectory,
  required Directory logsDir,
}) async {
  final safeLabel = label.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
  final stdoutLog = File('${logsDir.path}/$safeLabel.stdout.log');
  final stderrLog = File('${logsDir.path}/$safeLabel.stderr.log');
  final stdoutSink = stdoutLog.openWrite();
  final stderrSink = stderrLog.openWrite();
  final startedAt = DateTime.now();
  final command = _formatCommand(executable, displayArguments ?? arguments);

  stdout.writeln('[p1-non-loopback] run $command');
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
    runInShell: true,
  );

  final stdoutDone = process.stdout.transform(utf8.decoder).listen((chunk) {
    stdout.write(chunk);
    stdoutSink.write(chunk);
  }).asFuture<void>();

  final stderrDone = process.stderr.transform(utf8.decoder).listen((chunk) {
    stderr.write(chunk);
    stderrSink.write(chunk);
  }).asFuture<void>();

  final exitCodeValue = await process.exitCode;
  await stdoutDone;
  await stderrDone;
  await stdoutSink.close();
  await stderrSink.close();

  final finishedAt = DateTime.now();
  return _CommandResult(
    command: command,
    exitCode: exitCodeValue,
    startedAt: startedAt,
    finishedAt: finishedAt,
    stdoutLog: stdoutLog,
    stderrLog: stderrLog,
  );
}

Directory _resolvePackageRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final pubspec = File('${current.path}/pubspec.yaml');
    final toolFile = File('${current.path}/tool/network_bench.dart');
    if (pubspec.existsSync() && toolFile.existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError(
        'failed to locate flutter_rust_net package root from ${Directory.current.path}',
      );
    }
    current = parent;
  }
}

Directory _resolveOutputDir(Directory packageRoot, String rawPath) {
  final path = rawPath.trim();
  if (path.isEmpty) {
    throw ArgumentError('output dir cannot be empty');
  }
  final directory = Directory(path);
  if (directory.isAbsolute) {
    return directory;
  }
  return Directory('${packageRoot.path}/$path');
}

Future<String?> _readGitCommit(Directory workingDirectory) async {
  final result = await Process.run(
    'git',
    ['rev-parse', 'HEAD'],
    workingDirectory: workingDirectory.path,
    runInShell: true,
  );
  if (result.exitCode != 0) {
    return null;
  }
  final stdoutText = '${result.stdout}'.trim();
  return stdoutText.isEmpty ? null : stdoutText;
}

Future<bool?> _readGitDirty(Directory workingDirectory) async {
  final result = await Process.run(
    'git',
    ['status', '--short'],
    workingDirectory: workingDirectory.path,
    runInShell: true,
  );
  if (result.exitCode != 0) {
    return null;
  }
  return '${result.stdout}'.trim().isNotEmpty;
}

_Preset _parsePreset(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'smoke':
      return _Preset.smoke;
    case 'standard':
      return _Preset.standard;
    default:
      throw ArgumentError('invalid preset: $raw');
  }
}

int _parseInt(String raw, {required String label}) {
  final value = int.tryParse(raw);
  if (value == null) {
    throw ArgumentError('invalid int for $label: $raw');
  }
  return value;
}

bool _parseBool(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'true':
    case '1':
    case 'yes':
    case 'on':
      return true;
    case 'false':
    case '0':
    case 'no':
    case 'off':
      return false;
    default:
      throw ArgumentError('invalid bool: $raw');
  }
}

String _normalizeBaseUrl(String raw) {
  var normalized = raw.trim();
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  final uri = Uri.tryParse(normalized);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
    throw ArgumentError('invalid base url: $raw');
  }
  return normalized;
}

String _formatRunId(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  final second = value.second.toString().padLeft(2, '0');
  return '$year$month${day}_$hour$minute$second';
}

String _formatDay(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year$month$day';
}

String _formatCommand(String executable, List<String> arguments) {
  return ([executable, ...arguments]).map(_shellEscape).join(' ');
}

List<String> _redactSensitiveArguments(List<String> arguments) {
  return arguments
      .map((argument) {
        if (argument.startsWith('--upload-header=')) {
          return '--upload-header=<redacted>';
        }
        if (argument.startsWith('--header=')) {
          final payload = argument.substring('--header='.length);
          final colonIndex = payload.indexOf(':');
          if (colonIndex > 0) {
            final headerName = payload.substring(0, colonIndex);
            return '--header=$headerName:<redacted>';
          }
          return '--header=<redacted>';
        }
        if (argument.contains(':') &&
            !argument.startsWith('--') &&
            !_looksLikePath(argument)) {
          final colonIndex = argument.indexOf(':');
          final headerName = argument.substring(0, colonIndex);
          if (_looksLikeHeaderName(headerName)) {
            return '$headerName:<redacted>';
          }
        }
        return argument;
      })
      .toList(growable: false);
}

bool _looksLikePath(String value) {
  return value.length >= 2 && RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value);
}

bool _looksLikeHeaderName(String value) {
  return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);
}

String _shellEscape(String value) {
  if (value.isEmpty) {
    return '""';
  }
  if (!value.contains(' ') && !value.contains('"')) {
    return value;
  }
  final escaped = value.replaceAll('"', r'\"');
  return '"$escaped"';
}

void _printUsage() {
  stdout.writeln('''
p1_non_loopback_bench.dart - fixed public-remote benchmark runner for P1 evidence

Usage:
  dart run tool/p1_non_loopback_bench.dart [options]

Options:
  --preset=smoke|standard         default: standard
  --base-url=http://47.110.52.208:7777
  --output-dir=build/remote_public_<runId>
  --run-id=20260313_161700
  --rust-max-in-flight=32
  --network-profile=ethernet
  --device=host_windows
  --link-type=public_remote
  --operator=<name>               optional trace field for archive metadata
  --commit=<sha>                  optional override, default reads git rev-parse HEAD
  --upload=true|false             default: false
  --upload-endpoint=/upload
  --upload-header=token:<token>   repeatable, only used when --upload=true

Preset behavior:
  smoke:
    - small_json dio        requests=20 warmup=2 concurrency=4
    - small_json rust       requests=20 warmup=2 concurrency=4
    - jitter_latency        requests=80 warmup=8 concurrency=8
  standard:
    - small_json dio        requests=40 warmup=4 concurrency=8
    - small_json rust       requests=40 warmup=4 concurrency=8
    - jitter_latency        requests=240 warmup=24 concurrency=16

Outputs:
  - benchmark JSON files under output dir
  - aggregate_small_json.(md|json)
  - aggregate_jitter_latency.(md|json)
  - logs/*.stdout.log and logs/*.stderr.log
  - run_manifest.json

Examples:
  dart run tool/p1_non_loopback_bench.dart --preset=smoke
  dart run tool/p1_non_loopback_bench.dart --preset=standard --network-profile=wifi --device=android_real
  dart run tool/p1_non_loopback_bench.dart --upload=true --upload-header=token:<actual-token>
''');
}
