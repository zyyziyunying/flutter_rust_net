import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/bytes_first_network_client.dart';
import 'package:flutter_rust_net/network/net_adapter.dart';
import 'package:flutter_rust_net/network/net_feature_flag.dart';
import 'package:flutter_rust_net/network/net_models.dart';
import 'package:flutter_rust_net/network/network_gateway.dart';
import 'package:flutter_rust_net/network/routing_policy.dart';
import 'package:flutter_rust_net/network/rust_adapter.dart';

void main() {
  group('BytesFirstNetworkClient', () {
    test('standard factory wires default adapters and keeps rust disabled', () {
      final client = BytesFirstNetworkClient.standard();

      expect(client.dioAdapter, isNotNull);
      expect(client.rustAdapter, isNotNull);
      expect(client.gateway.featureFlag.enableRustChannel, isFalse);
    });

    test('standard factory rejects rust enablement without ready adapter', () {
      expect(
        () => BytesFirstNetworkClient.standard(
          featureFlag: const NetFeatureFlag(enableRustChannel: true),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('standard factory accepts ready rust adapter when explicitly enabled',
        () {
      final rustAdapter = RustAdapter(
        initialized: true,
        requestHandler: (request) async => NetResponse(
          statusCode: 200,
          headers: const <String, String>{},
          bodyBytes: const <int>[],
          bridgeBytes: 0,
          channel: NetChannel.rust,
          fromFallback: false,
          costMs: 1,
        ),
      );

      final client = BytesFirstNetworkClient.standard(
        featureFlag: const NetFeatureFlag(enableRustChannel: true),
        rustAdapter: rustAdapter,
      );

      expect(client.gateway.featureFlag.enableRustChannel, isTrue);
      expect(client.rustAdapter, same(rustAdapter));
    });

    test('standardWithRust initializes rust adapter before returning',
        () async {
      final rustAdapter = RustAdapter(
        requestHandler: (request) async => NetResponse(
          statusCode: 200,
          headers: const <String, String>{},
          bodyBytes: const <int>[],
          bridgeBytes: 0,
          channel: NetChannel.rust,
          fromFallback: false,
          costMs: 1,
        ),
      );

      expect(rustAdapter.isReady, isFalse);

      final client = await BytesFirstNetworkClient.standardWithRust(
        rustAdapter: rustAdapter,
      );

      expect(rustAdapter.isReady, isTrue);
      expect(client.gateway.featureFlag.enableRustChannel, isTrue);
      expect(client.rustAdapter, same(rustAdapter));
    });

    test('request helper builds NetRequest from enum method', () async {
      NetRequest? capturedRequest;
      final client = BytesFirstNetworkClient(
        gateway: NetworkGateway(
          routingPolicy: const RoutingPolicy(),
          featureFlag: const NetFeatureFlag(enableRustChannel: false),
          dioAdapter: _FakeAdapter((request, {fromFallback = false}) async {
            capturedRequest = request;
            return NetResponse(
              statusCode: 200,
              headers: const <String, String>{},
              bodyBytes: const <int>[],
              bridgeBytes: 0,
              channel: NetChannel.dio,
              fromFallback: fromFallback,
              costMs: 1,
            );
          }),
          rustAdapter: _FakeAdapter((request, {fromFallback = false}) async {
            return NetResponse(
              statusCode: 200,
              headers: const <String, String>{},
              bodyBytes: const <int>[],
              bridgeBytes: 0,
              channel: NetChannel.rust,
              fromFallback: fromFallback,
              costMs: 1,
            );
          }),
        ),
      );

      await client.request(
        method: NetHttpMethod.post,
        url: 'https://example.com/feed',
        headers: const <String, String>{'x-request-id': 'abc'},
        body: const <String, String>{'ok': 'true'},
      );

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.method, 'POST');
      expect(capturedRequest!.httpMethod, NetHttpMethod.post);
      expect(capturedRequest!.url, 'https://example.com/feed');
      expect(capturedRequest!.headers['x-request-id'], 'abc');
    });

    test('decodes inline json bytes into model', () async {
      final payload = utf8.encode('{"id":1,"title":"harry"}');
      final client = _buildClient(
        NetResponse(
          statusCode: 200,
          headers: const {HttpHeaders.contentTypeHeader: 'application/json'},
          bodyBytes: payload,
          bridgeBytes: payload.length,
          channel: NetChannel.dio,
          fromFallback: false,
          costMs: 6,
        ),
      );

      final decoded = await client.requestJsonModel<Map<String, dynamic>>(
        const NetRequest(method: 'GET', url: 'https://example.com/feed'),
        mapper: (value) => Map<String, dynamic>.from(value as Map),
      );

      expect(decoded.decoded['id'], 1);
      expect(decoded.decoded['title'], 'harry');
      expect(decoded.bodyBytes.length, payload.length);
      expect(decoded.metrics.bridgeBytes, payload.length);
      expect(decoded.metrics.materializedBytes, payload.length);
      expect(decoded.rawResponse.routeReason, 'rust_disabled');
    });

    test('materializes file body and keeps bridge bytes at zero', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'bytes-first-client-test',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File('${tempDir.path}/response.json');
      await file.writeAsString('{"ok":true}');

      final client = _buildClient(
        NetResponse(
          statusCode: 200,
          headers: const {HttpHeaders.contentTypeHeader: 'application/json'},
          bodyFilePath: file.path,
          bridgeBytes: 0,
          channel: NetChannel.dio,
          fromFallback: false,
          costMs: 4,
        ),
      );

      final decoded = await client.requestDecoded<String>(
        const NetRequest(method: 'GET', url: 'https://example.com/large'),
        decoder: const Utf8BodyDecoder(),
      );

      expect(decoded.decoded, '{"ok":true}');
      expect(decoded.bodyBytes.length, greaterThan(0));
      expect(decoded.metrics.bridgeBytes, 0);
      expect(decoded.metrics.materializedBytes, decoded.bodyBytes.length);
      expect(await file.exists(), isFalse);
    });

    test('deletes materialized file when decoder throws', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'bytes-first-client-test',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File('${tempDir.path}/response.json');
      await file.writeAsString('{"ok":true}');

      final client = _buildClient(
        NetResponse(
          statusCode: 200,
          headers: const {HttpHeaders.contentTypeHeader: 'application/json'},
          bodyFilePath: file.path,
          bridgeBytes: 0,
          channel: NetChannel.rust,
          fromFallback: false,
          costMs: 4,
        ),
      );

      await expectLater(
        client.requestDecoded<String>(
          const NetRequest(method: 'GET', url: 'https://example.com/large'),
          decoder: const _ThrowingDecoder(),
        ),
        throwsA(isA<StateError>()),
      );
      expect(await file.exists(), isFalse);
    });

    test('rejects non-json content type when decoder requires json', () async {
      final payload = utf8.encode('{"ok":true}');
      final client = _buildClient(
        NetResponse(
          statusCode: 200,
          headers: const {HttpHeaders.contentTypeHeader: 'text/plain'},
          bodyBytes: payload,
          bridgeBytes: payload.length,
          channel: NetChannel.dio,
          fromFallback: false,
          costMs: 3,
        ),
      );

      await expectLater(
        client.requestJsonObject(
          const NetRequest(method: 'GET', url: 'https://example.com/plain'),
          requireJsonContentType: true,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

BytesFirstNetworkClient _buildClient(NetResponse response) {
  final gateway = NetworkGateway(
    routingPolicy: const RoutingPolicy(),
    featureFlag: const NetFeatureFlag(enableRustChannel: false),
    dioAdapter: _FakeAdapter(
      (request, {fromFallback = false}) async => response.withMeta(
        fromFallback: fromFallback,
        channel: NetChannel.dio,
      ),
    ),
    rustAdapter: _FakeAdapter(
      (request, {fromFallback = false}) async => response.withMeta(
        fromFallback: fromFallback,
        channel: NetChannel.rust,
      ),
    ),
  );
  return BytesFirstNetworkClient(gateway: gateway);
}

class _FakeAdapter implements NetAdapter {
  final Future<NetResponse> Function(NetRequest request, {bool fromFallback})
      _delegate;

  _FakeAdapter(this._delegate);

  @override
  bool get isReady => true;

  @override
  Future<NetResponse> request(NetRequest request, {bool fromFallback = false}) {
    return _delegate(request, fromFallback: fromFallback);
  }

  @override
  Future<String> startTransferTask(NetTransferTaskRequest request) async {
    return request.taskId;
  }

  @override
  Future<List<NetTransferEvent>> pollTransferEvents({int limit = 64}) async {
    return const [];
  }

  @override
  Future<bool> cancelTransferTask(String taskId) async {
    return false;
  }
}

class _ThrowingDecoder implements NetBodyDecoder<String> {
  const _ThrowingDecoder();

  @override
  Future<String> decode(
    Uint8List bodyBytes, {
    required NetResponse response,
  }) async {
    throw StateError('decode failed');
  }
}
