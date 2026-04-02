import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/net_models.dart';
import 'package:flutter_rust_net/network/rhttp_adapter.dart';
import 'package:rhttp/rhttp.dart' as rhttp;

void main() {
  final realRhttpSkip = _realRhttpSkipReason();

  group('RhttpAdapter request path', () {
    test('maps success response and keeps bytes-first metadata', () async {
      RhttpAdapterRequest? capturedRequest;
      final responseBytes = Uint8List.fromList(utf8.encode('{"ok":true}'));
      final adapter = RhttpAdapter(
        requestHandler: (request) async {
          capturedRequest = request;
          return RhttpAdapterResponse(
            statusCode: io.HttpStatus.created,
            headers: const [
              ('content-type', 'application/json'),
              ('x-repeat', 'a'),
              ('x-repeat', 'b'),
            ],
            bodyBytes: responseBytes,
          );
        },
      );

      final response = await adapter.request(
        const NetRequest(
          method: 'GET',
          url: 'https://example.com/items?lang=en',
          headers: {'x-trace-id': 'trace-1'},
          queryParameters: {'limit': 10},
        ),
        fromFallback: true,
      );

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.method, 'GET');
      expect(
        capturedRequest!.url,
        'https://example.com/items?lang=en&limit=10',
      );
      expect(capturedRequest!.headers['x-trace-id'], 'trace-1');
      expect(capturedRequest!.bodyBytes, isNull);

      expect(response.statusCode, io.HttpStatus.created);
      expect(response.headers['content-type'], 'application/json');
      expect(response.headers['x-repeat'], 'a,b');
      expect(response.bodyBytes, responseBytes);
      expect(response.bridgeBytes, responseBytes.length);
      expect(response.channel, NetChannel.rust);
      expect(response.fromFallback, isTrue);
      expect(response.fromCache, isFalse);
      expect(response.bodyFilePath, isNull);
      expect(response.requestId, isNotNull);
      expect(response.requestId, isNotEmpty);
    });

    test('returns 4xx response instead of throwing', () async {
      final responseBytes = Uint8List.fromList(utf8.encode('missing'));
      final adapter = RhttpAdapter(
        clientSettings: const rhttp.ClientSettings(throwOnStatusCode: true),
        requestHandler: (request) async {
          return RhttpAdapterResponse(
            statusCode: io.HttpStatus.notFound,
            headers: const [('content-type', 'text/plain')],
            bodyBytes: responseBytes,
          );
        },
      );

      final response = await adapter.request(
        const NetRequest(method: 'GET', url: 'https://example.com/missing'),
      );

      expect(response.statusCode, io.HttpStatus.notFound);
      expect(response.bodyBytes, responseBytes);
      expect(response.channel, NetChannel.rust);
    });

    test('maps timeout errors as fallback-eligible net exceptions', () async {
      final adapter = RhttpAdapter(
        requestHandler: (request) async {
          throw rhttp.RhttpTimeoutException(_toRhttpRequest(request));
        },
      );

      await expectLater(
        adapter.request(
          const NetRequest(method: 'GET', url: 'https://example.com/slow'),
        ),
        throwsA(
          isA<NetException>()
              .having((error) => error.code, 'code', NetErrorCode.timeout)
              .having((error) => error.channel, 'channel', NetChannel.rust)
              .having(
                (error) => error.fallbackEligible,
                'fallbackEligible',
                isTrue,
              )
              .having((error) => error.requestId, 'requestId', isNotNull),
        ),
      );
    });

    test(
      'maps connection failures as fallback-eligible io exceptions',
      () async {
        final adapter = RhttpAdapter(
          requestHandler: (request) async {
            throw rhttp.RhttpConnectionException(
              _toRhttpRequest(request),
              'connection refused',
            );
          },
        );

        await expectLater(
          adapter.request(
            const NetRequest(method: 'GET', url: 'https://example.com/down'),
          ),
          throwsA(
            isA<NetException>()
                .having((error) => error.code, 'code', NetErrorCode.io)
                .having((error) => error.channel, 'channel', NetChannel.rust)
                .having(
                  (error) => error.fallbackEligible,
                  'fallbackEligible',
                  isTrue,
                )
                .having((error) => error.requestId, 'requestId', isNotNull),
          ),
        );
      },
    );
  });

  group('RhttpAdapter real rhttp path', () {
    test('tracks readiness from real client initialization', () async {
      final server = await io.HttpServer.bind(
        io.InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() async {
        await server.close(force: true);
      });
      server.listen((request) async {
        request.response.statusCode = io.HttpStatus.ok;
        request.response.add(utf8.encode('{}'));
        await request.response.close();
      });

      final adapter = RhttpAdapter();

      expect(adapter.isReady, isFalse);

      final response = await adapter.request(
        NetRequest(
          method: 'GET',
          url: 'http://${server.address.address}:${server.port}/ready',
        ),
      );

      expect(response.statusCode, io.HttpStatus.ok);
      expect(adapter.isReady, isTrue);
    }, skip: realRhttpSkip);

    test('real client keeps 4xx responses instead of throwing', () async {
      final server = await io.HttpServer.bind(
        io.InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() async {
        await server.close(force: true);
      });
      server.listen((request) async {
        request.response.statusCode = io.HttpStatus.notFound;
        request.response.headers.contentType = io.ContentType.text;
        request.response.write('missing');
        await request.response.close();
      });

      final adapter = RhttpAdapter(
        clientSettings: const rhttp.ClientSettings(throwOnStatusCode: true),
      );

      final response = await adapter.request(
        NetRequest(
          method: 'GET',
          url: 'http://${server.address.address}:${server.port}/missing',
        ),
      );

      expect(response.statusCode, io.HttpStatus.notFound);
      expect(utf8.decode(response.bodyBytes!), 'missing');
      expect(response.channel, NetChannel.rust);
      expect(adapter.isReady, isTrue);
    }, skip: realRhttpSkip);

    test(
      'retries client creation after failure and reuses successful client',
      () async {
        final server = await io.HttpServer.bind(
          io.InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() async {
          await server.close(force: true);
        });
        var serverHits = 0;
        server.listen((request) async {
          serverHits += 1;
          request.response.statusCode = io.HttpStatus.ok;
          request.response.add(utf8.encode('ok'));
          await request.response.close();
        });

        var createCalls = 0;
        final adapter = RhttpAdapter(
          clientFactory: (settings) async {
            createCalls += 1;
            if (createCalls == 1) {
              throw StateError('client create failed');
            }
            return rhttp.RhttpClient.create(settings: settings);
          },
        );

        expect(adapter.isReady, isFalse);
        await expectLater(
          adapter.request(
            NetRequest(
              method: 'GET',
              url: 'http://${server.address.address}:${server.port}/retry',
            ),
          ),
          throwsA(
            isA<NetException>().having(
              (error) => error.code,
              'code',
              NetErrorCode.infrastructure,
            ),
          ),
        );
        expect(adapter.isReady, isFalse);

        final firstSuccess = await adapter.request(
          NetRequest(
            method: 'GET',
            url: 'http://${server.address.address}:${server.port}/retry',
          ),
        );
        final secondSuccess = await adapter.request(
          NetRequest(
            method: 'GET',
            url: 'http://${server.address.address}:${server.port}/retry',
          ),
        );

        expect(firstSuccess.statusCode, io.HttpStatus.ok);
        expect(secondSuccess.statusCode, io.HttpStatus.ok);
        expect(createCalls, 2);
        expect(serverHits, 2);
        expect(adapter.isReady, isTrue);
      },
      skip: realRhttpSkip,
    );
  });
}

rhttp.HttpRequest _toRhttpRequest(RhttpAdapterRequest request) {
  return rhttp.HttpRequest(
    method: rhttp.HttpMethod(request.method),
    url: request.url,
    headers: request.headers.isEmpty
        ? null
        : rhttp.HttpHeaders.rawMap(request.headers),
    body: request.bodyBytes == null
        ? null
        : rhttp.HttpBody.bytes(request.bodyBytes!),
    expectBody: rhttp.HttpExpectBody.bytes,
  );
}

String? _realRhttpSkipReason() {
  final nativeLibDir =
      io.Platform.environment['FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR'];
  if (nativeLibDir == null || nativeLibDir.isEmpty) {
    return 'Set FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR to a directory containing librhttp.dylib to run real-rhttp tests.';
  }
  final nativeLib = io.File('$nativeLibDir/librhttp.dylib');
  if (!nativeLib.existsSync()) {
    return 'Missing librhttp.dylib under FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR=$nativeLibDir';
  }
  return null;
}
