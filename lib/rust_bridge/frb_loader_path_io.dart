import 'dart:io';

const String _nativeProjectRelativePath = 'native/rust/net_engine';
const String _defaultFrbIoDirectory = 'native/rust/net_engine/target/release/';

String resolveFrbDefaultIoDirectory() {
  final nativeRoot = resolveNativeProjectRootPath();
  if (nativeRoot == null) {
    return _defaultFrbIoDirectory;
  }

  final releaseDirectory = Directory.fromUri(
    Directory(nativeRoot).absolute.uri.resolve('target/release/'),
  );
  return releaseDirectory.uri.toString();
}

String? resolveNativeProjectRootPath({String? currentDirectoryPath}) {
  var cursor = Directory(
    currentDirectoryPath ?? Directory.current.path,
  ).absolute;
  while (true) {
    final candidate = Directory.fromUri(
      cursor.uri.resolve('$_nativeProjectRelativePath/'),
    );
    if (candidate.existsSync()) {
      final normalized = candidate.absolute.path.replaceAll('\\', '/');
      return normalized.endsWith('/')
          ? normalized.substring(0, normalized.length - 1)
          : normalized;
    }

    final parent = cursor.parent;
    if (parent.path == cursor.path) {
      return null;
    }
    cursor = parent;
  }
}
