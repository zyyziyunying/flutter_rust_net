import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/dio_adapter.dart';
import 'package:flutter_rust_net/network/net_adapter.dart';
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

    test(
      'cache-off keeps dio and rust request semantics aligned through the real bridge',
      () async {
        final scenario = await _startCacheScenarioServer();
        final tempRoot = await Directory.systemTemp.createTemp(
          'flutter_rust_net_real_cache_off_',
        );
        final separator = Platform.pathSeparator;
        final dioAdapter = DioAdapter();
        final rustAdapter = RustAdapter();
        addTearDown(() async {
          await scenario.close();
          if (rustAdapter.isReady) {
            await rustAdapter.shutdownEngine();
          }
          if (tempRoot.existsSync()) {
            await tempRoot.delete(recursive: true);
          }
          if (RustLib.instance.initialized) {
            RustLib.dispose();
          }
        });

        await rustAdapter.initializeEngine(
          options: RustEngineInitOptions(
            cacheDir: '${tempRoot.path}${separator}cache',
          ),
        );

        final suffix = DateTime.now().microsecondsSinceEpoch.toString();
        final dioKey = 'dio_off_$suffix';
        final rustKey = 'rust_off_$suffix';
        final cacheControl = <String, String>{
          HttpHeaders.cacheControlHeader: 'no-store',
        };

        final dio1 = await _sendAndDecode(
          adapter: dioAdapter,
          baseUrl: scenario.baseUrl,
          key: dioKey,
          cacheMode: 'off',
          headers: cacheControl,
        );
        final dio2 = await _sendAndDecode(
          adapter: dioAdapter,
          baseUrl: scenario.baseUrl,
          key: dioKey,
          cacheMode: 'off',
          headers: cacheControl,
        );
        final rust1 = await _sendAndDecode(
          adapter: rustAdapter,
          baseUrl: scenario.baseUrl,
          key: rustKey,
          cacheMode: 'off',
          headers: cacheControl,
        );
        final rust2 = await _sendAndDecode(
          adapter: rustAdapter,
          baseUrl: scenario.baseUrl,
          key: rustKey,
          cacheMode: 'off',
          headers: cacheControl,
        );

        expect([dio1.hitCount, dio2.hitCount], [1, 2]);
        expect([rust1.hitCount, rust2.hitCount], [1, 2]);
        expect(rust1.response.statusCode, dio1.response.statusCode);
        expect(rust1.response.fromCache, isFalse);
        expect(rust2.response.fromCache, isFalse);
        expect(scenario.requestHitsByKey[dioKey], 2);
        expect(scenario.requestHitsByKey[rustKey], 2);
        expect(dio1.cacheMode, 'off');
        expect(rust1.cacheMode, 'off');
      },
      skip: realBridgeSkip,
    );

    test(
      'cache-on serves the second rust hit from cache through the real bridge',
      () async {
        final scenario = await _startCacheScenarioServer();
        final tempRoot = await Directory.systemTemp.createTemp(
          'flutter_rust_net_real_cache_on_',
        );
        final separator = Platform.pathSeparator;
        final dioAdapter = DioAdapter();
        final rustAdapter = RustAdapter();
        addTearDown(() async {
          await scenario.close();
          if (rustAdapter.isReady) {
            await rustAdapter.shutdownEngine();
          }
          if (tempRoot.existsSync()) {
            await tempRoot.delete(recursive: true);
          }
          if (RustLib.instance.initialized) {
            RustLib.dispose();
          }
        });

        await rustAdapter.initializeEngine(
          options: RustEngineInitOptions(
            cacheDir: '${tempRoot.path}${separator}cache',
          ),
        );

        final suffix = DateTime.now().microsecondsSinceEpoch.toString();
        final dioKey = 'dio_on_$suffix';
        final rustKey = 'rust_on_$suffix';

        final dio1 = await _sendAndDecode(
          adapter: dioAdapter,
          baseUrl: scenario.baseUrl,
          key: dioKey,
          cacheMode: 'on',
        );
        final dio2 = await _sendAndDecode(
          adapter: dioAdapter,
          baseUrl: scenario.baseUrl,
          key: dioKey,
          cacheMode: 'on',
        );
        final rust1 = await _sendAndDecode(
          adapter: rustAdapter,
          baseUrl: scenario.baseUrl,
          key: rustKey,
          cacheMode: 'on',
        );
        final rust2 = await _sendAndDecode(
          adapter: rustAdapter,
          baseUrl: scenario.baseUrl,
          key: rustKey,
          cacheMode: 'on',
        );

        expect(dio1.response.statusCode, HttpStatus.ok);
        expect(rust1.response.statusCode, dio1.response.statusCode);
        expect([dio1.hitCount, dio2.hitCount], [1, 2]);
        expect([rust1.hitCount, rust2.hitCount], [1, 1]);
        expect(rust1.response.fromCache, isFalse);
        expect(rust2.response.fromCache, isTrue);
        expect(scenario.requestHitsByKey[dioKey], 2);
        expect(scenario.requestHitsByKey[rustKey], 1);
        expect(dio1.cacheMode, 'on');
        expect(rust1.cacheMode, dio1.cacheMode);
      },
      skip: realBridgeSkip,
    );
  });
}

Future<_DecodedResponse> _sendAndDecode({
  required NetAdapter adapter,
  required String baseUrl,
  required String key,
  required String cacheMode,
  Map<String, String> headers = const {},
}) async {
  final response = await adapter.request(
    NetRequest(
      method: 'GET',
      url: '$baseUrl/cache?key=$key&cache=$cacheMode',
      headers: headers,
    ),
  );
  final bodyBytes = await _readResponseBody(response);
  final payload = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;
  return _DecodedResponse(
    response: response,
    hitCount: payload['hit'] as int,
    cacheMode: payload['cache'] as String,
  );
}

Future<List<int>> _readResponseBody(NetResponse response) async {
  final bodyBytes = response.bodyBytes;
  if (bodyBytes != null) {
    return bodyBytes;
  }
  final bodyFilePath = response.bodyFilePath;
  if (bodyFilePath == null) {
    return const <int>[];
  }

  final file = File(bodyFilePath);
  final bytes = await file.readAsBytes();
  try {
    await file.delete();
  } catch (_) {}
  return bytes;
}

Future<_CacheScenarioServer> _startCacheScenarioServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final requestHitsByKey = <String, int>{};

  server.listen((request) async {
    final key = request.uri.queryParameters['key'] ?? 'default';
    final cacheMode = request.uri.queryParameters['cache'] ?? 'off';
    final hits = (requestHitsByKey[key] ?? 0) + 1;
    requestHitsByKey[key] = hits;

    final payload = utf8.encode(
      jsonEncode({'key': key, 'cache': cacheMode, 'hit': hits, 'ok': true}),
    );

    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    if (cacheMode == 'on') {
      request.response.headers.set(
        HttpHeaders.cacheControlHeader,
        'max-age=120',
      );
    }
    request.response.add(payload);
    await request.response.close();
  });

  return _CacheScenarioServer(
    server: server,
    baseUrl: 'http://${server.address.address}:${server.port}',
    requestHitsByKey: requestHitsByKey,
  );
}

class _DecodedResponse {
  final NetResponse response;
  final int hitCount;
  final String cacheMode;

  const _DecodedResponse({
    required this.response,
    required this.hitCount,
    required this.cacheMode,
  });
}

class _CacheScenarioServer {
  final HttpServer server;
  final String baseUrl;
  final Map<String, int> requestHitsByKey;

  const _CacheScenarioServer({
    required this.server,
    required this.baseUrl,
    required this.requestHitsByKey,
  });

  Future<void> close() async {
    await server.close(force: true);
  }
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
