import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/net_adapter.dart';
import 'package:flutter_rust_net/network/net_feature_flag.dart';
import 'package:flutter_rust_net/network/net_models.dart';
import 'package:flutter_rust_net/network/network_gateway.dart';
import 'package:flutter_rust_net/network/routing_policy.dart';

void main() {
  group('NetworkGateway', () {
    test('uses dio directly when policy chooses dio', () async {
      var dioCalls = 0;
      var rustCalls = 0;

      final dio = _FakeAdapter((request, {fromFallback = false}) async {
        dioCalls += 1;
        return _ok(channel: NetChannel.dio, fromFallback: fromFallback);
      });
      final rust = _FakeAdapter((request, {fromFallback = false}) async {
        rustCalls += 1;
        return _ok(channel: NetChannel.rust, fromFallback: fromFallback);
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

      final dio = _FakeAdapter((request, {fromFallback = false}) async {
        dioCalls += 1;
        dioFromFallback = fromFallback;
        return _ok(channel: NetChannel.dio, fromFallback: fromFallback);
      });
      final rust = _FakeAdapter((request, {fromFallback = false}) async {
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

        final dio = _FakeAdapter((request, {fromFallback = false}) async {
          dioCalls += 1;
          dioFromFallback = fromFallback;
          return _ok(channel: NetChannel.dio, fromFallback: fromFallback);
        });
        final rust = _FakeAdapter((request, {fromFallback = false}) async {
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

    test('does not fallback when fallback switch is disabled', () async {
      final dio = _FakeAdapter((request, {fromFallback = false}) async {
        return _ok(channel: NetChannel.dio, fromFallback: fromFallback);
      });
      final rust = _FakeAdapter((request, {fromFallback = false}) async {
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

      final dio = _FakeAdapter((request, {fromFallback = false}) async {
        dioCalls += 1;
        return _ok(channel: NetChannel.dio, fromFallback: fromFallback);
      });
      final rust = _FakeAdapter((request, {fromFallback = false}) async {
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

        final dio = _FakeAdapter((request, {fromFallback = false}) async {
          dioCalls += 1;
          return _ok(channel: NetChannel.dio, fromFallback: fromFallback);
        });
        final rust = _FakeAdapter((request, {fromFallback = false}) async {
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

        final dio = _FakeAdapter((request, {fromFallback = false}) async {
          dioCalls += 1;
          return _ok(channel: NetChannel.dio, fromFallback: fromFallback);
        });
        final rust = _FakeAdapter((request, {fromFallback = false}) async {
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

        final dio = _FakeAdapter((request, {fromFallback = false}) async {
          dioCalls += 1;
          return _ok(channel: NetChannel.dio, fromFallback: fromFallback);
        });
        final rust = _FakeAdapter((request, {fromFallback = false}) async {
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

    test(
      'routes transfer task to rust and cancels on tracked channel',
      () async {
        var dioStartCalls = 0;
        var rustStartCalls = 0;
        var dioCancelCalls = 0;
        var rustCancelCalls = 0;

        final dio = _FakeAdapter(
          (request, {fromFallback = false}) async {
            return _ok(channel: NetChannel.dio, fromFallback: fromFallback);
          },
          startTransferDelegate: (request) async {
            dioStartCalls += 1;
            return request.taskId;
          },
          cancelTransferDelegate: (taskId) async {
            dioCancelCalls += 1;
            return true;
          },
        );
        final rust = _FakeAdapter(
          (request, {fromFallback = false}) async {
            return _ok(channel: NetChannel.rust, fromFallback: fromFallback);
          },
          startTransferDelegate: (request) async {
            rustStartCalls += 1;
            return request.taskId;
          },
          cancelTransferDelegate: (taskId) async {
            rustCancelCalls += 1;
            return true;
          },
        );

        final gateway = NetworkGateway(
          routingPolicy: const RoutingPolicy(),
          featureFlag: const NetFeatureFlag(enableRustChannel: true),
          dioAdapter: dio,
          rustAdapter: rust,
        );

        final startResult = await gateway.startTransferTask(
          const NetTransferTaskRequest(
            taskId: 'task-rust-1',
            kind: NetTransferKind.download,
            url: 'https://example.com/file.bin',
            localPath: '/tmp/file.bin',
          ),
        );

        final canceled = await gateway.cancelTransferTask('task-rust-1');

        expect(startResult.taskId, 'task-rust-1');
        expect(startResult.channel, NetChannel.rust);
        expect(startResult.routeReason, 'transfer_task');
        expect(startResult.fromFallback, isFalse);
        expect(canceled, isTrue);
        expect(rustStartCalls, 1);
        expect(dioStartCalls, 0);
        expect(rustCancelCalls, 1);
        expect(dioCancelCalls, 0);
      },
    );

    test('routes transfer task to dio when rust is not ready', () async {
      var dioStartCalls = 0;
      var rustStartCalls = 0;

      final dio = _FakeAdapter(
        (request, {fromFallback = false}) async {
          return _ok(channel: NetChannel.dio, fromFallback: fromFallback);
        },
        startTransferDelegate: (request) async {
          dioStartCalls += 1;
          return request.taskId;
        },
      );
      final rust = _FakeAdapter(
        (request, {fromFallback = false}) async {
          return _ok(channel: NetChannel.rust, fromFallback: fromFallback);
        },
        isReady: false,
        startTransferDelegate: (request) async {
          rustStartCalls += 1;
          return request.taskId;
        },
      );

      final gateway = NetworkGateway(
        routingPolicy: const RoutingPolicy(),
        featureFlag: const NetFeatureFlag(enableRustChannel: true),
        dioAdapter: dio,
        rustAdapter: rust,
      );

      final startResult = await gateway.startTransferTask(
        const NetTransferTaskRequest(
          taskId: 'task-dio-1',
          kind: NetTransferKind.download,
          url: 'https://example.com/file.bin',
          localPath: '/tmp/file.bin',
          forceChannel: NetChannel.rust,
        ),
      );

      expect(startResult.channel, NetChannel.dio);
      expect(startResult.routeReason, 'force_channel -> rust_not_ready_dio');
      expect(startResult.fromFallback, isFalse);
      expect(rustStartCalls, 0);
      expect(dioStartCalls, 1);
    });

    test(
      'falls back to dio when rust transfer start fails and is eligible',
      () async {
        var dioStartCalls = 0;
        var rustStartCalls = 0;

        final dio = _FakeAdapter(
          (request, {fromFallback = false}) async {
            return _ok(channel: NetChannel.dio, fromFallback: fromFallback);
          },
          startTransferDelegate: (request) async {
            dioStartCalls += 1;
            return request.taskId;
          },
        );
        final rust = _FakeAdapter(
          (request, {fromFallback = false}) async {
            return _ok(channel: NetChannel.rust, fromFallback: fromFallback);
          },
          startTransferDelegate: (request) async {
            rustStartCalls += 1;
            throw NetException.infrastructure(
              message: 'rust transfer start failed',
              channel: NetChannel.rust,
              requestId: 'rust-transfer-fallback-1',
            );
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

        final startResult = await gateway.startTransferTask(
          const NetTransferTaskRequest(
            taskId: 'task-fallback-1',
            kind: NetTransferKind.upload,
            url: 'https://example.com/upload',
            method: 'POST',
            headers: {'Idempotency-Key': 'upload-safe-1'},
            localPath: '/tmp/source.bin',
            forceChannel: NetChannel.rust,
          ),
        );

        expect(startResult.channel, NetChannel.dio);
        expect(startResult.fromFallback, isTrue);
        expect(startResult.fallbackReason, NetErrorCode.infrastructure.name);
        expect(startResult.routeReason, 'force_channel -> fallback_dio');
        expect(startResult.fallbackError, isNotNull);
        expect(
          startResult.fallbackError?.requestId,
          'rust-transfer-fallback-1',
        );
        expect(startResult.fallbackError?.code, NetErrorCode.infrastructure);
        expect(rustStartCalls, 1);
        expect(dioStartCalls, 1);
      },
    );
  });
}

class _FakeAdapter implements NetAdapter {
  final bool _isReady;
  final Future<NetResponse> Function(NetRequest request, {bool fromFallback})
  _delegate;
  final Future<String> Function(NetTransferTaskRequest request)
  _startTransferDelegate;
  final Future<List<NetTransferEvent>> Function({int limit})
  _pollTransferDelegate;
  final Future<bool> Function(String taskId) _cancelTransferDelegate;

  _FakeAdapter(
    this._delegate, {
    bool isReady = true,
    Future<String> Function(NetTransferTaskRequest request)?
    startTransferDelegate,
    Future<List<NetTransferEvent>> Function({int limit})? pollTransferDelegate,
    Future<bool> Function(String taskId)? cancelTransferDelegate,
  }) : _isReady = isReady,
       _startTransferDelegate = startTransferDelegate ?? _defaultStartTransfer,
       _pollTransferDelegate = pollTransferDelegate ?? _defaultPollTransfer,
       _cancelTransferDelegate = cancelTransferDelegate ?? _defaultCancel;

  @override
  bool get isReady => _isReady;

  @override
  Future<NetResponse> request(NetRequest request, {bool fromFallback = false}) {
    return _delegate(request, fromFallback: fromFallback);
  }

  @override
  Future<String> startTransferTask(NetTransferTaskRequest request) {
    return _startTransferDelegate(request);
  }

  @override
  Future<List<NetTransferEvent>> pollTransferEvents({int limit = 64}) {
    return _pollTransferDelegate(limit: limit);
  }

  @override
  Future<bool> cancelTransferTask(String taskId) {
    return _cancelTransferDelegate(taskId);
  }

  static Future<String> _defaultStartTransfer(
    NetTransferTaskRequest request,
  ) async {
    return request.taskId;
  }

  static Future<List<NetTransferEvent>> _defaultPollTransfer({
    int limit = 64,
  }) async {
    return const [];
  }

  static Future<bool> _defaultCancel(String taskId) async {
    return false;
  }
}

NetResponse _ok({
  required NetChannel channel,
  required bool fromFallback,
  String? requestId,
}) {
  return NetResponse(
    statusCode: 200,
    headers: const {'content-type': 'application/json'},
    bodyBytes: const [123, 125],
    channel: channel,
    fromFallback: fromFallback,
    costMs: 1,
    requestId: requestId ?? '${channel.name}-request',
  );
}
