import 'dart:async';
import 'dart:io';

import '_rust_tool_utils.dart';

const String _generatedEntrypointRelativePath =
    'lib/rust_bridge/frb_generated.dart';
const String _generatedImportAnchor = "import 'dart:convert';";
const String _generatedHelperImport =
    "import 'frb_loader_path.dart' as frb_loader_path;";
const String _generatedLoaderConfigOriginal =
    "  static const kDefaultExternalLibraryLoaderConfig =\n"
    "      ExternalLibraryLoaderConfig(\n"
    "        stem: 'net_engine',\n"
    "        ioDirectory: 'native/rust/net_engine/target/release/',\n"
    "        webPrefix: 'pkg/',\n"
    "      );";
const String _generatedLoaderConfigPatched =
    "  static final kDefaultExternalLibraryLoaderConfig =\n"
    "      ExternalLibraryLoaderConfig(\n"
    "        stem: 'net_engine',\n"
    "        ioDirectory: frb_loader_path.resolveFrbDefaultIoDirectory(),\n"
    "        webPrefix: 'pkg/',\n"
    "      );";

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  try {
    final options = _parseOptions(args);
    final packageRoot = resolvePackageRoot();
    final configFile = File(
      '${packageRoot.path}${Platform.pathSeparator}flutter_rust_bridge.yaml',
    );
    if (!configFile.existsSync()) {
      throw StateError('Missing FRB config: ${configFile.path}');
    }

    final commandArgs = <String>[
      'generate',
      '--config-file',
      configFile.path,
      if (options.watch) '--watch',
      if (options.verbose) '--verbose',
    ];

    stdout.writeln(
      '[rust-codegen] running flutter_rust_bridge_codegen '
      '${commandArgs.join(' ')}',
    );

    if (options.watch) {
      await _runWatchCodegen(
        packageRoot: packageRoot,
        commandArgs: commandArgs,
      );
    } else {
      await runCommand(
        executable: 'flutter_rust_bridge_codegen',
        arguments: commandArgs,
        workingDirectory: packageRoot,
        notFoundHint:
            'Install flutter_rust_bridge_codegen v2.11.1 and ensure it is on PATH.',
      );
      await _postProcessGeneratedEntrypoint(packageRoot);
    }
  } catch (error) {
    stderr.writeln('[rust-codegen] failed: $error');
    stderr.writeln('use --help to view all options.');
    exitCode = 2;
  }
}

class _CliOptions {
  final bool watch;
  final bool verbose;

  const _CliOptions({required this.watch, required this.verbose});
}

_CliOptions _parseOptions(List<String> args) {
  var watch = false;
  var verbose = false;

  for (final arg in args) {
    switch (arg) {
      case '--watch':
        watch = true;
        break;
      case '--verbose':
      case '-v':
        verbose = true;
        break;
      default:
        if (arg == '--help' || arg == '-h') {
          continue;
        }
        throw ArgumentError('unsupported option: $arg');
    }
  }

  return _CliOptions(watch: watch, verbose: verbose);
}

void _printUsage() {
  stdout.writeln('''
rust_codegen.dart - regenerate flutter_rust_bridge bindings for flutter_rust_net

Usage:
  dart run tool/rust_codegen.dart [options]

Options:
  --watch                         re-generate on source changes
  --verbose, -v                  print verbose codegen logs

Config:
  Uses flutter_rust_bridge.yaml at the package root.

Examples:
  dart run tool/rust_codegen.dart
  dart run tool/rust_codegen.dart --watch
''');
}

Future<void> _runWatchCodegen({
  required Directory packageRoot,
  required List<String> commandArgs,
}) async {
  final process = await _startCodegenProcess(
    packageRoot: packageRoot,
    commandArgs: commandArgs,
  );
  final entrypointFile = _generatedEntrypointFile(packageRoot);

  Timer? debounce;
  Object? patchError;
  var patchChain = Future<void>.value();

  void schedulePatch() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 200), () {
      patchChain = patchChain.then((_) async {
        try {
          await _postProcessGeneratedEntrypoint(packageRoot);
        } catch (error) {
          patchError ??= error;
          stderr.writeln('[rust-codegen] post-process failed: $error');
        }
      });
    });
  }

  final watcher = entrypointFile.parent.watch().listen((event) {
    final normalized = event.path.replaceAll('\\', '/');
    if (normalized.endsWith('/frb_generated.dart')) {
      schedulePatch();
    }
  });

  if (entrypointFile.existsSync()) {
    await _postProcessGeneratedEntrypoint(packageRoot);
  }

  await Future.wait([
    stdout.addStream(process.stdout),
    stderr.addStream(process.stderr),
  ]);
  final exitCode = await process.exitCode;

  debounce?.cancel();
  await patchChain;
  await _postProcessGeneratedEntrypoint(packageRoot);
  await watcher.cancel();

  if (patchError != null) {
    throw StateError('generated entrypoint post-process failed: $patchError');
  }
  if (exitCode != 0) {
    throw StateError(
      '`flutter_rust_bridge_codegen ${commandArgs.join(' ')}` failed with exit code $exitCode',
    );
  }
}

Future<Process> _startCodegenProcess({
  required Directory packageRoot,
  required List<String> commandArgs,
}) async {
  try {
    return await Process.start(
      'flutter_rust_bridge_codegen',
      commandArgs,
      workingDirectory: packageRoot.path,
      runInShell: true,
    );
  } on ProcessException catch (error) {
    throw StateError(
      'Failed to start `flutter_rust_bridge_codegen`: $error\n'
      'Install flutter_rust_bridge_codegen v2.11.1 and ensure it is on PATH.',
    );
  }
}

Future<void> _postProcessGeneratedEntrypoint(Directory packageRoot) async {
  final file = _generatedEntrypointFile(packageRoot);
  if (!file.existsSync()) {
    throw StateError('Missing generated entrypoint: ${file.path}');
  }

  final original = await file.readAsString();
  var updated = original;

  if (!updated.contains(_generatedHelperImport)) {
    if (!updated.contains(_generatedImportAnchor)) {
      throw StateError(
        'Could not locate import anchor in generated entrypoint: ${file.path}',
      );
    }
    updated = updated.replaceFirst(
      _generatedImportAnchor,
      '$_generatedImportAnchor\n$_generatedHelperImport',
    );
  }

  if (updated.contains(_generatedLoaderConfigOriginal)) {
    updated = updated.replaceFirst(
      _generatedLoaderConfigOriginal,
      _generatedLoaderConfigPatched,
    );
  } else if (!updated.contains(_generatedLoaderConfigPatched)) {
    throw StateError(
      'Could not locate default loader config block in generated entrypoint: ${file.path}',
    );
  }

  if (updated == original) {
    return;
  }

  await file.writeAsString(updated);
  stdout.writeln('[rust-codegen] patched ${file.path}');
}

File _generatedEntrypointFile(Directory packageRoot) {
  return File(
    '${packageRoot.path}${Platform.pathSeparator}'
    '${_generatedEntrypointRelativePath.replaceAll('/', Platform.pathSeparator)}',
  );
}
