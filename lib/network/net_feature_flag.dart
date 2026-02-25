class NetFeatureFlag {
  final bool enableRustChannel;
  final bool enableFallback;

  const NetFeatureFlag({
    this.enableRustChannel = true,
    this.enableFallback = true,
  });
}
