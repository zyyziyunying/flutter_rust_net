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

class NetRequest {
  final String method;
  final String url;
  final Map<String, String> headers;
  final Map<String, dynamic> queryParameters;
  final Object? body;
  final bool expectLargeResponse;
  final bool isJitterSensitive;
  final bool isTransferTask;
  final int? contentLengthHint;
  final NetChannel? forceChannel;

  const NetRequest({
    required this.method,
    required this.url,
    this.headers = const {},
    this.queryParameters = const {},
    this.body,
    this.expectLargeResponse = false,
    this.isJitterSensitive = false,
    this.isTransferTask = false,
    this.contentLengthHint,
    this.forceChannel,
  });

  NetRequest copyWith({
    String? method,
    String? url,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    Object? body,
    bool? expectLargeResponse,
    bool? isJitterSensitive,
    bool? isTransferTask,
    int? contentLengthHint,
    NetChannel? forceChannel,
    bool clearForceChannel = false,
  }) {
    return NetRequest(
      method: method ?? this.method,
      url: url ?? this.url,
      headers: headers ?? this.headers,
      queryParameters: queryParameters ?? this.queryParameters,
      body: body ?? this.body,
      expectLargeResponse: expectLargeResponse ?? this.expectLargeResponse,
      isJitterSensitive: isJitterSensitive ?? this.isJitterSensitive,
      isTransferTask: isTransferTask ?? this.isTransferTask,
      contentLengthHint: contentLengthHint ?? this.contentLengthHint,
      forceChannel: clearForceChannel
          ? null
          : (forceChannel ?? this.forceChannel),
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

  NetTransferTaskRequest copyWith({
    String? taskId,
    NetTransferKind? kind,
    String? url,
    String? method,
    Map<String, String>? headers,
    String? localPath,
    int? resumeFrom,
    int? expectedTotal,
    int? priority,
    NetChannel? forceChannel,
    bool clearForceChannel = false,
  }) {
    return NetTransferTaskRequest(
      taskId: taskId ?? this.taskId,
      kind: kind ?? this.kind,
      url: url ?? this.url,
      method: method ?? this.method,
      headers: headers ?? this.headers,
      localPath: localPath ?? this.localPath,
      resumeFrom: resumeFrom ?? this.resumeFrom,
      expectedTotal: expectedTotal ?? this.expectedTotal,
      priority: priority ?? this.priority,
      forceChannel: clearForceChannel
          ? null
          : (forceChannel ?? this.forceChannel),
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
    this.bodyBytes,
    this.bodyFilePath,
    this.requestId,
    this.routeReason,
    this.fallbackReason,
    this.fallbackError,
  });

  NetResponse copyWith({
    int? statusCode,
    Map<String, String>? headers,
    List<int>? bodyBytes,
    String? bodyFilePath,
    int? bridgeBytes,
    NetChannel? channel,
    bool? fromFallback,
    int? costMs,
    String? requestId,
    String? routeReason,
    String? fallbackReason,
    NetException? fallbackError,
  }) {
    return NetResponse(
      statusCode: statusCode ?? this.statusCode,
      headers: headers ?? this.headers,
      bodyBytes: bodyBytes ?? this.bodyBytes,
      bodyFilePath: bodyFilePath ?? this.bodyFilePath,
      bridgeBytes: bridgeBytes ?? this.bridgeBytes,
      channel: channel ?? this.channel,
      fromFallback: fromFallback ?? this.fromFallback,
      costMs: costMs ?? this.costMs,
      requestId: requestId ?? this.requestId,
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
