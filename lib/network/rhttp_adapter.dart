import 'dart:async';
import 'dart:typed_data';

import 'package:rhttp/rhttp.dart' as rhttp;

import 'net_adapter.dart';
import 'net_models.dart';
import 'request_body_codec.dart';
import 'url_resolution.dart';

typedef RhttpClientFactory =
    Future<rhttp.RhttpClient> Function(rhttp.ClientSettings settings);
typedef RhttpAdapterRequestHandler =
    Future<RhttpAdapterResponse> Function(RhttpAdapterRequest request);

class RhttpAdapterRequest {
  final String method;
  final String url;
  final Map<String, String> headers;
  final Uint8List? bodyBytes;

  const RhttpAdapterRequest({
    required this.method,
    required this.url,
    required this.headers,
    required this.bodyBytes,
  });
}

class RhttpAdapterResponse {
  final int statusCode;
  final List<(String, String)> headers;
  final Uint8List bodyBytes;

  const RhttpAdapterResponse({
    required this.statusCode,
    required this.headers,
    required this.bodyBytes,
  });
}

class RhttpAdapter extends NetAdapter {
  static int _requestCounter = 0;
  static Future<void>? _initFuture;

  final rhttp.ClientSettings _clientSettings;
  final RhttpClientFactory? _clientFactory;
  final RhttpAdapterRequestHandler? _requestHandler;
  bool _clientReady = false;
  Future<rhttp.RhttpClient>? _clientFuture;

  RhttpAdapter({
    rhttp.ClientSettings? clientSettings,
    RhttpClientFactory? clientFactory,
    RhttpAdapterRequestHandler? requestHandler,
  }) : _clientSettings = (clientSettings ?? const rhttp.ClientSettings())
           .copyWith(throwOnStatusCode: false),
       _clientFactory = clientFactory,
       _requestHandler = requestHandler;

  @override
  bool get isReady => _requestHandler != null || _clientReady;

  Future<bool> ensureRequestReady() async {
    if (_requestHandler != null || _clientReady) {
      return true;
    }
    try {
      await _ensureClient();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<NetResponse> request(
    NetRequest request, {
    bool fromFallback = false,
  }) async {
    final resolvedRequest = resolveNetRequestUrl(request);
    final url = _buildUrl(resolvedRequest.url, resolvedRequest.queryParameters);
    final bodyBytes = encodeRequestBody(
      resolvedRequest.body,
      bodyBytes: resolvedRequest.bodyBytes,
      channel: NetChannel.rust,
    );
    final requestId = _nextRequestId();
    final watch = Stopwatch()..start();

    try {
      final handler = _requestHandler;
      if (handler != null) {
        final response = await handler(
          RhttpAdapterRequest(
            method: resolvedRequest.method,
            url: url,
            headers: Map<String, String>.unmodifiable(resolvedRequest.headers),
            bodyBytes: bodyBytes,
          ),
        );
        watch.stop();
        return NetResponse(
          statusCode: response.statusCode,
          headers: _flattenHeaders(response.headers),
          bodyBytes: response.bodyBytes,
          bodyFilePath: null,
          bridgeBytes: response.bodyBytes.length,
          fromCache: false,
          channel: NetChannel.rust,
          fromFallback: fromFallback,
          costMs: watch.elapsedMilliseconds,
          requestId: requestId,
        );
      }

      final client = await _ensureClient();
      final response = await client.requestBytes(
        method: rhttp.HttpMethod(resolvedRequest.method),
        url: url,
        headers: _toHeaders(resolvedRequest.headers),
        body: bodyBytes == null ? null : rhttp.HttpBody.bytes(bodyBytes),
      );
      watch.stop();
      return NetResponse(
        statusCode: response.statusCode,
        headers: _flattenHeaders(response.headers),
        bodyBytes: response.body,
        bodyFilePath: null,
        bridgeBytes: response.body.length,
        fromCache: false,
        channel: NetChannel.rust,
        fromFallback: fromFallback,
        costMs: watch.elapsedMilliseconds,
        requestId: requestId,
      );
    } on NetException {
      watch.stop();
      rethrow;
    } on rhttp.RhttpException catch (error) {
      watch.stop();
      throw _mapRhttpException(error, requestId: requestId);
    } catch (error) {
      watch.stop();
      throw NetException.infrastructure(
        message: 'rhttp request failed: $error',
        channel: NetChannel.rust,
        requestId: requestId,
        cause: error,
      );
    }
  }

  Future<rhttp.RhttpClient> _ensureClient() async {
    final future = _clientFuture ??= _createClient();
    try {
      final client = await future;
      _clientReady = true;
      return client;
    } catch (_) {
      if (identical(_clientFuture, future)) {
        _clientFuture = null;
      }
      _clientReady = false;
      rethrow;
    }
  }

  Future<rhttp.RhttpClient> _createClient() async {
    await _ensureInitialized();
    final factory = _clientFactory;
    if (factory != null) {
      return factory(_clientSettings);
    }
    return rhttp.RhttpClient.create(settings: _clientSettings);
  }

  static Future<void> _ensureInitialized() async {
    final future = _initFuture ??= rhttp.Rhttp.init();
    try {
      await future;
    } catch (_) {
      if (identical(_initFuture, future)) {
        _initFuture = null;
      }
      rethrow;
    }
  }

  String _buildUrl(String url, Map<String, dynamic> extraQueryParameters) {
    final uri = Uri.parse(url);
    if (extraQueryParameters.isEmpty) {
      return uri.toString();
    }

    final merged = <String, String>{...uri.queryParameters};
    extraQueryParameters.forEach((key, value) {
      if (value == null) {
        return;
      }
      merged[key] = value.toString();
    });
    return uri.replace(queryParameters: merged).toString();
  }

  rhttp.HttpHeaders? _toHeaders(Map<String, String> headers) {
    if (headers.isEmpty) {
      return null;
    }
    return rhttp.HttpHeaders.rawMap(headers);
  }

  Map<String, String> _flattenHeaders(List<(String, String)> source) {
    final map = <String, String>{};
    for (final header in source) {
      final previous = map[header.$1];
      map[header.$1] = previous == null ? header.$2 : '$previous,${header.$2}';
    }
    return map;
  }

  NetException _mapRhttpException(
    rhttp.RhttpException error, {
    required String requestId,
  }) {
    if (error is rhttp.RhttpCancelException) {
      return NetException(
        code: NetErrorCode.canceled,
        message: 'request canceled',
        channel: NetChannel.rust,
        requestId: requestId,
      );
    }
    if (error is rhttp.RhttpTimeoutException) {
      return NetException(
        code: NetErrorCode.timeout,
        message: 'request timeout',
        channel: NetChannel.rust,
        fallbackEligible: true,
        requestId: requestId,
      );
    }
    if (error is rhttp.RhttpInvalidCertificateException) {
      return NetException(
        code: NetErrorCode.tls,
        message: error.message,
        channel: NetChannel.rust,
        fallbackEligible: true,
        requestId: requestId,
      );
    }
    if (error is rhttp.RhttpConnectionException) {
      return NetException(
        code: _mapConnectionErrorCode(error.message),
        message: error.message,
        channel: NetChannel.rust,
        fallbackEligible: true,
        requestId: requestId,
      );
    }
    if (error is rhttp.RhttpStatusCodeException) {
      final code = error.statusCode >= 400 && error.statusCode < 500
          ? NetErrorCode.http4xx
          : NetErrorCode.http5xx;
      return NetException(
        code: code,
        message: 'http error',
        channel: NetChannel.rust,
        statusCode: error.statusCode,
        requestId: requestId,
      );
    }
    if (error is rhttp.RhttpClientDisposedException) {
      return NetException(
        code: NetErrorCode.internal,
        message: 'rhttp client already disposed',
        channel: NetChannel.rust,
        requestId: requestId,
      );
    }
    if (error is rhttp.RhttpInterceptorException) {
      return NetException(
        code: NetErrorCode.internal,
        message: '${error.error}',
        channel: NetChannel.rust,
        requestId: requestId,
        cause: error.error,
      );
    }
    if (error is rhttp.RhttpRedirectException) {
      return NetException.infrastructure(
        message: 'redirect error',
        channel: NetChannel.rust,
        requestId: requestId,
      );
    }
    if (error is rhttp.RhttpUnknownException) {
      return NetException.infrastructure(
        message: error.message,
        channel: NetChannel.rust,
        requestId: requestId,
      );
    }

    return NetException.infrastructure(
      message: '$error',
      channel: NetChannel.rust,
      requestId: requestId,
      cause: error,
    );
  }

  NetErrorCode _mapConnectionErrorCode(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('dns') ||
        lower.contains('resolve') ||
        lower.contains('lookup')) {
      return NetErrorCode.dns;
    }
    if (lower.contains('tls') ||
        lower.contains('ssl') ||
        lower.contains('certificate')) {
      return NetErrorCode.tls;
    }
    return NetErrorCode.io;
  }

  String _nextRequestId() {
    _requestCounter += 1;
    return 'rhttp_${DateTime.now().microsecondsSinceEpoch}_$_requestCounter';
  }
}
