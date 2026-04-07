import 'dart:io';

const String _neutralEnvKey = 'RHTTP_NATIVE_LIB_DIR';
const String _legacyEnvKey = 'FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR';

String? realRhttpSkipReason({
  Map<String, String>? environment,
  bool Function(String path)? fileExists,
}) {
  final resolvedEnvironment = environment ?? Platform.environment;
  final resolvedFileExists = fileExists ?? ((path) => File(path).existsSync());
  final legacyNativeLibDir = _normalizedEnvValue(
    resolvedEnvironment[_legacyEnvKey],
  );
  final neutralNativeLibDir = _normalizedEnvValue(
    resolvedEnvironment[_neutralEnvKey],
  );

  if (legacyNativeLibDir != null) {
    final nativeLibPath = '$legacyNativeLibDir/librhttp.dylib';
    if (resolvedFileExists(nativeLibPath)) {
      return null;
    }

    return 'Missing librhttp.dylib under the configured native rhttp library '
        'directory: $legacyNativeLibDir.';
  }

  if (neutralNativeLibDir != null) {
    return '$_neutralEnvKey is set to $neutralNativeLibDir, but the current '
        'rhttp native loader still reads $_legacyEnvKey. Mirror the same '
        'directory into $_legacyEnvKey to run opt-in real-rhttp tests.';
  }

  return 'Set $_legacyEnvKey to a directory containing librhttp.dylib to run '
      'opt-in real-rhttp tests.';
}

String? _normalizedEnvValue(String? value) {
  if (value == null) {
    return null;
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}
