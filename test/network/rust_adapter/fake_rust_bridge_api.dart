import 'package:flutter_rust_net/network/rust_bridge_api.dart';
import 'package:flutter_rust_net/rust_bridge/api.dart' as rust_api;

class FakeRustBridgeApi implements RustBridgeApi {
  int ensureLoadedCalls = 0;
  int initCalls = 0;
  int shutdownCalls = 0;
  int startTransferCalls = 0;
  int pollEventsCalls = 0;
  int cancelCalls = 0;
  int clearCacheCalls = 0;
  rust_api.NetEngineConfig? lastInitConfig;
  final Object? initError;
  final Future<void> Function(rust_api.NetEngineConfig config)? initResponder;
  final Future<rust_api.ResponseMeta> Function(rust_api.RequestSpec spec)?
  requestResponder;
  final Future<String> Function(rust_api.TransferTaskSpec spec)?
  startTransferResponder;
  final Future<List<rust_api.NetEvent>> Function(int limit)?
  pollEventsResponder;
  final Future<bool> Function(String id)? cancelResponder;
  final Future<int> Function(String? namespace)? clearCacheResponder;

  FakeRustBridgeApi({
    this.initError,
    this.initResponder,
    this.requestResponder,
    this.startTransferResponder,
    this.pollEventsResponder,
    this.cancelResponder,
    this.clearCacheResponder,
  });

  @override
  Future<void> ensureBridgeLoaded() async {
    ensureLoadedCalls += 1;
  }

  @override
  Future<void> initNetEngine({required rust_api.NetEngineConfig config}) async {
    initCalls += 1;
    lastInitConfig = config;
    final responder = initResponder;
    if (responder != null) {
      await responder(config);
      return;
    }
    if (initError != null) {
      throw initError!;
    }
  }

  @override
  Future<void> shutdownNetEngine() async {
    shutdownCalls += 1;
  }

  @override
  Future<rust_api.ResponseMeta> request({required rust_api.RequestSpec spec}) {
    final responder = requestResponder;
    if (responder != null) {
      return responder(spec);
    }
    throw UnimplementedError('requestResponder not set');
  }

  @override
  Future<String> startTransferTask({required rust_api.TransferTaskSpec spec}) {
    startTransferCalls += 1;
    final responder = startTransferResponder;
    if (responder != null) {
      return responder(spec);
    }
    throw UnimplementedError('startTransferResponder not set');
  }

  @override
  Future<List<rust_api.NetEvent>> pollEvents({required int limit}) {
    pollEventsCalls += 1;
    final responder = pollEventsResponder;
    if (responder != null) {
      return responder(limit);
    }
    return Future.value(const <rust_api.NetEvent>[]);
  }

  @override
  Future<bool> cancel({required String id}) {
    cancelCalls += 1;
    final responder = cancelResponder;
    if (responder != null) {
      return responder(id);
    }
    return Future.value(false);
  }

  @override
  Future<int> clearCache({String? namespace}) {
    clearCacheCalls += 1;
    final responder = clearCacheResponder;
    if (responder != null) {
      return responder(namespace);
    }
    return Future.value(0);
  }
}
