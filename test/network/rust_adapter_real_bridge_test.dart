import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/net_models.dart';
import 'package:flutter_rust_net/network/rust_adapter.dart';
import 'package:flutter_rust_net/network/rust_bridge_api.dart';
import 'package:flutter_rust_net/rust_bridge/frb_generated.dart';

void main() {
  final realBridgeSkip = _realBridgeSkipReason();

  group('RustAdapter real bridge', () {
    test(
      'loads local native library when launched from example working directory',
      () async {
        final originalCurrent = Directory.current;
        addTearDown(() {
          Directory.current = originalCurrent;
          if (RustLib.instance.initialized) {
            RustLib.dispose();
          }
        });

        final exampleDir = Directory.fromUri(
          originalCurrent.absolute.uri.resolve('example/'),
        );
        Directory.current = exampleDir;

        await FrbRustBridgeApi().ensureBridgeLoaded();

        expect(RustLib.instance.initialized, isTrue);
      },
      skip: realBridgeSkip,
    );

    test(
      'shutdown allows reinitialize with new config through the real bridge',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp(
          'flutter_rust_net_real_bridge_',
        );
        final separator = Platform.pathSeparator;
        final adapter = RustAdapter();
        addTearDown(() async {
          if (adapter.isReady) {
            await adapter.shutdownEngine();
          }
          if (tempRoot.existsSync()) {
            await tempRoot.delete(recursive: true);
          }
          if (RustLib.instance.initialized) {
            RustLib.dispose();
          }
        });

        await adapter.initializeEngine(
          options: RustEngineInitOptions(
            cacheDir: '${tempRoot.path}${separator}cache_a',
            cacheDefaultTtlSeconds: 12,
          ),
        );

        await adapter.shutdownEngine();

        expect(adapter.isReady, isFalse);

        await adapter.initializeEngine(
          options: RustEngineInitOptions(
            cacheDir: '${tempRoot.path}${separator}cache_b',
            cacheDefaultTtlSeconds: 30,
          ),
        );

        expect(adapter.isReady, isTrue);
      },
      skip: realBridgeSkip,
    );

    test(
      'rejects duplicate transfer task ids through the real bridge',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp(
          'flutter_rust_net_real_transfer_',
        );
        final separator = Platform.pathSeparator;
        final downloadPath = File('${tempRoot.path}${separator}download.bin');
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final releaseResponse = Completer<void>();
        server.listen((request) async {
          await releaseResponse.future;
          request.response.statusCode = HttpStatus.ok;
          request.response.add(List<int>.filled(16, 0x41));
          try {
            await request.response.close();
          } catch (_) {}
        });

        final adapter = RustAdapter();
        addTearDown(() async {
          if (!releaseResponse.isCompleted) {
            releaseResponse.complete();
          }
          await server.close(force: true);
          if (adapter.isReady) {
            await adapter.shutdownEngine();
          }
          if (tempRoot.existsSync()) {
            await tempRoot.delete(recursive: true);
          }
          if (RustLib.instance.initialized) {
            RustLib.dispose();
          }
        });

        await adapter.initializeEngine(
          options: RustEngineInitOptions(
            cacheDir: '${tempRoot.path}${separator}cache',
          ),
        );

        final request = NetTransferTaskRequest(
          taskId: 'duplicate-real-task',
          kind: NetTransferKind.download,
          url: 'http://127.0.0.1:${server.port}/slow.bin',
          localPath: downloadPath.path,
        );

        await adapter.startTransferTask(request);

        await expectLater(
          adapter.startTransferTask(request),
          throwsA(
            isA<NetException>().having(
              (error) => error.message,
              'message',
              contains('transfer task already exists: duplicate-real-task'),
            ),
          ),
        );

        expect(await adapter.cancelTransferTask('duplicate-real-task'), isTrue);
      },
      skip: realBridgeSkip,
    );
  });
}

Object _realBridgeSkipReason() {
  final libraryFileName = _localLibraryFileName();
  if (libraryFileName == null) {
    return 'real bridge tests require a desktop dart:ffi platform';
  }

  final packageRoot = Directory.current.absolute;
  final candidates = <File>[
    File.fromUri(
      packageRoot.uri.resolve(
        'native/rust/net_engine/target/debug/$libraryFileName',
      ),
    ),
    File.fromUri(
      packageRoot.uri.resolve(
        'native/rust/net_engine/target/release/$libraryFileName',
      ),
    ),
  ];
  if (candidates.any((file) => file.existsSync())) {
    return false;
  }

  return 'build native/rust/net_engine before running real bridge tests';
}

String? _localLibraryFileName() {
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
