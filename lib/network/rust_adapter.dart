import 'dart:async';
import 'dart:io';

import '../rust_bridge/api.dart' as rust_api;
import 'net_adapter.dart';
import 'net_models.dart';
import 'request_body_codec.dart';
import 'rust_bridge_api.dart';

part 'rust_adapter/rust_adapter_codec.dart';
part 'rust_adapter/rust_adapter_errors.dart';
part 'rust_adapter/rust_adapter_init.dart';

typedef RustRequestHandler = Future<NetResponse> Function(NetRequest request);

class RustEngineInitOptions {
  final String baseUrl;
  final int connectTimeoutMs;
  final int readTimeoutMs;
  final int writeTimeoutMs;
  final int maxConnections;
  final int maxConnectionsPerHost;
  final int maxInFlightTasks;
  final int largeBodyThresholdKb;
  final String? cacheDir;
  final int cacheDefaultTtlSeconds;
  final int cacheMaxNamespaceBytes;
  final String userAgent;

  const RustEngineInitOptions({
    this.baseUrl = '',
    this.connectTimeoutMs = 10000,
    this.readTimeoutMs = 30000,
    this.writeTimeoutMs = 30000,
    this.maxConnections = 100,
    this.maxConnectionsPerHost = 6,
    this.maxInFlightTasks = 32,
    this.largeBodyThresholdKb = 256,
    this.cacheDir,
    this.cacheDefaultTtlSeconds = 300,
    this.cacheMaxNamespaceBytes = 64 * 1024 * 1024,
    this.userAgent = 'HarryPet/1.0',
  });
}

class RustAdapter implements NetAdapter {
  final RustRequestHandler? _requestHandler;
  final RustBridgeApi _bridgeApi;
  bool _initialized;

  RustAdapter({
    bool initialized = false,
    RustRequestHandler? requestHandler,
    RustBridgeApi? bridgeApi,
  }) : _initialized = initialized,
       _requestHandler = requestHandler,
       _bridgeApi = bridgeApi ?? FrbRustBridgeApi();

  @override
  bool get isReady => _initialized;

  bool get isInitialized => _initialized;

  void markInitialized([bool value = true]) {
    _initialized = value;
  }

  Future<void> initializeEngine({
    RustEngineInitOptions options = const RustEngineInitOptions(),
  }) async {
    if (_requestHandler != null) {
      _initialized = true;
      return;
    }

    await _RustAdapterInitTracker.initialize(
      bridgeApi: _bridgeApi,
      alreadyInitialized: _initialized,
      options: options,
    );
    _initialized = true;
  }

  @override
  Future<NetResponse> request(
    NetRequest request, {
    bool fromFallback = false,
  }) async {
    _ensureInitialized();

    final handler = _requestHandler;
    if (handler != null) {
      return handler(request);
    }

    rust_api.RequestSpec? spec;
    try {
      spec = _RustAdapterCodec.toRustRequestSpec(request);
      await _bridgeApi.ensureBridgeLoaded();
      final response = await _bridgeApi.request(spec: spec);
      return _RustAdapterCodec.toNetResponse(
        response,
        fromFallback: fromFallback,
      );
    } catch (error) {
      if (error is NetException) {
        rethrow;
      }
      throw _RustAdapterErrors.mapRustException(
        error,
        requestId: spec?.requestId,
      );
    }
  }

  @override
  Future<String> startTransferTask(NetTransferTaskRequest request) async {
    _ensureInitialized();

    try {
      await _bridgeApi.ensureBridgeLoaded();
      return _bridgeApi.startTransferTask(
        spec: _RustAdapterCodec.toRustTransferTaskSpec(request),
      );
    } catch (error) {
      if (error is NetException) {
        rethrow;
      }
      throw _RustAdapterErrors.mapRustException(error);
    }
  }

  @override
  Future<List<NetTransferEvent>> pollTransferEvents({int limit = 64}) async {
    _ensureInitialized();
    final safeLimit = limit <= 0 ? 1 : limit;

    try {
      await _bridgeApi.ensureBridgeLoaded();
      final events = await _bridgeApi.pollEvents(limit: safeLimit);
      return events
          .map(_RustAdapterCodec.toNetTransferEvent)
          .toList(growable: false);
    } catch (error) {
      if (error is NetException) {
        rethrow;
      }
      throw _RustAdapterErrors.mapRustException(error);
    }
  }

  @override
  Future<bool> cancelTransferTask(String taskId) async {
    _ensureInitialized();

    try {
      await _bridgeApi.ensureBridgeLoaded();
      return _bridgeApi.cancel(id: taskId);
    } catch (error) {
      if (error is NetException) {
        rethrow;
      }
      throw _RustAdapterErrors.mapRustException(error);
    }
  }

  Future<int> clearCache({String? namespace}) async {
    _ensureInitialized();

    try {
      await _bridgeApi.ensureBridgeLoaded();
      return _bridgeApi.clearCache(namespace: namespace);
    } catch (error) {
      if (error is NetException) {
        rethrow;
      }
      throw _RustAdapterErrors.mapRustException(error);
    }
  }

  void _ensureInitialized() {
    if (_initialized) {
      return;
    }
    throw NetException.infrastructure(
      message: 'Rust engine not initialized, call init_net_engine first',
      channel: NetChannel.rust,
    );
  }
}
