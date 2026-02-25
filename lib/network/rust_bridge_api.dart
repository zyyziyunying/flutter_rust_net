import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import '../rust_bridge/api.dart' as rust_api;
import '../rust_bridge/frb_generated.dart';

abstract class RustBridgeApi {
  Future<void> ensureBridgeLoaded();

  Future<void> initNetEngine({required rust_api.NetEngineConfig config});

  Future<rust_api.ResponseMeta> request({required rust_api.RequestSpec spec});

  Future<String> startTransferTask({required rust_api.TransferTaskSpec spec});

  Future<List<rust_api.NetEvent>> pollEvents({required int limit});

  Future<bool> cancel({required String id});

  Future<int> clearCache({String? namespace});
}

class FrbRustBridgeApi implements RustBridgeApi {
  @override
  Future<void> ensureBridgeLoaded() async {
    if (RustLib.instance.initialized) {
      return;
    }

    try {
      await RustLib.init();
      return;
    } catch (_) {
      // fall through and try project-local dynamic libraries in debug/release
    }

    final fileName = _libraryFileName();
    if (fileName == null) {
      await RustLib.init();
      return;
    }

    final root = Directory.current.path;
    final candidatePaths = [
      '$root/../native/rust/net_engine/target/debug/$fileName',
      '$root/../native/rust/net_engine/target/release/$fileName',
    ];

    Object? lastError;
    for (final path in candidatePaths) {
      final normalized = path.replaceAll('\\', '/');
      if (!File(normalized).existsSync()) {
        continue;
      }
      try {
        await RustLib.init(externalLibrary: ExternalLibrary.open(normalized));
        return;
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError != null) {
      throw lastError;
    }
    await RustLib.init();
  }

  @override
  Future<void> initNetEngine({required rust_api.NetEngineConfig config}) {
    return rust_api.initNetEngine(config: config);
  }

  @override
  Future<rust_api.ResponseMeta> request({required rust_api.RequestSpec spec}) {
    return rust_api.request(spec: spec);
  }

  @override
  Future<String> startTransferTask({required rust_api.TransferTaskSpec spec}) {
    return rust_api.startTransferTask(spec: spec);
  }

  @override
  Future<List<rust_api.NetEvent>> pollEvents({required int limit}) {
    return rust_api.pollEvents(limit: limit);
  }

  @override
  Future<bool> cancel({required String id}) {
    return rust_api.cancel(id: id);
  }

  @override
  Future<int> clearCache({String? namespace}) async {
    final removedBytes = await rust_api.clearCache(namespace: namespace);
    return removedBytes.toInt();
  }

  String? _libraryFileName() {
    if (Platform.isWindows) {
      return 'net_engine.dll';
    }
    if (Platform.isLinux) {
      return 'libnet_engine.so';
    }
    if (Platform.isMacOS) {
      return 'libnet_engine.dylib';
    }
    return null;
  }
}
