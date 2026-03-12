part of 'package:flutter_rust_net/network/rust_adapter.dart';

class _RustAdapterInitTracker {
  static const String _defaultCacheSubDir = 'harrypet_net_engine_cache';
  static final Object _sharedBridgeConfigScope = Object();
  static final Expando<_RustEngineInitState> _trackedInitStates =
      Expando<_RustEngineInitState>('rust_engine_init_states');

  static bool isActiveGeneration(
    RustBridgeApi bridgeApi, {
    required int? generation,
  }) {
    if (generation == null) {
      return false;
    }
    final initState = _initStateFor(bridgeApi);
    return initState.initialized && initState.generation == generation;
  }

  static Future<int> initialize({
    required RustBridgeApi bridgeApi,
    required bool alreadyInitialized,
    required RustEngineInitOptions options,
  }) {
    final config = toNetEngineConfig(options);
    final initState = _initStateFor(bridgeApi);
    return _serializeLifecycle<int>(initState, () async {
      if (alreadyInitialized && initState.initialized) {
        _ensureInitConfigMatches(bridgeApi, requested: config);
        return initState.generation;
      }

      if (initState.initialized) {
        _ensureInitConfigMatches(bridgeApi, requested: config);
        return initState.generation;
      }

      initState.pendingConfig = config;
      try {
        await bridgeApi.ensureBridgeLoaded();
        await bridgeApi.initNetEngine(config: config);
        _rememberInitConfig(bridgeApi, config);
        initState.initialized = true;
        return initState.generation;
      } catch (error, stackTrace) {
        final text = '$error';
        if (text.contains('already initialized')) {
          _acceptAlreadyInitializedConfig(
            bridgeApi,
            requested: config,
            cause: error,
          );
          initState.initialized = true;
          return initState.generation;
        }
        final initError = _RustAdapterErrors.wrapInitError(error, text);
        Error.throwWithStackTrace(initError, stackTrace);
      } finally {
        if (initState.pendingConfig == config) {
          initState.pendingConfig = null;
        }
      }
    });
  }

  static Future<void> shutdown({
    required RustBridgeApi bridgeApi,
    required int generation,
  }) {
    final initState = _initStateFor(bridgeApi);
    return _serializeLifecycle<void>(initState, () async {
      if (!initState.initialized || initState.generation != generation) {
        return;
      }

      final completer = Completer<void>();
      initState.shutdownInFlight = completer.future;
      unawaited(completer.future.catchError((_) {}));

      try {
        await bridgeApi.ensureBridgeLoaded();
        await bridgeApi.shutdownNetEngine();
        initState.knownConfig = null;
        initState.acceptedConfigWhenActualUnknown = null;
        initState.pendingConfig = null;
        initState.initialized = false;
        initState.generation += 1;
        completer.complete();
      } catch (error, stackTrace) {
        final shutdownError = _RustAdapterErrors.wrapShutdownError(error);
        completer.completeError(shutdownError, stackTrace);
        Error.throwWithStackTrace(shutdownError, stackTrace);
      } finally {
        if (identical(initState.shutdownInFlight, completer.future)) {
          initState.shutdownInFlight = null;
        }
      }
    });
  }

  static rust_api.NetEngineConfig toNetEngineConfig(
    RustEngineInitOptions options,
  ) {
    return rust_api.NetEngineConfig(
      baseUrl: options.baseUrl,
      connectTimeoutMs: options.connectTimeoutMs,
      readTimeoutMs: options.readTimeoutMs,
      writeTimeoutMs: options.writeTimeoutMs,
      maxConnections: options.maxConnections,
      maxConnectionsPerHost: options.maxConnectionsPerHost,
      maxInFlightTasks: options.maxInFlightTasks,
      largeBodyThresholdKb: options.largeBodyThresholdKb,
      cacheDir: options.cacheDir ?? _defaultCacheDirPath(),
      cacheDefaultTtlSeconds: options.cacheDefaultTtlSeconds,
      cacheMaxNamespaceBytes: options.cacheMaxNamespaceBytes,
      userAgent: options.userAgent,
    );
  }

  static void _rememberInitConfig(
    RustBridgeApi bridgeApi,
    rust_api.NetEngineConfig config,
  ) {
    final initState = _initStateFor(bridgeApi);
    initState.knownConfig = config;
    initState.acceptedConfigWhenActualUnknown = null;
  }

  static void _acceptAlreadyInitializedConfig(
    RustBridgeApi bridgeApi, {
    required rust_api.NetEngineConfig requested,
    Object? cause,
  }) {
    final knownConfig = _knownInitConfigFor(bridgeApi);
    if (knownConfig != null) {
      _throwKnownInitConfigMismatch(knownConfig, requested, cause: cause);
      return;
    }

    final acceptedUnknownConfig = _acceptedInitConfigWhenActualUnknownFor(
      bridgeApi,
    );
    if (acceptedUnknownConfig != null) {
      _throwUnknownActualInitConfigMismatch(
        acceptedUnknownConfig,
        requested,
        cause: cause,
      );
      return;
    }

    _initStateFor(bridgeApi).acceptedConfigWhenActualUnknown = requested;
  }

  static void _ensureInitConfigMatches(
    RustBridgeApi bridgeApi, {
    required rust_api.NetEngineConfig requested,
    rust_api.NetEngineConfig? activeConfig,
    Object? cause,
  }) {
    final known = activeConfig ?? _knownInitConfigFor(bridgeApi);
    if (known != null) {
      _throwKnownInitConfigMismatch(known, requested, cause: cause);
      return;
    }

    final acceptedUnknownConfig = activeConfig == null
        ? _acceptedInitConfigWhenActualUnknownFor(bridgeApi)
        : null;
    if (acceptedUnknownConfig == null) {
      return;
    }

    _throwUnknownActualInitConfigMismatch(
      acceptedUnknownConfig,
      requested,
      cause: cause,
    );
  }

  static void _throwKnownInitConfigMismatch(
    rust_api.NetEngineConfig active,
    rust_api.NetEngineConfig requested, {
    Object? cause,
  }) {
    if (active == requested) {
      return;
    }

    throw NetException.infrastructure(
      message:
          'Rust engine already initialized with a different config; '
          'requested init options were ignored. Changed fields: '
          '${_describeInitConfigDiff(active, requested)}',
      channel: NetChannel.rust,
      fallbackEligible: false,
      cause: cause,
    );
  }

  static void _throwUnknownActualInitConfigMismatch(
    rust_api.NetEngineConfig acceptedRequestedConfig,
    rust_api.NetEngineConfig requested, {
    Object? cause,
  }) {
    if (acceptedRequestedConfig == requested) {
      return;
    }

    throw NetException.infrastructure(
      message:
          'Rust engine was already initialized before Dart could observe its '
          'active config; only the first accepted init options can be reused '
          'safely until Rust exposes the real config. Changed fields: '
          '${_describeInitConfigDiff(acceptedRequestedConfig, requested)}',
      channel: NetChannel.rust,
      fallbackEligible: false,
      cause: cause,
    );
  }

  static String _describeInitConfigDiff(
    rust_api.NetEngineConfig active,
    rust_api.NetEngineConfig requested,
  ) {
    final diffs = <String>[];
    void addDiff(String field, Object current, Object next) {
      if (current == next) {
        return;
      }
      diffs.add(
        '$field=${_formatInitValue(current)} -> ${_formatInitValue(next)}',
      );
    }

    addDiff('baseUrl', active.baseUrl, requested.baseUrl);
    addDiff(
      'connectTimeoutMs',
      active.connectTimeoutMs,
      requested.connectTimeoutMs,
    );
    addDiff('readTimeoutMs', active.readTimeoutMs, requested.readTimeoutMs);
    addDiff('writeTimeoutMs', active.writeTimeoutMs, requested.writeTimeoutMs);
    addDiff('maxConnections', active.maxConnections, requested.maxConnections);
    addDiff(
      'maxConnectionsPerHost',
      active.maxConnectionsPerHost,
      requested.maxConnectionsPerHost,
    );
    addDiff(
      'maxInFlightTasks',
      active.maxInFlightTasks,
      requested.maxInFlightTasks,
    );
    addDiff(
      'largeBodyThresholdKb',
      active.largeBodyThresholdKb,
      requested.largeBodyThresholdKb,
    );
    addDiff('cacheDir', active.cacheDir, requested.cacheDir);
    addDiff(
      'cacheDefaultTtlSeconds',
      active.cacheDefaultTtlSeconds,
      requested.cacheDefaultTtlSeconds,
    );
    addDiff(
      'cacheMaxNamespaceBytes',
      active.cacheMaxNamespaceBytes,
      requested.cacheMaxNamespaceBytes,
    );
    addDiff('userAgent', active.userAgent, requested.userAgent);

    return diffs.join(', ');
  }

  static String _formatInitValue(Object value) {
    if (value is String) {
      return '"$value"';
    }
    return '$value';
  }

  static rust_api.NetEngineConfig? _knownInitConfigFor(
    RustBridgeApi bridgeApi,
  ) {
    return _initStateFor(bridgeApi).knownConfig;
  }

  static rust_api.NetEngineConfig? _acceptedInitConfigWhenActualUnknownFor(
    RustBridgeApi bridgeApi,
  ) {
    return _initStateFor(bridgeApi).acceptedConfigWhenActualUnknown;
  }

  static _RustEngineInitState _initStateFor(RustBridgeApi bridgeApi) {
    final scope = _initConfigScopeFor(bridgeApi);
    final existing = _trackedInitStates[scope];
    if (existing != null) {
      return existing;
    }
    final created = _RustEngineInitState();
    _trackedInitStates[scope] = created;
    return created;
  }

  static Object _initConfigScopeFor(RustBridgeApi bridgeApi) {
    return bridgeApi is FrbRustBridgeApi ? _sharedBridgeConfigScope : bridgeApi;
  }

  static Future<T> _serializeLifecycle<T>(
    _RustEngineInitState initState,
    Future<T> Function() action,
  ) async {
    final previousLifecycle = initState.lifecycleInFlight;
    final completer = Completer<void>();
    initState.lifecycleInFlight = completer.future;
    unawaited(completer.future.catchError((_) {}));

    try {
      await previousLifecycle.catchError((_) {});
      return await action();
    } finally {
      completer.complete();
    }
  }

  static String _defaultCacheDirPath() {
    final tempPath = Directory.systemTemp.path;
    final separator = Platform.pathSeparator;
    if (tempPath.endsWith(separator)) {
      return '$tempPath$_defaultCacheSubDir';
    }
    return '$tempPath$separator$_defaultCacheSubDir';
  }
}

class _RustEngineInitState {
  int generation = 0;
  bool initialized = false;
  rust_api.NetEngineConfig? knownConfig;
  rust_api.NetEngineConfig? acceptedConfigWhenActualUnknown;
  rust_api.NetEngineConfig? pendingConfig;
  Future<void> lifecycleInFlight = Future<void>.value();
  Future<void>? shutdownInFlight;
}
