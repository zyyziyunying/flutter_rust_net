part of 'package:flutter_rust_net/network/rust_adapter.dart';

class _RustAdapterCodec {
  static int _requestCounter = 0;

  static rust_api.RequestSpec toRustRequestSpec(NetRequest request) {
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
      query: mergedQuery.entries
          .map((entry) => (entry.key, entry.value))
          .toList(),
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
      priority: 1,
    );
  }

  static rust_api.TransferTaskSpec toRustTransferTaskSpec(
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
      resumeFrom: request.resumeFrom == null
          ? null
          : BigInt.from(request.resumeFrom!),
      expectedTotal: request.expectedTotal == null
          ? null
          : BigInt.from(request.expectedTotal!),
      priority: request.priority,
    );
  }

  static NetResponse toNetResponse(
    rust_api.ResponseMeta response, {
    required bool fromFallback,
  }) {
    final error = response.error;
    if (error != null && error.isNotEmpty) {
      throw _RustAdapterErrors.mapRustError(
        error,
        kind: response.errorKind,
        statusCode: response.statusCode,
        requestId: response.requestId,
      );
    }

    final headers = <String, String>{};
    for (final header in response.headers) {
      final previous = headers[header.$1];
      headers[header.$1] = previous == null
          ? header.$2
          : '$previous,${header.$2}';
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

  static NetTransferEvent toNetTransferEvent(rust_api.NetEvent event) {
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

  static NetTransferEventKind _toNetTransferEventKind(
    rust_api.NetEventKind kind,
  ) {
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

  static String _nextRequestId() {
    _requestCounter += 1;
    return 'frb_${DateTime.now().microsecondsSinceEpoch}_$_requestCounter';
  }
}
