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
  final Future<bool> Function(String taskId) _cancelTransferDelegate;

  _FakeTransferAdapter({
    required Future<String> Function(NetTransferTaskRequest request)
    startTransferDelegate,
    required Future<bool> Function(String taskId) cancelTransferDelegate,
  }) : _startTransferDelegate = startTransferDelegate,
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
    return const [];
  }

  @override
  Future<bool> cancelTransferTask(String taskId) {
    return _cancelTransferDelegate(taskId);
  }
}
