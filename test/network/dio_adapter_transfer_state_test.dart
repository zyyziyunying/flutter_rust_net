import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/dio_adapter.dart';
import 'package:flutter_rust_net/network/net_models.dart';

void main() {
  group('DioAdapter transfer state bounds', () {
    test(
      'keeps only terminal event for completed task when polling is delayed',
      () async {
        final adapter = DioAdapter();
        final tempDir = await Directory.systemTemp.createTemp(
          'flutter_rust_net_dio_transfer_state_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final destination = File(
          '${tempDir.path}${Platform.pathSeparator}large.bin',
        );
        const totalChunks = 24;
        const chunkSize = 1024;
        final expectedLength = totalChunks * chunkSize;

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          await server.close(force: true);
        });
        server.listen((request) async {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentLength = expectedLength;
          for (var chunk = 0; chunk < totalChunks; chunk += 1) {
            request.response.add(List<int>.filled(chunkSize, chunk));
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          await request.response.close();
        });

        const taskId = 'delayed-poll-download-1';
        await adapter.startTransferTask(
          NetTransferTaskRequest(
            taskId: taskId,
            kind: NetTransferKind.download,
            url: 'http://${server.address.address}:${server.port}/large.bin',
            localPath: destination.path,
          ),
        );

        await _waitForPublishedDownload(destination, expectedLength);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final events = await adapter.pollTransferEvents(limit: 32);
        final taskEvents = events.where((event) => event.id == taskId).toList();

        expect(taskEvents, hasLength(1));
        expect(taskEvents.single.kind, NetTransferEventKind.completed);
        expect(taskEvents.single.statusCode, HttpStatus.ok);
      },
    );

    test('caps buffered transfer events across many unpolled tasks', () async {
      final adapter = DioAdapter();
      final tempDir = await Directory.systemTemp.createTemp(
        'flutter_rust_net_dio_transfer_state_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      const taskCount = 300;
      for (var i = 0; i < taskCount; i += 1) {
        await adapter.startTransferTask(
          NetTransferTaskRequest(
            taskId: 'missing-upload-$i',
            kind: NetTransferKind.upload,
            url: 'https://example.com/upload',
            method: 'POST',
            localPath:
                '${tempDir.path}${Platform.pathSeparator}missing-upload-$i.bin',
          ),
        );
      }

      await Future<void>.delayed(const Duration(seconds: 1));

      final events = await adapter.pollTransferEvents(limit: taskCount + 32);

      expect(events.length, lessThan(taskCount));
      expect(
        events.every((event) => event.kind == NetTransferEventKind.failed),
        isTrue,
      );
    });
  });
}

Future<void> _waitForPublishedDownload(
  File destination,
  int expectedLength,
) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < const Duration(seconds: 5)) {
    if (await destination.exists() &&
        await destination.length() == expectedLength) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  fail('Timed out waiting for published download ${destination.path}');
}
