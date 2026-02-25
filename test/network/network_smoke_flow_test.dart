import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/dio_adapter.dart';
import 'package:flutter_rust_net/network/net_feature_flag.dart';
import 'package:flutter_rust_net/network/net_models.dart';
import 'package:flutter_rust_net/network/network_gateway.dart';
import 'package:flutter_rust_net/network/routing_policy.dart';
import 'package:flutter_rust_net/network/rust_adapter.dart';

void main() {
  late HttpServer server;
  late String baseUrl;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';
    _log('setUp', 'local server started at $baseUrl');

    server.listen((request) async {
      _log('server', '${request.method} ${request.uri.path}');
      if (request.method == 'GET' && request.uri.path == '/todos/1') {
        final payload = utf8.encode(
          jsonEncode({'id': 1, 'title': 'network-smoke', 'ok': true}),
        );
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..add(payload);
        await request.response.close();
        _log('server', 'respond 200 /todos/1 (${payload.length} bytes)');
        return;
      }

      request.response
        ..statusCode = HttpStatus.notFound
        ..write('not found');
      await request.response.close();
      _log('server', 'respond 404 ${request.uri.path}');
    });
  });

  tearDown(() async {
    _log('tearDown', 'closing server');
    await server.close(force: true);
  });

  test('real request succeeds on dio channel', () async {
    _log('case:dio', 'build gateway with rust disabled');
    final gateway = NetworkGateway(
      routingPolicy: const RoutingPolicy(),
      featureFlag: const NetFeatureFlag(enableRustChannel: false),
      dioAdapter: DioAdapter(),
      rustAdapter: RustAdapter(),
    );

    _log('case:dio', 'send GET $baseUrl/todos/1');
    final response = await gateway.request(
      NetRequest(method: 'GET', url: '$baseUrl/todos/1'),
    );
    final body = utf8.decode(response.bodyBytes ?? const []);
    _log('case:dio', _describe(response, bodyPreview: body));

    expect(response.statusCode, 200);
    expect(response.channel, NetChannel.dio);
    expect(response.fromFallback, isFalse);
    expect(response.routeReason, 'rust_disabled');
    expect(body, contains('network-smoke'));
  });

  test('rust not ready routes directly to dio via readiness gate', () async {
    _log('case:fallback', 'build gateway with rust enabled + fallback');
    final gateway = NetworkGateway(
      routingPolicy: const RoutingPolicy(),
      featureFlag: const NetFeatureFlag(
        enableRustChannel: true,
        enableFallback: true,
      ),
      dioAdapter: DioAdapter(),
      rustAdapter: RustAdapter(initialized: false),
    );

    _log(
      'case:fallback',
      'send force rust GET $baseUrl/todos/1 (expect readiness-gated dio)',
    );
    final response = await gateway.request(
      NetRequest(
        method: 'GET',
        url: '$baseUrl/todos/1',
        forceChannel: NetChannel.rust,
      ),
    );
    _log('case:fallback', _describe(response));

    expect(response.statusCode, 200);
    expect(response.channel, NetChannel.dio);
    expect(response.fromFallback, isFalse);
    expect(response.routeReason, 'force_channel -> rust_not_ready_dio');
    expect(response.fallbackReason, isNull);
  });
}

void _log(String scope, String message) {
  debugPrint('[network-smoke][$scope] $message');
}

String _describe(NetResponse response, {String? bodyPreview}) {
  final preview = bodyPreview == null
      ? '-'
      : (bodyPreview.length > 120
            ? '${bodyPreview.substring(0, 120)}...'
            : bodyPreview);
  return [
    'status=${response.statusCode}',
    'channel=${response.channel.name}',
    'fromFallback=${response.fromFallback}',
    'routeReason=${response.routeReason ?? '-'}',
    'fallbackReason=${response.fallbackReason ?? '-'}',
    'costMs=${response.costMs}',
    'bodyPreview=$preview',
  ].join(', ');
}
