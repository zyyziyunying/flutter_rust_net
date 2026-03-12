import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/net_models.dart';
import 'package:flutter_rust_net/network/rust_adapter.dart';
import 'package:flutter_rust_net/rust_bridge/api.dart' as rust_api;

import 'fake_rust_bridge_api.dart';

void main() {
  group('RustAdapter transfer and cache', () {
    test(
      'starts transfer task and maps events/cancel through bridge',
      () async {
        final fakeBridge = FakeRustBridgeApi(
          startTransferResponder: (spec) async {
            expect(spec.taskId, 'transfer-1');
            expect(spec.kind, NetTransferKind.download.name);
            expect(spec.url, 'https://example.com/file.bin');
            expect(spec.localPath, '/tmp/file.bin');
            expect(spec.expectedTotal, BigInt.from(2048));
            expect(spec.priority, 7);
            return spec.taskId;
          },
          pollEventsResponder: (limit) async {
            expect(limit, 8);
            return [
              rust_api.NetEvent(
                id: 'transfer-1',
                kind: rust_api.NetEventKind.progress,
                transferred: BigInt.one,
                total: BigInt.one,
                statusCode: null,
                message: null,
                costMs: null,
              ),
            ];
          },
          cancelResponder: (id) async {
            expect(id, 'transfer-1');
            return true;
          },
        );
        final adapter = RustAdapter(bridgeApi: fakeBridge);

        await adapter.initializeEngine();
        final taskId = await adapter.startTransferTask(
          const NetTransferTaskRequest(
            taskId: 'transfer-1',
            kind: NetTransferKind.download,
            url: 'https://example.com/file.bin',
            localPath: '/tmp/file.bin',
            expectedTotal: 2048,
            priority: 7,
          ),
        );
        final events = await adapter.pollTransferEvents(limit: 8);
        final canceled = await adapter.cancelTransferTask('transfer-1');

        expect(taskId, 'transfer-1');
        expect(events, hasLength(1));
        expect(events.first.id, 'transfer-1');
        expect(events.first.kind, NetTransferEventKind.progress);
        expect(events.first.transferred, 1);
        expect(events.first.total, 1);
        expect(events.first.channel, NetChannel.rust);
        expect(canceled, isTrue);
        expect(fakeBridge.startTransferCalls, 1);
        expect(fakeBridge.pollEventsCalls, 1);
        expect(fakeBridge.cancelCalls, 1);
      },
    );

    test('clears cache through rust bridge', () async {
      final fakeBridge = FakeRustBridgeApi(
        clearCacheResponder: (namespace) async {
          expect(namespace, 'responses');
          return 128;
        },
      );
      final adapter = RustAdapter(bridgeApi: fakeBridge);

      await adapter.initializeEngine();
      final removed = await adapter.clearCache(namespace: 'responses');

      expect(removed, 128);
      expect(fakeBridge.clearCacheCalls, 1);
    });
  });
}
