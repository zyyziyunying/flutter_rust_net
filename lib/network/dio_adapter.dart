import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'net_adapter.dart';
import 'net_models.dart';
import 'request_body_codec.dart';

class DioAdapter implements NetAdapter {
  static int _requestCounter = 0;
  static const int _maxPendingTransferEvents = 256;
  static const String _resumeDownloadUnsupportedMessage =
      'Dio download does not support resumeFrom; use the Rust channel for resume downloads.';

  final Dio _client;
  final Map<String, CancelToken> _transferCancelTokens = {};
  final List<NetTransferEvent> _transferEvents = [];

  DioAdapter({Dio? client}) : _client = client ?? Dio();

  @override
  bool get isReady => true;

  @override
  Future<NetResponse> request(
    NetRequest request, {
    bool fromFallback = false,
  }) async {
    final watch = Stopwatch()..start();
    final requestId = _nextRequestId();
    final uri = _buildUri(request.url, request.queryParameters);

    try {
      final bodyBytes = encodeRequestBody(
        request.body,
        bodyBytes: request.bodyBytes,
        channel: NetChannel.dio,
      );
      final response = await _client.requestUri<List<int>>(
        uri,
        data: bodyBytes,
        options: Options(
          method: request.method,
          headers: request.headers,
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
        ),
      );
      watch.stop();

      return NetResponse(
        statusCode: response.statusCode ?? 0,
        headers: _flattenHeaders(response.headers.map),
        bodyBytes: response.data,
        bridgeBytes: response.data?.length ?? 0,
        channel: NetChannel.dio,
        fromFallback: fromFallback,
        costMs: watch.elapsedMilliseconds,
        requestId: requestId,
      );
    } on NetException {
      watch.stop();
      rethrow;
    } on DioException catch (error) {
      watch.stop();
      throw _mapDioException(error, requestId: requestId);
    }
  }

  @override
  Future<String> startTransferTask(NetTransferTaskRequest request) async {
    final taskId = request.taskId;
    if (taskId.isEmpty) {
      throw NetException(
        code: NetErrorCode.parse,
        message: 'transfer task id is empty',
        channel: NetChannel.dio,
      );
    }
    if (request.isResumeDownload) {
      throw const NetException(
        code: NetErrorCode.infrastructure,
        message: _resumeDownloadUnsupportedMessage,
        channel: NetChannel.dio,
        fallbackEligible: false,
      );
    }
    if (_transferCancelTokens.containsKey(taskId)) {
      throw NetException(
        code: NetErrorCode.internal,
        message: 'transfer task already exists: $taskId',
        channel: NetChannel.dio,
      );
    }

    final cancelToken = CancelToken();
    _transferCancelTokens[taskId] = cancelToken;
    _emitTransferEvent(
      NetTransferEvent(
        id: taskId,
        kind: NetTransferEventKind.queued,
        transferred: 0,
        total: request.expectedTotal,
        channel: NetChannel.dio,
      ),
    );

    unawaited(_runTransferTask(request, cancelToken));
    return taskId;
  }

  @override
  Future<List<NetTransferEvent>> pollTransferEvents({int limit = 64}) async {
    if (limit <= 0 || _transferEvents.isEmpty) {
      return const [];
    }
    final size = limit < _transferEvents.length
        ? limit
        : _transferEvents.length;
    final events = _transferEvents.sublist(0, size);
    _transferEvents.removeRange(0, size);
    return events;
  }

  @override
  Future<bool> cancelTransferTask(String taskId) async {
    final token = _transferCancelTokens.remove(taskId);
    if (token == null) {
      return false;
    }
    token.cancel('canceled by caller');
    return true;
  }

  Uri _buildUri(String url, Map<String, dynamic> extraQueryParameters) {
    final uri = Uri.parse(url);
    if (extraQueryParameters.isEmpty) {
      return uri;
    }

    final merged = <String, String>{...uri.queryParameters};
    extraQueryParameters.forEach((key, value) {
      if (value == null) {
        return;
      }
      merged[key] = value.toString();
    });
    return uri.replace(queryParameters: merged);
  }

  Map<String, String> _flattenHeaders(Map<String, List<String>> source) {
    final map = <String, String>{};
    source.forEach((key, values) {
      if (values.isEmpty) {
        return;
      }
      map[key] = values.length == 1 ? values.first : values.join(',');
    });
    return map;
  }

  NetException _mapDioException(
    DioException error, {
    required String requestId,
  }) {
    if (error.type == DioExceptionType.cancel) {
      return NetException(
        code: NetErrorCode.canceled,
        message: error.message ?? 'request canceled',
        channel: NetChannel.dio,
        requestId: requestId,
      );
    }

    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return NetException(
        code: NetErrorCode.timeout,
        message: error.message ?? 'timeout',
        channel: NetChannel.dio,
        requestId: requestId,
      );
    }

    if (error.error is HandshakeException) {
      return NetException(
        code: NetErrorCode.tls,
        message: error.message ?? error.error.toString(),
        channel: NetChannel.dio,
        requestId: requestId,
      );
    }

    if (error.error is SocketException) {
      return NetException(
        code: NetErrorCode.dns,
        message: error.message ?? error.error.toString(),
        channel: NetChannel.dio,
        requestId: requestId,
      );
    }

    if (error.type == DioExceptionType.badResponse) {
      final status = error.response?.statusCode;
      final code = (status != null && status >= 400 && status < 500)
          ? NetErrorCode.http4xx
          : NetErrorCode.http5xx;
      return NetException(
        code: code,
        message: error.message ?? 'http error',
        channel: NetChannel.dio,
        statusCode: status,
        requestId: requestId,
      );
    }

    return NetException(
      code: NetErrorCode.internal,
      message: error.message ?? 'unknown dio error',
      channel: NetChannel.dio,
      requestId: requestId,
      cause: error.error,
    );
  }

  String _nextRequestId() {
    _requestCounter += 1;
    return 'dio_${DateTime.now().microsecondsSinceEpoch}_$_requestCounter';
  }

  Future<void> _runTransferTask(
    NetTransferTaskRequest request,
    CancelToken cancelToken,
  ) async {
    final watch = Stopwatch()..start();
    var transferred = request.resumeFrom ?? 0;
    var total = request.expectedTotal;
    _DownloadTarget? downloadTarget;

    _emitTransferEvent(
      NetTransferEvent(
        id: request.taskId,
        kind: NetTransferEventKind.started,
        transferred: transferred,
        total: total,
        channel: NetChannel.dio,
      ),
    );

    try {
      if (request.kind == NetTransferKind.download) {
        downloadTarget = await _prepareDownloadTarget(
          request.localPath,
          request.taskId,
        );
      }

      final response = request.kind == NetTransferKind.download
          ? await _runDownloadTask(
              request,
              cancelToken,
              savePath: downloadTarget!.tempFile.path,
              onProgress: (value, progressTotal) {
                transferred = value;
                total = progressTotal ?? total;
                _emitTransferEvent(
                  NetTransferEvent(
                    id: request.taskId,
                    kind: NetTransferEventKind.progress,
                    transferred: transferred,
                    total: total,
                    channel: NetChannel.dio,
                  ),
                );
              },
            )
          : await _runUploadTask(
              request,
              cancelToken,
              onProgress: (value, progressTotal) {
                transferred = value;
                total = progressTotal ?? total;
                _emitTransferEvent(
                  NetTransferEvent(
                    id: request.taskId,
                    kind: NetTransferEventKind.progress,
                    transferred: transferred,
                    total: total,
                    channel: NetChannel.dio,
                  ),
                );
              },
            );

      final statusCode = response.statusCode ?? 0;
      if (!_isSuccessfulStatus(statusCode)) {
        final code = statusCode >= 400 && statusCode < 500
            ? NetErrorCode.http4xx
            : NetErrorCode.http5xx;
        throw NetException(
          code: code,
          message: 'transfer failed with status $statusCode',
          channel: NetChannel.dio,
          statusCode: statusCode,
        );
      }
      if (downloadTarget != null) {
        await _publishDownloadTarget(downloadTarget);
      }

      watch.stop();
      _emitTransferEvent(
        NetTransferEvent(
          id: request.taskId,
          kind: NetTransferEventKind.completed,
          transferred: transferred,
          total: total,
          statusCode: statusCode,
          costMs: watch.elapsedMilliseconds,
          channel: NetChannel.dio,
        ),
      );
    } on DioException catch (error) {
      watch.stop();
      await _cleanupDownloadTempFile(downloadTarget);
      final mapped = _mapDioException(error, requestId: _nextRequestId());
      final canceled =
          error.type == DioExceptionType.cancel || CancelToken.isCancel(error);
      _emitTransferEvent(
        NetTransferEvent(
          id: request.taskId,
          kind: canceled
              ? NetTransferEventKind.canceled
              : NetTransferEventKind.failed,
          transferred: transferred,
          total: total,
          statusCode: mapped.statusCode ?? error.response?.statusCode,
          message: mapped.message,
          costMs: watch.elapsedMilliseconds,
          channel: NetChannel.dio,
        ),
      );
    } on NetException catch (error) {
      watch.stop();
      await _cleanupDownloadTempFile(downloadTarget);
      _emitTransferEvent(
        NetTransferEvent(
          id: request.taskId,
          kind: error.code == NetErrorCode.canceled
              ? NetTransferEventKind.canceled
              : NetTransferEventKind.failed,
          transferred: transferred,
          total: total,
          statusCode: error.statusCode,
          message: error.message,
          costMs: watch.elapsedMilliseconds,
          channel: NetChannel.dio,
        ),
      );
    } catch (error) {
      watch.stop();
      await _cleanupDownloadTempFile(downloadTarget);
      _emitTransferEvent(
        NetTransferEvent(
          id: request.taskId,
          kind: NetTransferEventKind.failed,
          transferred: transferred,
          total: total,
          message: '$error',
          costMs: watch.elapsedMilliseconds,
          channel: NetChannel.dio,
        ),
      );
    } finally {
      _transferCancelTokens.remove(request.taskId);
    }
  }

  Future<Response<dynamic>> _runDownloadTask(
    NetTransferTaskRequest request,
    CancelToken cancelToken, {
    required String savePath,
    required void Function(int transferred, int? total) onProgress,
  }) async {
    return _client.downloadUri(
      Uri.parse(request.url),
      savePath,
      cancelToken: cancelToken,
      options: Options(
        method: request.method,
        headers: request.headers,
        validateStatus: (_) => true,
      ),
      onReceiveProgress: (received, total) {
        onProgress(received, total > 0 ? total : null);
      },
    );
  }

  Future<_DownloadTarget> _prepareDownloadTarget(
    String localPath,
    String taskId,
  ) async {
    final finalFile = File(localPath);
    final parent = finalFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final tempFile = File(
      '$localPath.dio-download-${DateTime.now().microsecondsSinceEpoch}-${taskId.hashCode}.part',
    );
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    return _DownloadTarget(finalFile: finalFile, tempFile: tempFile);
  }

  Future<void> _publishDownloadTarget(_DownloadTarget target) async {
    try {
      await target.tempFile.rename(target.finalFile.path);
    } on FileSystemException {
      if (!await target.finalFile.exists()) {
        rethrow;
      }
      await target.finalFile.delete();
      await target.tempFile.rename(target.finalFile.path);
    }
  }

  Future<void> _cleanupDownloadTempFile(_DownloadTarget? target) async {
    if (target == null) {
      return;
    }
    try {
      if (await target.tempFile.exists()) {
        await target.tempFile.delete();
      }
    } on FileSystemException {
      // Best-effort cleanup after failed or canceled downloads.
    }
  }

  Future<Response<dynamic>> _runUploadTask(
    NetTransferTaskRequest request,
    CancelToken cancelToken, {
    required void Function(int transferred, int? total) onProgress,
  }) async {
    final sourceFile = File(request.localPath);
    if (!await sourceFile.exists()) {
      throw NetException(
        code: NetErrorCode.io,
        message: 'upload source file not found: ${request.localPath}',
        channel: NetChannel.dio,
      );
    }

    final fileLength = await sourceFile.length();
    final uploadHeaders = <String, String>{
      HttpHeaders.contentLengthHeader: fileLength.toString(),
      ...request.headers,
    };

    return _client.requestUri<dynamic>(
      Uri.parse(request.url),
      data: sourceFile.openRead(),
      cancelToken: cancelToken,
      options: Options(
        method: request.method,
        headers: uploadHeaders,
        validateStatus: (_) => true,
      ),
      onSendProgress: (sent, total) {
        onProgress(sent, total > 0 ? total : fileLength);
      },
    );
  }

  bool _isSuccessfulStatus(int statusCode) {
    return statusCode >= 200 && statusCode < 300;
  }

  void _emitTransferEvent(NetTransferEvent event) {
    if (_isTerminalTransferEvent(event.kind)) {
      _transferEvents.removeWhere((existing) => existing.id == event.id);
      _transferEvents.add(event);
      _trimBufferedTransferEvents();
      return;
    }

    if (event.kind == NetTransferEventKind.progress) {
      final existingIndex = _transferEvents.lastIndexWhere(
        (existing) =>
            existing.id == event.id &&
            existing.kind == NetTransferEventKind.progress,
      );
      if (existingIndex >= 0) {
        _transferEvents[existingIndex] = event;
        return;
      }
    }

    _transferEvents.add(event);
    _trimBufferedTransferEvents();
  }

  bool _isTerminalTransferEvent(NetTransferEventKind kind) {
    return kind == NetTransferEventKind.completed ||
        kind == NetTransferEventKind.failed ||
        kind == NetTransferEventKind.canceled;
  }

  void _trimBufferedTransferEvents() {
    final overflow = _transferEvents.length - _maxPendingTransferEvents;
    if (overflow <= 0) {
      return;
    }
    _transferEvents.removeRange(0, overflow);
  }
}

class _DownloadTarget {
  const _DownloadTarget({required this.finalFile, required this.tempFile});

  final File finalFile;
  final File tempFile;
}
