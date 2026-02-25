import 'net_models.dart';

abstract class NetAdapter {
  bool get isReady => true;

  Future<NetResponse> request(NetRequest request, {bool fromFallback = false});

  Future<String> startTransferTask(NetTransferTaskRequest request) {
    throw UnsupportedError(
      '${runtimeType.toString()} does not support transfer tasks',
    );
  }

  Future<List<NetTransferEvent>> pollTransferEvents({int limit = 64}) async {
    return const [];
  }

  Future<bool> cancelTransferTask(String taskId) async {
    return false;
  }
}
