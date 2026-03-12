import 'package:flutter_rust_net/network/net_adapter.dart';
import 'package:flutter_rust_net/network/net_models.dart';

class FakeNetAdapter implements NetAdapter {
  final bool _isReady;
  final Future<NetResponse> Function(NetRequest request, {bool fromFallback})
  _delegate;
  final Future<String> Function(NetTransferTaskRequest request)
  _startTransferDelegate;
  final Future<List<NetTransferEvent>> Function({int limit})
  _pollTransferDelegate;
  final Future<bool> Function(String taskId) _cancelTransferDelegate;

  FakeNetAdapter(
    this._delegate, {
    bool isReady = true,
    Future<String> Function(NetTransferTaskRequest request)?
    startTransferDelegate,
    Future<List<NetTransferEvent>> Function({int limit})? pollTransferDelegate,
    Future<bool> Function(String taskId)? cancelTransferDelegate,
  }) : _isReady = isReady,
       _startTransferDelegate = startTransferDelegate ?? _defaultStartTransfer,
       _pollTransferDelegate = pollTransferDelegate ?? _defaultPollTransfer,
       _cancelTransferDelegate = cancelTransferDelegate ?? _defaultCancel;

  @override
  bool get isReady => _isReady;

  @override
  Future<NetResponse> request(NetRequest request, {bool fromFallback = false}) {
    return _delegate(request, fromFallback: fromFallback);
  }

  @override
  Future<String> startTransferTask(NetTransferTaskRequest request) {
    return _startTransferDelegate(request);
  }

  @override
  Future<List<NetTransferEvent>> pollTransferEvents({int limit = 64}) {
    return _pollTransferDelegate(limit: limit);
  }

  @override
  Future<bool> cancelTransferTask(String taskId) {
    return _cancelTransferDelegate(taskId);
  }

  static Future<String> _defaultStartTransfer(
    NetTransferTaskRequest request,
  ) async {
    return request.taskId;
  }

  static Future<List<NetTransferEvent>> _defaultPollTransfer({
    int limit = 64,
  }) async {
    return const [];
  }

  static Future<bool> _defaultCancel(String taskId) async {
    return false;
  }
}

NetResponse okResponse({
  required NetChannel channel,
  required bool fromFallback,
  String? requestId,
}) {
  return NetResponse(
    statusCode: 200,
    headers: const {'content-type': 'application/json'},
    bodyBytes: const [123, 125],
    channel: channel,
    fromFallback: fromFallback,
    costMs: 1,
    requestId: requestId ?? '${channel.name}-request',
  );
}
