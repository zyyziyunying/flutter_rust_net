part of 'package:flutter_rust_net/network/rust_adapter.dart';

class _RustAdapterCodec {
  static int _requestCounter = 0;

  static rust_api.RequestSpec toRustRequestSpec(NetRequest request) {
    final resolvedRequest = resolveNetRequestUrl(
      request,
      requireBaseUrlForRelative: false,
    );
    final uri = Uri.parse(resolvedRequest.url);
    final path = uri.hasQuery
        ? resolvedRequest.url.split('?').first
        : resolvedRequest.url;

    final mergedQuery = <String, String>{...uri.queryParameters};
    resolvedRequest.queryParameters.forEach((key, value) {
      if (value == null) {
        return;
      }
      mergedQuery[key] = value.toString();
    });

    return rust_api.RequestSpec(
      requestId: _nextRequestId(),
      method: resolvedRequest.method,
      path: path,
      query: mergedQuery.entries
          .map((entry) => (entry.key, entry.value))
          .toList(),
      headers: resolvedRequest.headers.entries
          .map((entry) => (entry.key, entry.value))
          .toList(),
      bodyBytes: encodeRequestBody(
        resolvedRequest.body,
        bodyBytes: resolvedRequest.bodyBytes,
        channel: NetChannel.rust,
      ),
      bodyFilePath: null,
      expectLargeResponse: resolvedRequest.expectLargeResponse,
      saveToFilePath: null,
      priority: 1,
    );
  }

  static rust_api.TransferTaskSpec toRustTransferTaskSpec(
    NetTransferTaskRequest request,
  ) {
    final resolvedRequest = resolveNetTransferTaskUrl(request);
    return rust_api.TransferTaskSpec(
      taskId: resolvedRequest.taskId,
      kind: resolvedRequest.kind.name,
      url: resolvedRequest.url,
      method: resolvedRequest.method,
      headers: resolvedRequest.headers.entries
          .map((entry) => (entry.key, entry.value))
          .toList(),
      localPath: resolvedRequest.localPath,
      resumeFrom: resolvedRequest.resumeFrom == null
          ? null
          : BigInt.from(resolvedRequest.resumeFrom!),
      expectedTotal: resolvedRequest.expectedTotal == null
          ? null
          : BigInt.from(resolvedRequest.expectedTotal!),
      priority: resolvedRequest.priority,
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
