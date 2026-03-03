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
  static const String _nativeProjectPath = '../native/rust/net_engine';
  static const String _rebuildHintCommand =
      'cd ../native/rust/net_engine && cargo build --release -p net_engine';

  @override
  Future<void> ensureBridgeLoaded() async {
    if (RustLib.instance.initialized) {
      return;
    }

    final fileName = _libraryFileName();
    if (fileName == null) {
      await RustLib.init();
      return;
    }

    final root = Directory.current.path;
    final nativeRoot = '$root/$_nativeProjectPath';
    final candidatePaths = [
      '$nativeRoot/target/debug/$fileName',
      '$nativeRoot/target/release/$fileName',
    ];
    final latestSourceTime = _latestModifiedAt([
      '$nativeRoot/src/frb_generated.rs',
      '$nativeRoot/src/api.rs',
      '$nativeRoot/Cargo.toml',
      '$nativeRoot/Cargo.lock',
    ]);

    Object? lastError;
    final staleLibraries = <String>[];
    for (final path in candidatePaths) {
      final normalized = path.replaceAll('\\', '/');
      final libraryFile = File(normalized);
      if (!libraryFile.existsSync()) {
        continue;
      }
      if (latestSourceTime != null) {
        final libraryModifiedAt = libraryFile.lastModifiedSync();
        if (libraryModifiedAt.isBefore(latestSourceTime)) {
          staleLibraries.add(normalized);
          continue;
        }
      }
      try {
        await RustLib.init(externalLibrary: ExternalLibrary.open(normalized));
        return;
      } catch (error) {
        lastError = error;
      }
    }

    if (staleLibraries.isNotEmpty) {
      throw StateError(
        'Detected stale net_engine native library (${staleLibraries.join(', ')}). '
        'Please rebuild before running Rust benchmark/init: $_rebuildHintCommand',
      );
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

  DateTime? _latestModifiedAt(List<String> paths) {
    DateTime? latest;
    for (final path in paths) {
      final normalized = path.replaceAll('\\', '/');
      final file = File(normalized);
      if (!file.existsSync()) {
        continue;
      }
      final modifiedAt = file.lastModifiedSync();
      if (latest == null || latest.isBefore(modifiedAt)) {
        latest = modifiedAt;
      }
    }
    return latest;
  }
}
