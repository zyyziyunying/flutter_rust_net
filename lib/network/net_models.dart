enum NetHttpMethod {
  get('GET'),
  post('POST'),
  put('PUT'),
  patch('PATCH'),
  delete('DELETE'),
  head('HEAD'),
  options('OPTIONS'),
  trace('TRACE');

  const NetHttpMethod(this.wireName);

  final String wireName;

  static NetHttpMethod? tryParse(String value) {
    final normalized = value.trim().toUpperCase();
    for (final method in values) {
      if (method.wireName == normalized) {
        return method;
      }
    }
    return null;
  }
}

enum NetHeaderName {
  accept('accept'),
  authorization('authorization'),
  contentType('content-type'),
  contentLength('content-length'),
  userAgent('user-agent'),
  idempotencyKey('idempotency-key');

  const NetHeaderName(this.wireName);

  final String wireName;
}

enum NetChannel { dio, rust }

enum NetErrorCode {
  timeout,
  dns,
  tls,
  http4xx,
  http5xx,
  canceled,
  parse,
  io,
  infrastructure,
  internal,
}

/// Unified request model for gateway-driven network calls.
///
/// Channel routing currently only considers [forceChannel] plus the gateway's
/// feature flag state. [expectLargeResponse] is a Rust transport hint and does
/// not affect routing.
class NetRequest {
  final String method;
  final String url;
  final Map<String, String> headers;
  final Map<String, dynamic> queryParameters;

  /// UTF-8 text or JSON-encodable payload. Use [bodyBytes] for raw bytes.
  final Object? body;

  /// Raw request payload bytes. Use [body] for text or JSON payloads.
  final List<int>? bodyBytes;

  /// Rust transport hint only.
  ///
  /// When this request executes on the Rust channel, the Rust engine prefers
  /// file-backed response storage for large bodies. It does not affect routing.
  final bool expectLargeResponse;

  /// Explicit per-request routing override.
  ///
  /// This is the only request field currently consulted by the routing policy.
  final NetChannel? forceChannel;

  const NetRequest({
    required this.method,
    required this.url,
    this.headers = const {},
    this.queryParameters = const {},
    this.body,
    this.bodyBytes,
    this.expectLargeResponse = false,
    this.forceChannel,
  }) : assert(
         body == null || bodyBytes == null,
         'NetRequest.body and NetRequest.bodyBytes cannot both be set.',
       );

  NetHttpMethod? get httpMethod => NetHttpMethod.tryParse(method);

  NetRequest withForceChannel(NetChannel? forceChannel) {
    return NetRequest(
      method: method,
      url: url,
      headers: headers,
      queryParameters: queryParameters,
      body: body,
      bodyBytes: bodyBytes,
      expectLargeResponse: expectLargeResponse,
      forceChannel: forceChannel,
    );
  }
}

enum NetTransferKind { download, upload }

class NetTransferTaskRequest {
  final String taskId;
  final NetTransferKind kind;
  final String url;
  final String method;
  final Map<String, String> headers;
  final String localPath;
  final int? resumeFrom;
  final int? expectedTotal;
  final int priority;
  final NetChannel? forceChannel;

  const NetTransferTaskRequest({
    required this.taskId,
    required this.kind,
    required this.url,
    required this.localPath,
    this.method = 'GET',
    this.headers = const {},
    this.resumeFrom,
    this.expectedTotal,
    this.priority = 0,
    this.forceChannel,
  });

  bool get isResumeDownload =>
      kind == NetTransferKind.download && (resumeFrom ?? 0) > 0;

  NetTransferTaskRequest withForceChannel(NetChannel? forceChannel) {
    return NetTransferTaskRequest(
      taskId: taskId,
      kind: kind,
      url: url,
      method: method,
      headers: headers,
      localPath: localPath,
      resumeFrom: resumeFrom,
      expectedTotal: expectedTotal,
      priority: priority,
      forceChannel: forceChannel,
    );
  }
}

enum NetTransferEventKind {
  queued,
  started,
  progress,
  completed,
  failed,
  canceled,
}

class NetTransferEvent {
  final String id;
  final NetTransferEventKind kind;
  final int transferred;
  final int? total;
  final int? statusCode;
  final String? message;
  final int? costMs;
  final NetChannel channel;

  const NetTransferEvent({
    required this.id,
    required this.kind,
    required this.transferred,
    required this.channel,
    this.total,
    this.statusCode,
    this.message,
    this.costMs,
  });
}

class NetTransferTaskStartResult {
  final String taskId;
  final NetChannel channel;
  final String routeReason;
  final bool fromFallback;
  final String? fallbackReason;
  final NetException? fallbackError;

  const NetTransferTaskStartResult({
    required this.taskId,
    required this.channel,
    required this.routeReason,
    this.fromFallback = false,
    this.fallbackReason,
    this.fallbackError,
  });
}

class NetResponse {
  final int statusCode;
  final Map<String, String> headers;
  final List<int>? bodyBytes;
  final String? bodyFilePath;
  final int bridgeBytes;
  final bool fromCache;
  final NetChannel channel;
  final bool fromFallback;
  final int costMs;
  final String? requestId;
  final String? routeReason;
  final String? fallbackReason;
  final NetException? fallbackError;

  const NetResponse({
    required this.statusCode,
    required this.headers,
    required this.channel,
    required this.fromFallback,
    required this.costMs,
    this.bridgeBytes = 0,
    this.fromCache = false,
    this.bodyBytes,
    this.bodyFilePath,
    this.requestId,
    this.routeReason,
    this.fallbackReason,
    this.fallbackError,
  });

  NetResponse withMeta({
    bool? fromCache,
    NetChannel? channel,
    bool? fromFallback,
    String? routeReason,
    String? fallbackReason,
    NetException? fallbackError,
  }) {
    return NetResponse(
      statusCode: statusCode,
      headers: headers,
      bodyBytes: bodyBytes,
      bodyFilePath: bodyFilePath,
      bridgeBytes: bridgeBytes,
      fromCache: fromCache ?? this.fromCache,
      channel: channel ?? this.channel,
      fromFallback: fromFallback ?? this.fromFallback,
      costMs: costMs,
      requestId: requestId,
      routeReason: routeReason ?? this.routeReason,
      fallbackReason: fallbackReason ?? this.fallbackReason,
      fallbackError: fallbackError ?? this.fallbackError,
    );
  }
}

class NetException implements Exception {
  final NetErrorCode code;
  final String message;
  final NetChannel channel;
  final bool fallbackEligible;
  final int? statusCode;
  final String? requestId;
  final Object? cause;

  const NetException({
    required this.code,
    required this.message,
    required this.channel,
    this.fallbackEligible = false,
    this.statusCode,
    this.requestId,
    this.cause,
  });

  factory NetException.infrastructure({
    required String message,
    required NetChannel channel,
    bool fallbackEligible = true,
    String? requestId,
    Object? cause,
  }) {
    return NetException(
      code: NetErrorCode.infrastructure,
      message: message,
      channel: channel,
      fallbackEligible: fallbackEligible,
      requestId: requestId,
      cause: cause,
    );
  }

  @override
  String toString() {
    final statusSegment = statusCode == null ? '' : ' status=$statusCode';
    final requestSegment = requestId == null ? '' : ' requestId=$requestId';
    return '[${channel.name}] ${code.name}$statusSegment$requestSegment: $message';
  }
}
