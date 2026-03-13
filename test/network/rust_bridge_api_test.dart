import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/rust_bridge_api.dart';
import 'package:flutter_rust_net/rust_bridge/frb_generated.dart';

void main() {
  group('FrbRustBridgeApi local native root resolution', () {
    final bridge = FrbRustBridgeApi();

    test('finds native project root from package root working directory', () {
      final nativeRoot = bridge.resolveNativeProjectRoot(
        currentDirectory: Directory.current.absolute,
      );

      expect(nativeRoot, isNotNull);
      expect(
        nativeRoot!.replaceAll('\\', '/'),
        endsWith('/native/rust/net_engine'),
      );
      expect(Directory(nativeRoot).existsSync(), isTrue);
    });

    test('finds native project root from example working directory', () {
      final exampleDir = Directory.fromUri(
        Directory.current.absolute.uri.resolve('example/'),
      );
      expect(exampleDir.existsSync(), isTrue);

      final nativeRoot = bridge.resolveNativeProjectRoot(
        currentDirectory: exampleDir,
      );

      expect(nativeRoot, isNotNull);
      expect(
        nativeRoot!.replaceAll('\\', '/'),
        endsWith('/native/rust/net_engine'),
      );
      expect(Directory(nativeRoot).existsSync(), isTrue);
    });
  });

  group('FRB default loader', () {
    final skipReason = _defaultLoaderSkipReason();

    test(
      'RustLib.init loads local native library from example working directory',
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
        expect(exampleDir.existsSync(), isTrue);
        Directory.current = exampleDir;

        await RustLib.init();

        expect(RustLib.instance.initialized, isTrue);
      },
      skip: skipReason,
    );
  });
}

Object _defaultLoaderSkipReason() {
  final libraryFileName = _localLibraryFileName();
  if (libraryFileName == null) {
    return 'default loader test requires a desktop dart:ffi platform';
  }

  final packageRoot = Directory.current.absolute;
  final releaseLibrary = File.fromUri(
    packageRoot.uri.resolve(
      'native/rust/net_engine/target/release/$libraryFileName',
    ),
  );
  if (releaseLibrary.existsSync()) {
    return false;
  }

  return 'build native/rust/net_engine release library before running default loader tests';
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
