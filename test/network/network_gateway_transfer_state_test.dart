import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/net_adapter.dart';
import 'package:flutter_rust_net/network/net_feature_flag.dart';
import 'package:flutter_rust_net/network/net_models.dart';
import 'package:flutter_rust_net/network/network_gateway.dart';
import 'package:flutter_rust_net/network/routing_policy.dart';

void main() {
  group('NetworkGateway transfer state bounds', () {
    test(
      'falls back to the other adapter when tracked channel is stale',
      () async {
        var dioCancelCalls = 0;
        var rustCancelCalls = 0;

        final dio = _FakeTransferAdapter(
          startTransferDelegate: (request) async => request.taskId,
          cancelTransferDelegate: (taskId) async {
            dioCancelCalls += 1;
            return taskId == 'stale-rust-task';
          },
        );
        final rust = _FakeTransferAdapter(
          startTransferDelegate: (request) async => request.taskId,
          cancelTransferDelegate: (taskId) async {
            rustCancelCalls += 1;
            return false;
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
            taskId: 'stale-rust-task',
            kind: NetTransferKind.download,
            url: 'https://example.com/file.bin',
            localPath: '/tmp/file.bin',
          ),
        );

        final canceled = await gateway.cancelTransferTask('stale-rust-task');

        expect(canceled, isTrue);
        expect(rustCancelCalls, 1);
        expect(dioCancelCalls, 1);
      },
    );

    test(
      'refreshes active tracked transfer order before overflow eviction',
      () async {
        var dioCancelCalls = 0;
        var rustCancelCalls = 0;
        var rustPollCalls = 0;

        final dio = _FakeTransferAdapter(
          startTransferDelegate: (request) async => request.taskId,
          cancelTransferDelegate: (taskId) async {
            dioCancelCalls += 1;
            return false;
          },
        );
        final rust = _FakeTransferAdapter(
          startTransferDelegate: (request) async => request.taskId,
          pollTransferDelegate: ({limit = 64}) async {
            rustPollCalls += 1;
            if (rustPollCalls > 1) {
              return const [];
            }
            return const [
              NetTransferEvent(
                id: 'task-0',
                kind: NetTransferEventKind.progress,
                transferred: 64,
                total: 128,
                channel: NetChannel.rust,
              ),
            ];
          },
          cancelTransferDelegate: (taskId) async {
            rustCancelCalls += 1;
            return taskId == 'task-0';
          },
        );

        final gateway = NetworkGateway(
          routingPolicy: const RoutingPolicy(),
          featureFlag: const NetFeatureFlag(enableRustChannel: true),
          dioAdapter: dio,
          rustAdapter: rust,
        );

        for (var i = 0; i < 256; i += 1) {
          await gateway.startTransferTask(
            NetTransferTaskRequest(
              taskId: 'task-$i',
              kind: NetTransferKind.download,
              url: 'https://example.com/file-$i.bin',
              localPath: '/tmp/file-$i.bin',
            ),
          );
        }

        final events = await gateway.pollTransferEvents(limit: 8);
        expect(events, hasLength(1));
        expect(events.single.id, 'task-0');
        expect(events.single.kind, NetTransferEventKind.progress);

        await gateway.startTransferTask(
          const NetTransferTaskRequest(
            taskId: 'task-256',
            kind: NetTransferKind.download,
            url: 'https://example.com/file-256.bin',
            localPath: '/tmp/file-256.bin',
          ),
        );

        final canceled = await gateway.cancelTransferTask('task-0');

        expect(canceled, isTrue);
        expect(rustCancelCalls, 1);
        expect(dioCancelCalls, 0);
      },
    );

    test(
      'evicts oldest tracked transfers and probes adapters on cancel',
      () async {
        var dioCancelCalls = 0;
        var rustCancelCalls = 0;

        final dio = _FakeTransferAdapter(
          startTransferDelegate: (request) async => request.taskId,
          cancelTransferDelegate: (taskId) async {
            dioCancelCalls += 1;
            return false;
          },
        );
        final rust = _FakeTransferAdapter(
          startTransferDelegate: (request) async => request.taskId,
          cancelTransferDelegate: (taskId) async {
            rustCancelCalls += 1;
            return taskId == 'task-0';
          },
        );

        final gateway = NetworkGateway(
          routingPolicy: const RoutingPolicy(),
          featureFlag: const NetFeatureFlag(enableRustChannel: true),
          dioAdapter: dio,
          rustAdapter: rust,
        );

        for (var i = 0; i < 300; i += 1) {
          await gateway.startTransferTask(
            NetTransferTaskRequest(
              taskId: 'task-$i',
              kind: NetTransferKind.download,
              url: 'https://example.com/file-$i.bin',
              localPath: '/tmp/file-$i.bin',
            ),
          );
        }

        final canceled = await gateway.cancelTransferTask('task-0');

        expect(canceled, isTrue);
        expect(dioCancelCalls, 1);
        expect(rustCancelCalls, 1);
      },
    );
  });
}

class _FakeTransferAdapter implements NetAdapter {
  final Future<String> Function(NetTransferTaskRequest request)
  _startTransferDelegate;
  final Future<List<NetTransferEvent>> Function({int limit})
  _pollTransferDelegate;
  final Future<bool> Function(String taskId) _cancelTransferDelegate;

  _FakeTransferAdapter({
    required Future<String> Function(NetTransferTaskRequest request)
    startTransferDelegate,
    Future<List<NetTransferEvent>> Function({int limit})? pollTransferDelegate,
    required Future<bool> Function(String taskId) cancelTransferDelegate,
  }) : _startTransferDelegate = startTransferDelegate,
       _pollTransferDelegate = pollTransferDelegate ?? _defaultPollTransfer,
       _cancelTransferDelegate = cancelTransferDelegate;

  @override
  bool get isReady => true;

  @override
  Future<NetResponse> request(NetRequest request, {bool fromFallback = false}) {
    throw UnimplementedError();
  }

  @override
  Future<String> startTransferTask(NetTransferTaskRequest request) {
    return _startTransferDelegate(request);
  }

  @override
  Future<List<NetTransferEvent>> pollTransferEvents({int limit = 64}) async {
    return _pollTransferDelegate(limit: limit);
  }

  @override
  Future<bool> cancelTransferTask(String taskId) {
    return _cancelTransferDelegate(taskId);
  }

  static Future<List<NetTransferEvent>> _defaultPollTransfer({
    int limit = 64,
  }) async {
    return const [];
  }
}
