import 'dart:io';

import 'package:common/log_upload.dart';

const String _defaultBaseUrl = 'http://47.110.52.208:7777';
const String _defaultEndpoint = '/upload';
const Set<String> _defaultExtensions = {'json', 'log', 'txt'};

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  try {
    final options = _parseOptions(args);
    final files = _collectFiles(options);
    if (files.isEmpty) {
      throw ArgumentError('no matched files found for ${options.inputPath}');
    }

    stdout.writeln(
      '[log-upload] target=${options.uploadUri} files=${files.length} '
      'field=${options.fieldName}',
    );

    if (options.dryRun) {
      for (final file in files) {
        stdout.writeln('[log-upload][dry-run] ${file.path}');
      }
      stdout.writeln('[log-upload] dry run done.');
      return;
    }

    final client = LogUploadClient(
      defaults: LogUploadDefaults(
        fieldName: options.fieldName,
        timeout: Duration(milliseconds: options.timeoutMs),
        fields: options.extraFields,
        headers: options.headers,
        responsePreviewMaxLength: 180,
      ),
    );

    var success = 0;
    final failed = <String>[];
    try {
      for (final file in files) {
        try {
          final fileName = _buildRemoteFileName(file, options.remotePrefix);
          final fileContent = await file.readAsString();
          final result = await client.upload(
            uploadUri: options.uploadUri,
            fileContent: fileContent,
            fileName: fileName,
          );

          if (result.success) {
            success += 1;
            final detail = client.formatResultDetail(
              result,
              includeResponseOnSuccess: false,
            );
            stdout.writeln('[log-upload] ok ${file.path} $detail');
            continue;
          }

          failed.add(file.path);
          final detail = client.formatResultDetail(result);
          stderr.writeln('[log-upload] failed ${file.path} $detail');
        } catch (error) {
          failed.add(file.path);
          stderr.writeln('[log-upload] failed ${file.path}: $error');
        }
      }
    } finally {
      client.close();
    }

    stdout.writeln(
      '[log-upload] done success=$success failed=${failed.length} '
      'total=${files.length}',
    );
    if (failed.isNotEmpty) {
      exitCode = 1;
    }
  } catch (error) {
    stderr.writeln('[log-upload] failed: $error');
    stderr.writeln('use --help to view all options.');
    exitCode = 2;
  }
}

class _CliOptions {
  final String inputPath;
  final Uri uploadUri;
  final String fieldName;
  final Set<String> extensions;
  final bool recursive;
  final int timeoutMs;
  final bool dryRun;
  final String? remotePrefix;
  final Map<String, String> headers;
  final Map<String, String> extraFields;

  const _CliOptions({
    required this.inputPath,
    required this.uploadUri,
    required this.fieldName,
    required this.extensions,
    required this.recursive,
    required this.timeoutMs,
    required this.dryRun,
    required this.remotePrefix,
    required this.headers,
    required this.extraFields,
  });
}

_CliOptions _parseOptions(List<String> args) {
  String? inputPath;
  var baseUrl = _defaultBaseUrl;
  var endpoint = _defaultEndpoint;
  var fieldName = 'file';
  var extensions = Set<String>.from(_defaultExtensions);
  var recursive = true;
  var timeoutMs = 20000;
  var dryRun = false;
  String? remotePrefix;
  final headers = <String, String>{};
  final extraFields = <String, String>{};

  for (final arg in args) {
    if (!arg.startsWith('--')) {
      throw ArgumentError('invalid argument: $arg');
    }

    final payload = arg.substring(2);
    if (payload == 'dry-run') {
      dryRun = true;
      continue;
    }

    final splitIndex = payload.indexOf('=');
    if (splitIndex <= 0) {
      throw ArgumentError('invalid argument: $arg');
    }

    final key = payload.substring(0, splitIndex);
    final value = payload.substring(splitIndex + 1);
    switch (key) {
      case 'input':
        inputPath = value;
        break;
      case 'base-url':
        baseUrl = value;
        break;
      case 'endpoint':
        endpoint = value;
        break;
      case 'field-name':
        fieldName = value;
        break;
      case 'ext':
        extensions = value
            .split(',')
            .map((item) => item.trim().toLowerCase())
            .where((item) => item.isNotEmpty)
            .toSet();
        break;
      case 'recursive':
        recursive = _parseBool(value);
        break;
      case 'timeout-ms':
        timeoutMs = _parseInt(value);
        break;
      case 'remote-prefix':
        remotePrefix = value;
        break;
      case 'header':
        final pair = _parsePair(
          value,
          separator: ':',
          label: '--header=Key:Value',
        );
        headers[pair.key] = pair.value;
        break;
      case 'extra-field':
        final pair = _parsePair(
          value,
          separator: '=',
          label: '--extra-field=key=value',
        );
        extraFields[pair.key] = pair.value;
        break;
      default:
        throw ArgumentError('unsupported option: --$key');
    }
  }

  if (inputPath == null || inputPath.isEmpty) {
    throw ArgumentError('--input is required');
  }
  if (fieldName.trim().isEmpty) {
    throw ArgumentError('--field-name cannot be empty');
  }
  if (extensions.isEmpty) {
    throw ArgumentError('--ext cannot be empty');
  }
  if (timeoutMs <= 0) {
    throw ArgumentError('--timeout-ms must be > 0');
  }

  return _CliOptions(
    inputPath: inputPath,
    uploadUri: _resolveUploadUri(baseUrl: baseUrl, endpoint: endpoint),
    fieldName: fieldName.trim(),
    extensions: extensions,
    recursive: recursive,
    timeoutMs: timeoutMs,
    dryRun: dryRun,
    remotePrefix: remotePrefix,
    headers: headers,
    extraFields: extraFields,
  );
}

List<File> _collectFiles(_CliOptions options) {
  final type = FileSystemEntity.typeSync(options.inputPath);
  switch (type) {
    case FileSystemEntityType.notFound:
      throw ArgumentError('input path not found: ${options.inputPath}');
    case FileSystemEntityType.file:
      final file = File(options.inputPath);
      if (_isAllowedFile(file, options.extensions)) {
        return [file];
      }
      throw ArgumentError(
        'input file extension not allowed: ${file.path}, '
        'allowed=${options.extensions.join(',')}',
      );
    case FileSystemEntityType.directory:
      final dir = Directory(options.inputPath);
      final files =
          dir
              .listSync(recursive: options.recursive, followLinks: false)
              .whereType<File>()
              .where((file) => _isAllowedFile(file, options.extensions))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      return files;
    default:
      throw ArgumentError('unsupported input type: ${options.inputPath}');
  }
}

bool _isAllowedFile(File file, Set<String> extensions) {
  final name = _fileName(file.path).toLowerCase();
  final dotIndex = name.lastIndexOf('.');
  if (dotIndex <= 0 || dotIndex == name.length - 1) {
    return false;
  }
  final ext = name.substring(dotIndex + 1);
  return extensions.contains(ext);
}

Uri _resolveUploadUri({required String baseUrl, required String endpoint}) {
  final normalizedBase = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
  final normalizedEndpoint = endpoint.startsWith('/')
      ? endpoint.substring(1)
      : endpoint;
  return Uri.parse(normalizedBase).resolve(normalizedEndpoint);
}

String _buildRemoteFileName(File file, String? remotePrefix) {
  final name = _fileName(file.path);
  if (remotePrefix == null || remotePrefix.trim().isEmpty) {
    return name;
  }
  final normalized = remotePrefix
      .trim()
      .replaceAll('\\', '/')
      .replaceAll(RegExp('/+'), '/')
      .replaceAll(RegExp(r'^/+'), '')
      .replaceAll(RegExp(r'/+$'), '');
  if (normalized.isEmpty) {
    return name;
  }
  return '$normalized/$name';
}

String _fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slashIndex = normalized.lastIndexOf('/');
  if (slashIndex < 0 || slashIndex == normalized.length - 1) {
    return normalized;
  }
  return normalized.substring(slashIndex + 1);
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

int _parseInt(String raw) {
  final value = int.tryParse(raw.trim());
  if (value == null) {
    throw ArgumentError('invalid int: $raw');
  }
  return value;
}

MapEntry<String, String> _parsePair(
  String raw, {
  required String separator,
  required String label,
}) {
  final splitIndex = raw.indexOf(separator);
  if (splitIndex <= 0 || splitIndex == raw.length - 1) {
    throw ArgumentError('invalid pair format, expected $label');
  }
  final key = raw.substring(0, splitIndex).trim();
  final value = raw.substring(splitIndex + 1).trim();
  if (key.isEmpty || value.isEmpty) {
    throw ArgumentError('invalid pair format, expected $label');
  }
  return MapEntry(key, value);
}

void _printUsage() {
  stdout.writeln('''
upload_bench_log.dart - upload local benchmark/report files to remote endpoint

Usage:
  dart run tool/upload_bench_log.dart --input=<path> [options]

Required:
  --input=<file_or_dir>           file or directory that stores logs/reports

Remote target:
  --base-url=http://47.110.52.208:7777
  --endpoint=/upload
  --field-name=file               multipart field name for uploaded file
  --header=Key:Value              optional, can be repeated

File filter:
  --ext=json,log,txt              allowed extensions (comma-separated)
  --recursive=true|false          default: true (for directory input)

Metadata:
  --extra-field=key=value         optional form field, can be repeated
  --remote-prefix=<path>          prefix added to uploaded filename

Runtime:
  --timeout-ms=20000
  --dry-run                       print matched files only, no network request

Examples:
  dart run tool/upload_bench_log.dart --input=build/bench_jitter.json
  dart run tool/upload_bench_log.dart --input=build/p1_jitter/20260225_1448 --ext=json --extra-field=project=flutter_rust_net --extra-field=run_id=TR-20260228-XX
  dart run tool/upload_bench_log.dart --input=build --ext=json --header=Authorization:Bearer <token>
''');
}
