import 'dart:io';

Directory resolvePackageRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final pubspec = File(
      '${current.path}${Platform.pathSeparator}pubspec.yaml',
    );
    if (pubspec.existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError(
        'Could not locate package root from ${Directory.current.path}',
      );
    }
    current = parent;
  }
}

Future<void> runCommand({
  required String executable,
  required List<String> arguments,
  required Directory workingDirectory,
  String? notFoundHint,
}) async {
  late final Process process;
  try {
    process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory.path,
      runInShell: true,
    );
  } on ProcessException catch (error) {
    final suffix = notFoundHint == null ? '' : '\n$notFoundHint';
    throw StateError('Failed to start `$executable`: $error$suffix');
  }

  await Future.wait([
    stdout.addStream(process.stdout),
    stderr.addStream(process.stderr),
  ]);

  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw StateError(
      '`$executable ${arguments.join(' ')}` failed with exit code $exitCode',
    );
  }
}
