import 'dart:io';

import '../rust_bridge/api.dart' as rust_api;
import 'net_adapter.dart';
import 'net_models.dart';
import 'request_body_codec.dart';
import 'rust_bridge_api.dart';

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
  static const String _defaultCacheSubDir = 'harrypet_net_engine_cache';
  static const String _rustRebuildHintCommand =
      'cd ../native/rust/net_engine && cargo build --release -p net_engine';

  final RustRequestHandler? _requestHandler;
  final RustBridgeApi _bridgeApi;
  bool _initialized;

  static int _requestCounter = 0;

  RustAdapter({
    bool initialized = false,
    RustRequestHandler? requestHandler,
    RustBridgeApi? bridgeApi,
  })  : _initialized = initialized,
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
    if (_initialized) {
      return;
    }

    if (_requestHandler != null) {
      _initialized = true;
      return;
    }

    try {
      await _bridgeApi.ensureBridgeLoaded();
      await _bridgeApi.initNetEngine(
        config: rust_api.NetEngineConfig(
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
        ),
      );
      _initialized = true;
    } catch (error) {
      final text = '$error';
      if (text.contains('already initialized')) {
        _initialized = true;
        return;
      }
      if (_looksLikeStaleNativeBridge(text)) {
        throw NetException.infrastructure(
          message:
              'Rust init failed: $error. Native net_engine library may be stale; '
              'rebuild with `$_rustRebuildHintCommand`.',
          channel: NetChannel.rust,
          cause: error,
        );
      }
      throw NetException.infrastructure(
        message: 'Rust init failed: $error',
        channel: NetChannel.rust,
        cause: error,
      );
    }
  }

  @override
  Future<NetResponse> request(
    NetRequest request, {
    bool fromFallback = false,
  }) async {
    _ensureInitialized();

    if (_requestHandler != null) {
      return _requestHandler(request);
    }

    rust_api.RequestSpec? spec;
    try {
      spec = _toRustRequestSpec(request);
      await _bridgeApi.ensureBridgeLoaded();
      final response = await _bridgeApi.request(spec: spec);
      return _toNetResponse(response, fromFallback: fromFallback);
    } catch (error) {
      if (error is NetException) {
        rethrow;
      }
      throw _mapRustException(error, requestId: spec?.requestId);
    }
  }

  @override
  Future<String> startTransferTask(NetTransferTaskRequest request) async {
    _ensureInitialized();

    try {
      await _bridgeApi.ensureBridgeLoaded();
      return _bridgeApi.startTransferTask(
        spec: _toRustTransferTaskSpec(request),
      );
    } catch (error) {
      if (error is NetException) {
        rethrow;
      }
      throw _mapRustException(error);
    }
  }

  @override
  Future<List<NetTransferEvent>> pollTransferEvents({int limit = 64}) async {
    _ensureInitialized();
    final safeLimit = limit <= 0 ? 1 : limit;

    try {
      await _bridgeApi.ensureBridgeLoaded();
      final events = await _bridgeApi.pollEvents(limit: safeLimit);
      return events.map(_toNetTransferEvent).toList(growable: false);
    } catch (error) {
      if (error is NetException) {
        rethrow;
      }
      throw _mapRustException(error);
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
      throw _mapRustException(error);
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
      throw _mapRustException(error);
    }
  }

  rust_api.RequestSpec _toRustRequestSpec(NetRequest request) {
    final uri = Uri.parse(request.url);
    final path = uri.hasQuery ? request.url.split('?').first : request.url;

    final mergedQuery = <String, String>{...uri.queryParameters};
    request.queryParameters.forEach((key, value) {
      if (value == null) {
        return;
      }
      mergedQuery[key] = value.toString();
    });

    return rust_api.RequestSpec(
      requestId: _nextRequestId(),
      method: request.method,
      path: path,
      query:
          mergedQuery.entries.map((entry) => (entry.key, entry.value)).toList(),
      headers: request.headers.entries
          .map((entry) => (entry.key, entry.value))
          .toList(),
      bodyBytes: encodeRequestBody(
        request.body,
        bodyBytes: request.bodyBytes,
        channel: NetChannel.rust,
      ),
      bodyFilePath: null,
      expectLargeResponse: request.expectLargeResponse,
      saveToFilePath: null,
      priority: request.isTransferTask ? 0 : 1,
    );
  }

  rust_api.TransferTaskSpec _toRustTransferTaskSpec(
    NetTransferTaskRequest request,
  ) {
    return rust_api.TransferTaskSpec(
      taskId: request.taskId,
      kind: request.kind.name,
      url: request.url,
      method: request.method,
      headers: request.headers.entries
          .map((entry) => (entry.key, entry.value))
          .toList(),
      localPath: request.localPath,
      resumeFrom:
          request.resumeFrom == null ? null : BigInt.from(request.resumeFrom!),
      expectedTotal: request.expectedTotal == null
          ? null
          : BigInt.from(request.expectedTotal!),
      priority: request.priority,
    );
  }

  NetResponse _toNetResponse(
    rust_api.ResponseMeta response, {
    required bool fromFallback,
  }) {
    final error = response.error;
    if (error != null && error.isNotEmpty) {
      throw _mapRustError(
        error,
        kind: response.errorKind,
        statusCode: response.statusCode,
        requestId: response.requestId,
      );
    }

    final headers = <String, String>{};
    for (final header in response.headers) {
      final previous = headers[header.$1];
      headers[header.$1] =
          previous == null ? header.$2 : '$previous,${header.$2}';
    }

    return NetResponse(
      statusCode: response.statusCode,
      headers: headers,
      bodyBytes: response.bodyInline,
      bodyFilePath: response.bodyFilePath,
      bridgeBytes: response.bodyInline?.length ?? 0,
      fromCache: response.fromCache,
      channel: NetChannel.rust,
      fromFallback: fromFallback,
      costMs: response.costMs,
      requestId: response.requestId,
    );
  }

  NetTransferEvent _toNetTransferEvent(rust_api.NetEvent event) {
    return NetTransferEvent(
      id: event.id,
      kind: _toNetTransferEventKind(event.kind),
      transferred: event.transferred.toInt(),
      total: event.total?.toInt(),
      statusCode: event.statusCode,
      message: event.message,
      costMs: event.costMs,
      channel: NetChannel.rust,
    );
  }

  NetTransferEventKind _toNetTransferEventKind(rust_api.NetEventKind kind) {
    switch (kind) {
      case rust_api.NetEventKind.queued:
        return NetTransferEventKind.queued;
      case rust_api.NetEventKind.started:
        return NetTransferEventKind.started;
      case rust_api.NetEventKind.progress:
        return NetTransferEventKind.progress;
      case rust_api.NetEventKind.completed:
        return NetTransferEventKind.completed;
      case rust_api.NetEventKind.failed:
        return NetTransferEventKind.failed;
      case rust_api.NetEventKind.canceled:
        return NetTransferEventKind.canceled;
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

  NetException _mapRustException(Object error, {String? requestId}) {
    final message = '$error';
    if (message.contains('not initialized')) {
      return NetException.infrastructure(
        message: message,
        channel: NetChannel.rust,
        requestId: requestId,
      );
    }
    if (message.contains('Failed to lookup symbol') ||
        message.contains('loadExternalLibrary') ||
        message.contains('cannot open shared object file') ||
        message.contains('The specified module could not be found')) {
      return NetException.infrastructure(
        message: 'Rust bridge not available: $message',
        channel: NetChannel.rust,
        requestId: requestId,
        cause: error,
      );
    }
    return _mapRustError(message, requestId: requestId);
  }

  NetException _mapRustError(
    String message, {
    rust_api.NetErrorKind? kind,
    int? statusCode,
    String? requestId,
  }) {
    if (kind != null) {
      return _mapTypedRustError(
        kind,
        message,
        statusCode: statusCode,
        requestId: requestId,
      );
    }
    return _mapLegacyRustError(
      message,
      statusCode: statusCode,
      requestId: requestId,
    );
  }

  NetException _mapTypedRustError(
    rust_api.NetErrorKind kind,
    String message, {
    int? statusCode,
    String? requestId,
  }) {
    final parsedStatusCode =
        statusCode == null || statusCode == 0 ? null : statusCode;
    switch (kind) {
      case rust_api.NetErrorKind.timeout:
        return NetException(
          code: NetErrorCode.timeout,
          message: message,
          channel: NetChannel.rust,
          fallbackEligible: true,
          requestId: requestId,
        );
      case rust_api.NetErrorKind.dns:
        return NetException(
          code: NetErrorCode.dns,
          message: message,
          channel: NetChannel.rust,
          fallbackEligible: true,
          requestId: requestId,
        );
      case rust_api.NetErrorKind.tls:
        return NetException(
          code: NetErrorCode.tls,
          message: message,
          channel: NetChannel.rust,
          fallbackEligible: true,
          requestId: requestId,
        );
      case rust_api.NetErrorKind.http4Xx:
        return NetException(
          code: NetErrorCode.http4xx,
          message: message,
          channel: NetChannel.rust,
          statusCode: parsedStatusCode,
          fallbackEligible: false,
          requestId: requestId,
        );
      case rust_api.NetErrorKind.http5Xx:
        return NetException(
          code: NetErrorCode.http5xx,
          message: message,
          channel: NetChannel.rust,
          statusCode: parsedStatusCode,
          fallbackEligible: false,
          requestId: requestId,
        );
      case rust_api.NetErrorKind.canceled:
        return NetException(
          code: NetErrorCode.canceled,
          message: message,
          channel: NetChannel.rust,
          fallbackEligible: false,
          requestId: requestId,
        );
      case rust_api.NetErrorKind.parse:
        return NetException(
          code: NetErrorCode.parse,
          message: message,
          channel: NetChannel.rust,
          fallbackEligible: false,
          requestId: requestId,
        );
      case rust_api.NetErrorKind.io:
        return NetException(
          code: NetErrorCode.io,
          message: message,
          channel: NetChannel.rust,
          fallbackEligible: true,
          requestId: requestId,
        );
      case rust_api.NetErrorKind.internal:
        return NetException(
          code: NetErrorCode.internal,
          message: message,
          channel: NetChannel.rust,
          fallbackEligible: false,
          requestId: requestId,
        );
    }
  }

  NetException _mapLegacyRustError(
    String message, {
    int? statusCode,
    String? requestId,
  }) {
    final normalized = message.trim().toLowerCase();
    if (normalized.startsWith('timeout:')) {
      return NetException(
        code: NetErrorCode.timeout,
        message: message,
        channel: NetChannel.rust,
        fallbackEligible: true,
        requestId: requestId,
      );
    }
    if (normalized.startsWith('dns:')) {
      return NetException(
        code: NetErrorCode.dns,
        message: message,
        channel: NetChannel.rust,
        fallbackEligible: true,
        requestId: requestId,
      );
    }
    if (normalized.startsWith('tls:')) {
      return NetException(
        code: NetErrorCode.tls,
        message: message,
        channel: NetChannel.rust,
        fallbackEligible: true,
        requestId: requestId,
      );
    }
    if (normalized.startsWith('parse:')) {
      return NetException(
        code: NetErrorCode.parse,
        message: message,
        channel: NetChannel.rust,
        fallbackEligible: false,
        requestId: requestId,
      );
    }
    if (normalized.startsWith('io:')) {
      return NetException(
        code: NetErrorCode.io,
        message: message,
        channel: NetChannel.rust,
        fallbackEligible: true,
        requestId: requestId,
      );
    }
    if (normalized.startsWith('canceled:')) {
      return NetException(
        code: NetErrorCode.canceled,
        message: message,
        channel: NetChannel.rust,
        fallbackEligible: false,
        requestId: requestId,
      );
    }

    var parsedStatusCode =
        statusCode == null || statusCode == 0 ? null : statusCode;
    if (parsedStatusCode == null) {
      final match = RegExp(r'^http\s+(\d{3})[:\s]').firstMatch(normalized);
      if (match != null) {
        parsedStatusCode = int.tryParse(match.group(1)!);
      }
    }
    if (parsedStatusCode != null) {
      final code = parsedStatusCode >= 400 && parsedStatusCode < 500
          ? NetErrorCode.http4xx
          : NetErrorCode.http5xx;
      return NetException(
        code: code,
        message: message,
        channel: NetChannel.rust,
        statusCode: parsedStatusCode,
        fallbackEligible: false,
        requestId: requestId,
      );
    }

    if (normalized.contains('not initialized')) {
      return NetException.infrastructure(
        message: message,
        channel: NetChannel.rust,
        requestId: requestId,
      );
    }

    if (normalized.startsWith('internal:')) {
      return NetException(
        code: NetErrorCode.internal,
        message: message,
        channel: NetChannel.rust,
        fallbackEligible: false,
        requestId: requestId,
      );
    }

    return NetException(
      code: NetErrorCode.internal,
      message: message,
      channel: NetChannel.rust,
      fallbackEligible: false,
      requestId: requestId,
    );
  }

  static String _defaultCacheDirPath() {
    final tempPath = Directory.systemTemp.path;
    final separator = Platform.pathSeparator;
    if (tempPath.endsWith(separator)) {
      return '$tempPath$_defaultCacheSubDir';
    }
    return '$tempPath$separator$_defaultCacheSubDir';
  }

  static bool _looksLikeStaleNativeBridge(String text) {
    final lower = text.toLowerCase();
    return lower.contains('unexpectedeof') ||
        lower.contains('failed to fill whole buffer') ||
        lower.contains('content hash on dart side');
  }

  String _nextRequestId() {
    _requestCounter += 1;
    return 'frb_${DateTime.now().microsecondsSinceEpoch}_$_requestCounter';
  }
}
