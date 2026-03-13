import 'dart:io';

import '_rust_tool_utils.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  try {
    final options = _parseOptions(args);
    final packageRoot = resolvePackageRoot();
    final rustRoot = Directory(
      '${packageRoot.path}${Platform.pathSeparator}native'
      '${Platform.pathSeparator}rust'
      '${Platform.pathSeparator}net_engine',
    );
    if (!rustRoot.existsSync()) {
      throw StateError('Missing Rust crate: ${rustRoot.path}');
    }

    if (options.build) {
      final buildArgs = <String>['build', '-p', 'net_engine'];
      if (options.profile == 'release') {
        buildArgs.add('--release');
      }
      stdout.writeln('[rust-build] cargo ${buildArgs.join(' ')}');
      await runCommand(
        executable: 'cargo',
        arguments: buildArgs,
        workingDirectory: rustRoot,
      );
    }

    if (options.fmtCheck) {
      stdout.writeln('[rust-build] cargo fmt --check');
      await runCommand(
        executable: 'cargo',
        arguments: const ['fmt', '--check'],
        workingDirectory: rustRoot,
      );
    }

    if (options.test) {
      stdout.writeln('[rust-build] cargo test -q');
      await runCommand(
        executable: 'cargo',
        arguments: const ['test', '-q'],
        workingDirectory: rustRoot,
      );
    }
  } catch (error) {
    stderr.writeln('[rust-build] failed: $error');
    stderr.writeln('use --help to view all options.');
    exitCode = 2;
  }
}

class _CliOptions {
  final String profile;
  final bool build;
  final bool fmtCheck;
  final bool test;

  const _CliOptions({
    required this.profile,
    required this.build,
    required this.fmtCheck,
    required this.test,
  });
}

_CliOptions _parseOptions(List<String> args) {
  var profile = 'release';
  var build = true;
  var fmtCheck = false;
  var test = false;

  for (final arg in args) {
    if (!arg.startsWith('--')) {
      throw ArgumentError('unsupported option: $arg');
    }
    if (arg == '--help' || arg == '-h') {
      continue;
    }
    final splitIndex = arg.indexOf('=');
    if (splitIndex <= 2) {
      throw ArgumentError('unsupported option: $arg');
    }
    final key = arg.substring(2, splitIndex);
    final value = arg.substring(splitIndex + 1);
    switch (key) {
      case 'profile':
        final normalized = value.trim().toLowerCase();
        if (normalized != 'debug' && normalized != 'release') {
          throw ArgumentError('invalid profile: $value');
        }
        profile = normalized;
        break;
      case 'build':
        build = _parseBool(value);
        break;
      case 'fmt-check':
        fmtCheck = _parseBool(value);
        break;
      case 'test':
        test = _parseBool(value);
        break;
      default:
        throw ArgumentError('unsupported option: --$key');
    }
  }

  return _CliOptions(
    profile: profile,
    build: build,
    fmtCheck: fmtCheck,
    test: test,
  );
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

void _printUsage() {
  stdout.writeln('''
rust_build.dart - build and validate the package-local net_engine crate

Usage:
  dart run tool/rust_build.dart [options]

Options:
  --profile=release|debug        build profile, default: release
  --build=true|false             run cargo build, default: true
  --fmt-check=true|false         run cargo fmt --check, default: false
  --test=true|false              run cargo test -q, default: false

Examples:
  dart run tool/rust_build.dart
  dart run tool/rust_build.dart --profile=debug
  dart run tool/rust_build.dart --build=false --fmt-check=true --test=true
''');
}
