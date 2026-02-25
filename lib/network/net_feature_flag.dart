class NetFeatureFlag {
  final bool enableRustChannel;
  final bool enableFallback;
  final int rustBodyThresholdBytes;
  final Set<String> rustPathAllowList;
  final Set<String> dioPathDenyList;

  const NetFeatureFlag({
    this.enableRustChannel = false,
    this.enableFallback = true,
    this.rustBodyThresholdBytes = 1024 * 1024,
    this.rustPathAllowList = const {},
    this.dioPathDenyList = const {},
  });

  bool isRustAllowListMatch(Uri uri) {
    return _isPathMatched(uri: uri, patterns: rustPathAllowList);
  }

  bool isDioDenyListMatch(Uri uri) {
    return _isPathMatched(uri: uri, patterns: dioPathDenyList);
  }

  bool _isPathMatched({required Uri uri, required Set<String> patterns}) {
    if (patterns.isEmpty) {
      return false;
    }

    final path = uri.path.isEmpty ? '/' : uri.path;
    for (final pattern in patterns) {
      if (pattern.endsWith('*')) {
        final prefix = pattern.substring(0, pattern.length - 1);
        if (path.startsWith(prefix)) {
          return true;
        }
        continue;
      }

      if (path == pattern) {
        return true;
      }
    }

    return false;
  }
}
