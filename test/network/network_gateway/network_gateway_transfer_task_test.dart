import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/net_feature_flag.dart';
import 'package:flutter_rust_net/network/net_models.dart';
import 'package:flutter_rust_net/network/network_gateway.dart';
import 'package:flutter_rust_net/network/routing_policy.dart';

import 'network_gateway_test_helpers.dart';

void main() {
  group('NetworkGateway.transferTask', () {
    test(
      'routes transfer task to dio in v1 even when rust feature is enabled',
      () async {
        var dioStartCalls = 0;
        var rustStartCalls = 0;
        var dioCancelCalls = 0;
        var rustCancelCalls = 0;

        final dio = FakeNetAdapter(
          (request, {fromFallback = false}) async {
            return okResponse(
              channel: NetChannel.dio,
              fromFallback: fromFallback,
            );
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
        final rust = FakeNetAdapter(
          (request, {fromFallback = false}) async {
            return okResponse(
              channel: NetChannel.rust,
              fromFallback: fromFallback,
            );
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
            taskId: 'task-dio-only-1',
            kind: NetTransferKind.download,
            url: 'https://example.com/file.bin',
            localPath: '/tmp/file.bin',
          ),
        );

        final canceled = await gateway.cancelTransferTask('task-dio-only-1');

        expect(startResult.taskId, 'task-dio-only-1');
        expect(startResult.channel, NetChannel.dio);
        expect(startResult.routeReason, 'rust_enabled -> transfer_dio_only');
        expect(startResult.fromFallback, isFalse);
        expect(canceled, isTrue);
        expect(dioStartCalls, 1);
        expect(rustStartCalls, 0);
        expect(dioCancelCalls, 1);
        expect(rustCancelCalls, 0);
      },
    );

    test('honors forceChannel dio for transfer tasks', () async {
      var dioStartCalls = 0;
      var rustStartCalls = 0;

      final dio = FakeNetAdapter(
        (request, {fromFallback = false}) async {
          return okResponse(
            channel: NetChannel.dio,
            fromFallback: fromFallback,
          );
        },
        startTransferDelegate: (request) async {
          dioStartCalls += 1;
          return request.taskId;
        },
      );
      final rust = FakeNetAdapter(
        (request, {fromFallback = false}) async {
          return okResponse(
            channel: NetChannel.rust,
            fromFallback: fromFallback,
          );
        },
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
          taskId: 'task-force-dio-1',
          kind: NetTransferKind.download,
          url: 'https://example.com/file.bin',
          localPath: '/tmp/file.bin',
          forceChannel: NetChannel.dio,
        ),
      );

      expect(startResult.channel, NetChannel.dio);
      expect(startResult.routeReason, 'force_channel');
      expect(dioStartCalls, 1);
      expect(rustStartCalls, 0);
    });

    test(
      'rejects forceChannel rust for transfer tasks in v1 without probing adapters',
      () async {
        var dioStartCalls = 0;
        var rustStartCalls = 0;

        final dio = FakeNetAdapter(
          (request, {fromFallback = false}) async {
            return okResponse(
              channel: NetChannel.dio,
              fromFallback: fromFallback,
            );
          },
          startTransferDelegate: (request) async {
            dioStartCalls += 1;
            return request.taskId;
          },
        );
        final rust = FakeNetAdapter(
          (request, {fromFallback = false}) async {
            return okResponse(
              channel: NetChannel.rust,
              fromFallback: fromFallback,
            );
          },
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

        await expectLater(
          gateway.startTransferTask(
            const NetTransferTaskRequest(
              taskId: 'task-force-rust-unsupported-1',
              kind: NetTransferKind.download,
              url: 'https://example.com/file.bin',
              localPath: '/tmp/file.bin',
              forceChannel: NetChannel.rust,
            ),
          ),
          throwsA(
            isA<NetException>()
                .having(
                  (error) => error.code,
                  'code',
                  NetErrorCode.infrastructure,
                )
                .having((error) => error.channel, 'channel', NetChannel.rust)
                .having(
                  (error) => error.fallbackEligible,
                  'fallbackEligible',
                  isFalse,
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains('Transfer operations do not support NetChannel.rust'),
                ),
          ),
        );

        expect(dioStartCalls, 0);
        expect(rustStartCalls, 0);
      },
    );

    test('does not fallback transfer start errors to rust in v1', () async {
      var dioStartCalls = 0;
      var rustStartCalls = 0;

      final dio = FakeNetAdapter(
        (request, {fromFallback = false}) async {
          return okResponse(
            channel: NetChannel.dio,
            fromFallback: fromFallback,
          );
        },
        startTransferDelegate: (request) async {
          dioStartCalls += 1;
          throw NetException.infrastructure(
            message: 'dio transfer start failed',
            channel: NetChannel.dio,
            requestId: 'dio-transfer-1',
          );
        },
      );
      final rust = FakeNetAdapter(
        (request, {fromFallback = false}) async {
          return okResponse(
            channel: NetChannel.rust,
            fromFallback: fromFallback,
          );
        },
        startTransferDelegate: (request) async {
          rustStartCalls += 1;
          return request.taskId;
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

      await expectLater(
        gateway.startTransferTask(
          const NetTransferTaskRequest(
            taskId: 'task-no-transfer-fallback-1',
            kind: NetTransferKind.upload,
            url: 'https://example.com/upload',
            method: 'POST',
            headers: {'Idempotency-Key': 'upload-safe-1'},
            localPath: '/tmp/source.bin',
          ),
        ),
        throwsA(
          isA<NetException>()
              .having(
                (error) => error.code,
                'code',
                NetErrorCode.infrastructure,
              )
              .having((error) => error.channel, 'channel', NetChannel.dio)
              .having((error) => error.requestId, 'requestId', 'dio-transfer-1'),
        ),
      );

      expect(dioStartCalls, 1);
      expect(rustStartCalls, 0);
    });

    test('resolves transfer baseUrl before starting on dio', () async {
      NetTransferTaskRequest? dioRequest;
      var rustStartCalls = 0;

      final dio = FakeNetAdapter(
        (request, {fromFallback = false}) async {
          return okResponse(
            channel: NetChannel.dio,
            fromFallback: fromFallback,
          );
        },
        startTransferDelegate: (request) async {
          dioRequest = request;
          return request.taskId;
        },
      );
      final rust = FakeNetAdapter(
        (request, {fromFallback = false}) async {
          return okResponse(
            channel: NetChannel.rust,
            fromFallback: fromFallback,
          );
        },
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
          taskId: 'task-relative-transfer-1',
          kind: NetTransferKind.download,
          url: 'images/file.bin',
          baseUrl: 'https://cdn.example.com/root',
          localPath: '/tmp/file.bin',
        ),
      );

      expect(dioRequest, isNotNull);
      expect(dioRequest!.url, 'https://cdn.example.com/root/images/file.bin');
      expect(startResult.channel, NetChannel.dio);
      expect(startResult.routeReason, 'rust_enabled -> transfer_dio_only');
      expect(rustStartCalls, 0);
    });
  });
}
