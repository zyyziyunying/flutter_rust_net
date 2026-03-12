import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/net_feature_flag.dart';
import 'package:flutter_rust_net/network/net_models.dart';
import 'package:flutter_rust_net/network/network_gateway.dart';
import 'package:flutter_rust_net/network/routing_policy.dart';

import 'network_gateway_test_helpers.dart';

void main() {
  group('NetworkGateway.transferTask', () {
    test(
      'routes transfer task to rust and cancels on tracked channel',
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
            taskId: 'task-rust-1',
            kind: NetTransferKind.download,
            url: 'https://example.com/file.bin',
            localPath: '/tmp/file.bin',
          ),
        );

        final canceled = await gateway.cancelTransferTask('task-rust-1');

        expect(startResult.taskId, 'task-rust-1');
        expect(startResult.channel, NetChannel.rust);
        expect(startResult.routeReason, 'rust_enabled');
        expect(startResult.fromFallback, isFalse);
        expect(canceled, isTrue);
        expect(rustStartCalls, 1);
        expect(dioStartCalls, 0);
        expect(rustCancelCalls, 1);
        expect(dioCancelCalls, 0);
      },
    );

    test(
      'preserves tracked cancel error and does not probe the other adapter',
      () async {
        var dioCancelCalls = 0;
        var rustCancelCalls = 0;

        final dio = FakeNetAdapter(
          (request, {fromFallback = false}) async {
            return okResponse(
              channel: NetChannel.dio,
              fromFallback: fromFallback,
            );
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
          cancelTransferDelegate: (taskId) async {
            rustCancelCalls += 1;
            if (rustCancelCalls == 1) {
              throw NetException.infrastructure(
                message: 'rust cancel transport failure',
                channel: NetChannel.rust,
              );
            }
            return true;
          },
        );

        final gateway = NetworkGateway(
          routingPolicy: const RoutingPolicy(),
          featureFlag: const NetFeatureFlag(enableRustChannel: true),
          dioAdapter: dio,
          rustAdapter: rust,
        );

        await gateway.startTransferTask(
          const NetTransferTaskRequest(
            taskId: 'task-rust-cancel-error-1',
            kind: NetTransferKind.download,
            url: 'https://example.com/file.bin',
            localPath: '/tmp/file.bin',
          ),
        );

        await expectLater(
          gateway.cancelTransferTask('task-rust-cancel-error-1'),
          throwsA(
            isA<NetException>()
                .having(
                  (error) => error.code,
                  'code',
                  NetErrorCode.infrastructure,
                )
                .having((error) => error.channel, 'channel', NetChannel.rust),
          ),
        );

        final canceled = await gateway.cancelTransferTask(
          'task-rust-cancel-error-1',
        );

        expect(canceled, isTrue);
        expect(rustCancelCalls, 2);
        expect(dioCancelCalls, 0);
      },
    );

    test('routes transfer task to dio when rust is not ready', () async {
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

    test(
      'does not fallback resume download transfer to dio when rust start fails',
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
            throw NetException.infrastructure(
              message: 'rust transfer start failed',
              channel: NetChannel.rust,
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

        await expectLater(
          gateway.startTransferTask(
            const NetTransferTaskRequest(
              taskId: 'task-resume-no-fallback',
              kind: NetTransferKind.download,
              url: 'https://example.com/file.bin',
              localPath: '/tmp/file.bin',
              resumeFrom: 128,
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
        expect(rustStartCalls, 1);
        expect(dioStartCalls, 0);
      },
    );

    test('does not fallback transfer upload without idempotency key', () async {
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
          throw NetException.infrastructure(
            message: 'rust transfer start failed',
            channel: NetChannel.rust,
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

      expect(
        gateway.startTransferTask(
          const NetTransferTaskRequest(
            taskId: 'task-upload-no-idempotency',
            kind: NetTransferKind.upload,
            url: 'https://example.com/upload',
            method: 'POST',
            localPath: '/tmp/source.bin',
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
      expect(rustStartCalls, 1);
      expect(dioStartCalls, 0);
    });

    test(
      'surfaces dio rejection for resume download when rust is not ready',
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
            throw const NetException(
              code: NetErrorCode.infrastructure,
              message:
                  'Dio download does not support resumeFrom; use the Rust channel for resume downloads.',
              channel: NetChannel.dio,
              fallbackEligible: false,
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

        await expectLater(
          gateway.startTransferTask(
            const NetTransferTaskRequest(
              taskId: 'task-resume-rust-not-ready',
              kind: NetTransferKind.download,
              url: 'https://example.com/file.bin',
              localPath: '/tmp/file.bin',
              resumeFrom: 256,
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
                .having((error) => error.channel, 'channel', NetChannel.dio)
                .having(
                  (error) => error.fallbackEligible,
                  'fallbackEligible',
                  isFalse,
                ),
          ),
        );
        expect(rustStartCalls, 0);
        expect(dioStartCalls, 1);
      },
    );
  });
}
