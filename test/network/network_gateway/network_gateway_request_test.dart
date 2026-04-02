import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/net_feature_flag.dart';
import 'package:flutter_rust_net/network/net_models.dart';
import 'package:flutter_rust_net/network/network_gateway.dart';
import 'package:flutter_rust_net/network/rhttp_adapter.dart';
import 'package:flutter_rust_net/network/routing_policy.dart';
import 'package:rhttp/rhttp.dart' as rhttp;

import 'network_gateway_test_helpers.dart';

void main() {
  group('NetworkGateway.request', () {
    test(
      'routes request through rhttp adapter and keeps rust compatibility metadata',
      () async {
        var dioCalls = 0;
        RhttpAdapterRequest? capturedRequest;

        final dio = FakeNetAdapter((request, {fromFallback = false}) async {
          dioCalls += 1;
          return okResponse(
            channel: NetChannel.dio,
            fromFallback: fromFallback,
          );
        });
        final rust = RhttpAdapter(
          requestHandler: (request) async {
            capturedRequest = request;
            return RhttpAdapterResponse(
              statusCode: 200,
              headers: const [('content-type', 'application/json')],
              bodyBytes: Uint8List.fromList(const [123, 125]),
            );
          },
        );

        final gateway = NetworkGateway(
          routingPolicy: const RoutingPolicy(),
          featureFlag: const NetFeatureFlag(enableRustChannel: true),
          dioAdapter: dio,
          rustAdapter: rust,
        );

        final response = await gateway.request(
          const NetRequest(
            method: 'GET',
            url: 'users/me',
            baseUrl: 'https://api.example.com/v2',
          ),
        );

        expect(dioCalls, 0);
        expect(capturedRequest, isNotNull);
        expect(capturedRequest!.url, 'https://api.example.com/v2/users/me');
        expect(response.channel, NetChannel.rust);
        expect(response.fromFallback, isFalse);
        expect(response.routeReason, 'rust_enabled');
        expect(response.requestId, isNotNull);
      },
    );

    test('falls back to dio when rhttp adapter throws timeout', () async {
      var dioCalls = 0;

      final dio = FakeNetAdapter((request, {fromFallback = false}) async {
        dioCalls += 1;
        return okResponse(channel: NetChannel.dio, fromFallback: fromFallback);
      });
      final rust = RhttpAdapter(
        requestHandler: (request) async {
          throw rhttp.RhttpTimeoutException(_toRhttpRequest(request));
        },
      );

      final gateway = NetworkGateway(
        routingPolicy: const RoutingPolicy(),
        featureFlag: const NetFeatureFlag(
          enableRustChannel: true,
          enableFallback: true,
        ),
        dioAdapter: dio,
        rustAdapter: rust,
      );

      final response = await gateway.request(
        const NetRequest(method: 'GET', url: 'https://example.com/a'),
      );

      expect(dioCalls, 1);
      expect(response.channel, NetChannel.dio);
      expect(response.fromFallback, isTrue);
      expect(response.fallbackReason, NetErrorCode.timeout.name);
      expect(response.routeReason, 'rust_enabled -> fallback_dio');
      expect(response.fallbackError?.channel, NetChannel.rust);
      expect(response.fallbackError?.code, NetErrorCode.timeout);
    });

    test(
      'routes to dio directly when rhttp client is unavailable before first request',
      () async {
        var dioCalls = 0;

        final dio = FakeNetAdapter((request, {fromFallback = false}) async {
          dioCalls += 1;
          return okResponse(
            channel: NetChannel.dio,
            fromFallback: fromFallback,
          );
        });
        final rust = RhttpAdapter(
          clientFactory: (settings) async {
            throw StateError('native client unavailable');
          },
        );

        final gateway = NetworkGateway(
          routingPolicy: const RoutingPolicy(),
          featureFlag: const NetFeatureFlag(
            enableRustChannel: true,
            enableFallback: true,
          ),
          dioAdapter: dio,
          rustAdapter: rust,
        );

        final response = await gateway.request(
          const NetRequest(
            method: 'GET',
            url: 'https://example.com/a',
            forceChannel: NetChannel.rust,
          ),
        );

        expect(rust.isReady, isFalse);
        expect(dioCalls, 1);
        expect(response.channel, NetChannel.dio);
        expect(response.fromFallback, isFalse);
        expect(response.routeReason, 'force_channel -> rust_not_ready_dio');
        expect(response.fallbackReason, isNull);
        expect(response.fallbackError, isNull);
      },
    );

    test('uses dio directly when policy chooses dio', () async {
      var dioCalls = 0;
      var rustCalls = 0;

      final dio = FakeNetAdapter((request, {fromFallback = false}) async {
        dioCalls += 1;
        return okResponse(channel: NetChannel.dio, fromFallback: fromFallback);
      });
      final rust = FakeNetAdapter((request, {fromFallback = false}) async {
        rustCalls += 1;
        return okResponse(channel: NetChannel.rust, fromFallback: fromFallback);
      });

      final gateway = NetworkGateway(
        routingPolicy: const RoutingPolicy(),
        featureFlag: const NetFeatureFlag(enableRustChannel: false),
        dioAdapter: dio,
        rustAdapter: rust,
      );

      final response = await gateway.request(
        const NetRequest(method: 'GET', url: 'https://example.com/a'),
      );

      expect(dioCalls, 1);
      expect(rustCalls, 0);
      expect(response.channel, NetChannel.dio);
      expect(response.fromFallback, isFalse);
      expect(response.routeReason, 'rust_disabled');
    });

    test('routes to dio directly when rust adapter is not ready', () async {
      var dioCalls = 0;
      var rustCalls = 0;
      bool? dioFromFallback;

      final dio = FakeNetAdapter((request, {fromFallback = false}) async {
        dioCalls += 1;
        dioFromFallback = fromFallback;
        return okResponse(channel: NetChannel.dio, fromFallback: fromFallback);
      });
      final rust = FakeNetAdapter((request, {fromFallback = false}) async {
        rustCalls += 1;
        throw NetException.infrastructure(
          message: 'engine not ready',
          channel: NetChannel.rust,
        );
      }, isReady: false);

      final gateway = NetworkGateway(
        routingPolicy: const RoutingPolicy(),
        featureFlag: const NetFeatureFlag(
          enableRustChannel: true,
          enableFallback: true,
        ),
        dioAdapter: dio,
        rustAdapter: rust,
      );

      final response = await gateway.request(
        const NetRequest(
          method: 'GET',
          url: 'https://example.com/a',
          forceChannel: NetChannel.rust,
        ),
      );

      expect(rustCalls, 0);
      expect(dioCalls, 1);
      expect(dioFromFallback, isFalse);
      expect(response.channel, NetChannel.dio);
      expect(response.fromFallback, isFalse);
      expect(response.routeReason, 'force_channel -> rust_not_ready_dio');
      expect(response.fallbackReason, isNull);
    });

    test(
      'falls back to dio when rust infrastructure error is eligible',
      () async {
        var dioCalls = 0;
        var rustCalls = 0;
        bool? dioFromFallback;

        final dio = FakeNetAdapter((request, {fromFallback = false}) async {
          dioCalls += 1;
          dioFromFallback = fromFallback;
          return okResponse(
            channel: NetChannel.dio,
            fromFallback: fromFallback,
          );
        });
        final rust = FakeNetAdapter((request, {fromFallback = false}) async {
          rustCalls += 1;
          throw NetException.infrastructure(
            message: 'engine not ready',
            channel: NetChannel.rust,
            requestId: 'rust-fallback-1',
          );
        });

        final gateway = NetworkGateway(
          routingPolicy: const RoutingPolicy(),
          featureFlag: const NetFeatureFlag(
            enableRustChannel: true,
            enableFallback: true,
          ),
          dioAdapter: dio,
          rustAdapter: rust,
        );

        final response = await gateway.request(
          const NetRequest(
            method: 'GET',
            url: 'https://example.com/a',
            forceChannel: NetChannel.rust,
          ),
        );

        expect(rustCalls, 1);
        expect(dioCalls, 1);
        expect(dioFromFallback, isTrue);
        expect(response.channel, NetChannel.dio);
        expect(response.fromFallback, isTrue);
        expect(response.fallbackReason, NetErrorCode.infrastructure.name);
        expect(response.routeReason, 'force_channel -> fallback_dio');
        expect(response.requestId, 'dio-request');
        expect(response.fallbackError, isNotNull);
        expect(response.fallbackError?.requestId, 'rust-fallback-1');
        expect(response.fallbackError?.code, NetErrorCode.infrastructure);
        expect(response.fallbackError?.channel, NetChannel.rust);
      },
    );

    test('resolves request baseUrl before rust fallback to dio', () async {
      NetRequest? rustRequest;
      NetRequest? dioRequest;

      final dio = FakeNetAdapter((request, {fromFallback = false}) async {
        dioRequest = request;
        return okResponse(channel: NetChannel.dio, fromFallback: fromFallback);
      });
      final rust = FakeNetAdapter((request, {fromFallback = false}) async {
        rustRequest = request;
        throw NetException.infrastructure(
          message: 'rust transport failed',
          channel: NetChannel.rust,
        );
      });

      final gateway = NetworkGateway(
        routingPolicy: const RoutingPolicy(),
        featureFlag: const NetFeatureFlag(
          enableRustChannel: true,
          enableFallback: true,
        ),
        dioAdapter: dio,
        rustAdapter: rust,
      );

      final response = await gateway.request(
        const NetRequest(
          method: 'GET',
          url: 'users/me',
          baseUrl: 'https://api.example.com/v2',
          forceChannel: NetChannel.rust,
        ),
      );

      expect(rustRequest, isNotNull);
      expect(dioRequest, isNotNull);
      expect(rustRequest!.url, 'https://api.example.com/v2/users/me');
      expect(dioRequest!.url, 'https://api.example.com/v2/users/me');
      expect(response.channel, NetChannel.dio);
      expect(response.fromFallback, isTrue);
      expect(response.routeReason, 'force_channel -> fallback_dio');
    });

    test('does not fallback when fallback switch is disabled', () async {
      final dio = FakeNetAdapter((request, {fromFallback = false}) async {
        return okResponse(channel: NetChannel.dio, fromFallback: fromFallback);
      });
      final rust = FakeNetAdapter((request, {fromFallback = false}) async {
        throw NetException.infrastructure(
          message: 'engine not ready',
          channel: NetChannel.rust,
        );
      });

      final gateway = NetworkGateway(
        routingPolicy: const RoutingPolicy(),
        featureFlag: const NetFeatureFlag(
          enableRustChannel: true,
          enableFallback: false,
        ),
        dioAdapter: dio,
        rustAdapter: rust,
      );

      expect(
        gateway.request(
          const NetRequest(
            method: 'GET',
            url: 'https://example.com/a',
            forceChannel: NetChannel.rust,
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
    });

    test('does not fallback for non-eligible rust errors', () async {
      var dioCalls = 0;

      final dio = FakeNetAdapter((request, {fromFallback = false}) async {
        dioCalls += 1;
        return okResponse(channel: NetChannel.dio, fromFallback: fromFallback);
      });
      final rust = FakeNetAdapter((request, {fromFallback = false}) async {
        throw const NetException(
          code: NetErrorCode.http4xx,
          message: 'business error',
          channel: NetChannel.rust,
          fallbackEligible: false,
          statusCode: 400,
        );
      });

      final gateway = NetworkGateway(
        routingPolicy: const RoutingPolicy(),
        featureFlag: const NetFeatureFlag(
          enableRustChannel: true,
          enableFallback: true,
        ),
        dioAdapter: dio,
        rustAdapter: rust,
      );

      expect(
        gateway.request(
          const NetRequest(
            method: 'GET',
            url: 'https://example.com/a',
            forceChannel: NetChannel.rust,
          ),
        ),
        throwsA(
          isA<NetException>().having(
            (error) => error.code,
            'code',
            NetErrorCode.http4xx,
          ),
        ),
      );
      expect(dioCalls, 0);
    });

    test(
      'does not fallback for internal rust errors even when marked eligible',
      () async {
        var dioCalls = 0;

        final dio = FakeNetAdapter((request, {fromFallback = false}) async {
          dioCalls += 1;
          return okResponse(
            channel: NetChannel.dio,
            fromFallback: fromFallback,
          );
        });
        final rust = FakeNetAdapter((request, {fromFallback = false}) async {
          throw const NetException(
            code: NetErrorCode.internal,
            message: 'unknown rust failure',
            channel: NetChannel.rust,
            fallbackEligible: true,
          );
        });

        final gateway = NetworkGateway(
          routingPolicy: const RoutingPolicy(),
          featureFlag: const NetFeatureFlag(
            enableRustChannel: true,
            enableFallback: true,
          ),
          dioAdapter: dio,
          rustAdapter: rust,
        );

        expect(
          gateway.request(
            const NetRequest(
              method: 'GET',
              url: 'https://example.com/a',
              forceChannel: NetChannel.rust,
            ),
          ),
          throwsA(
            isA<NetException>().having(
              (error) => error.code,
              'code',
              NetErrorCode.internal,
            ),
          ),
        );
        expect(dioCalls, 0);
      },
    );

    test(
      'does not fallback for non-idempotent request without idempotency key',
      () async {
        var dioCalls = 0;

        final dio = FakeNetAdapter((request, {fromFallback = false}) async {
          dioCalls += 1;
          return okResponse(
            channel: NetChannel.dio,
            fromFallback: fromFallback,
          );
        });
        final rust = FakeNetAdapter((request, {fromFallback = false}) async {
          throw NetException.infrastructure(
            message: 'rust transient failure',
            channel: NetChannel.rust,
          );
        });

        final gateway = NetworkGateway(
          routingPolicy: const RoutingPolicy(),
          featureFlag: const NetFeatureFlag(
            enableRustChannel: true,
            enableFallback: true,
          ),
          dioAdapter: dio,
          rustAdapter: rust,
        );

        expect(
          gateway.request(
            const NetRequest(
              method: 'POST',
              url: 'https://example.com/a',
              forceChannel: NetChannel.rust,
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
        expect(dioCalls, 0);
      },
    );

    test(
      'allows fallback for non-idempotent request with idempotency key',
      () async {
        var dioCalls = 0;

        final dio = FakeNetAdapter((request, {fromFallback = false}) async {
          dioCalls += 1;
          return okResponse(
            channel: NetChannel.dio,
            fromFallback: fromFallback,
          );
        });
        final rust = FakeNetAdapter((request, {fromFallback = false}) async {
          throw NetException.infrastructure(
            message: 'rust transient failure',
            channel: NetChannel.rust,
          );
        });

        final gateway = NetworkGateway(
          routingPolicy: const RoutingPolicy(),
          featureFlag: const NetFeatureFlag(
            enableRustChannel: true,
            enableFallback: true,
          ),
          dioAdapter: dio,
          rustAdapter: rust,
        );

        final response = await gateway.request(
          const NetRequest(
            method: 'POST',
            url: 'https://example.com/a',
            headers: {'Idempotency-Key': 'retry-safe-1'},
            forceChannel: NetChannel.rust,
          ),
        );

        expect(dioCalls, 1);
        expect(response.channel, NetChannel.dio);
        expect(response.fromFallback, isTrue);
        expect(response.fallbackReason, NetErrorCode.infrastructure.name);
      },
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
