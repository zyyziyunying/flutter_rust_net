import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/dio_adapter.dart';
import 'package:flutter_rust_net/network/net_models.dart';

void main() {
  group('DioAdapter', () {
    test('resolves request baseUrl for relative urls', () async {
      final adapter = DioAdapter();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });
      server.listen((request) async {
        expect(request.uri.path, '/todos/1');
        expect(request.uri.queryParameters['lang'], 'en');
        expect(request.uri.queryParameters['page'], '2');
        request.response.statusCode = HttpStatus.ok;
        request.response.write('ok');
        await request.response.close();
      });

      final response = await adapter.request(
        NetRequest(
          method: 'GET',
          url: '/todos/1?lang=en',
          baseUrl: 'http://${server.address.address}:${server.port}',
          queryParameters: const {'page': 2},
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.channel, NetChannel.dio);
    });

    test('rejects resume download tasks', () async {
      final adapter = DioAdapter();

      await expectLater(
        adapter.startTransferTask(
          const NetTransferTaskRequest(
            taskId: 'resume-download-1',
            kind: NetTransferKind.download,
            url: 'https://example.com/file.bin',
            localPath: '/tmp/file.bin',
            resumeFrom: 128,
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
              )
              .having(
                (error) => error.message,
                'message',
                contains('resumeFrom'),
              ),
        ),
      );
    });

    test('replaces destination only after successful downloads', () async {
      final adapter = DioAdapter();
      final tempDir = await Directory.systemTemp.createTemp(
        'flutter_rust_net_dio_adapter_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final destination = File(
        '${tempDir.path}${Platform.pathSeparator}file.bin',
      );
      await destination.writeAsString('old-data');

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });
      server.listen((request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentLength = 'new-data'.length;
        request.response.write('new-data');
        await request.response.close();
      });

      await adapter.startTransferTask(
        NetTransferTaskRequest(
          taskId: 'download-success-1',
          kind: NetTransferKind.download,
          url: 'http://${server.address.address}:${server.port}/file.bin',
          localPath: destination.path,
        ),
      );
      final events = await _waitForEventsUntil(
        adapter,
        'download-success-1',
        _hasTerminalEvent,
      );
      final completed = events.lastWhere(_isTerminalEvent);

      expect(completed.kind, NetTransferEventKind.completed);
      expect(completed.statusCode, HttpStatus.ok);
      expect(await destination.readAsString(), 'new-data');
      expect(await _findTempArtifacts(destination.path), isEmpty);
    });

    test(
      'preserves destination and cleans temp files for non-2xx downloads',
      () async {
        final adapter = DioAdapter();
        final tempDir = await Directory.systemTemp.createTemp(
          'flutter_rust_net_dio_adapter_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final destination = File(
          '${tempDir.path}${Platform.pathSeparator}file.bin',
        );
        await destination.writeAsString('stable-data');

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          await server.close(force: true);
        });
        server.listen((request) async {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('not-found-body');
          await request.response.close();
        });

        await adapter.startTransferTask(
          NetTransferTaskRequest(
            taskId: 'download-404-1',
            kind: NetTransferKind.download,
            url: 'http://${server.address.address}:${server.port}/missing.bin',
            localPath: destination.path,
          ),
        );
        final events = await _waitForEventsUntil(
          adapter,
          'download-404-1',
          _hasTerminalEvent,
        );
        final failed = events.lastWhere(_isTerminalEvent);

        expect(failed.kind, NetTransferEventKind.failed);
        expect(failed.statusCode, HttpStatus.notFound);
        expect(await destination.readAsString(), 'stable-data');
        expect(await _findTempArtifacts(destination.path), isEmpty);
      },
    );

    test(
      'preserves destination and cleans temp files for canceled downloads',
      () async {
        final adapter = DioAdapter();
        final tempDir = await Directory.systemTemp.createTemp(
          'flutter_rust_net_dio_adapter_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final destination = File(
          '${tempDir.path}${Platform.pathSeparator}file.bin',
        );
        await destination.writeAsString('stable-data');

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          await server.close(force: true);
        });
        server.listen((request) async {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentLength = 32 * 1024;
          try {
            for (var chunk = 0; chunk < 32; chunk += 1) {
              request.response.add(List<int>.filled(1024, chunk));
              await request.response.flush();
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
          } on HttpException {
            // Client canceled the download mid-stream.
          } on SocketException {
            // Client canceled the download mid-stream.
          } finally {
            try {
              await request.response.close();
            } on HttpException {
              // Client already disconnected.
            } on SocketException {
              // Client already disconnected.
            }
          }
        });

        await adapter.startTransferTask(
          NetTransferTaskRequest(
            taskId: 'download-cancel-1',
            kind: NetTransferKind.download,
            url: 'http://${server.address.address}:${server.port}/slow.bin',
            localPath: destination.path,
          ),
        );
        final activeEvents = await _waitForEventsUntil(
          adapter,
          'download-cancel-1',
          _hasStartedOrProgressEvent,
        );

        final canceled = await adapter.cancelTransferTask('download-cancel-1');
        final terminalEvents = await _waitForEventsUntil(
          adapter,
          'download-cancel-1',
          _hasTerminalEvent,
          seed: activeEvents,
        );
        final terminal = terminalEvents.lastWhere(_isTerminalEvent);

        expect(canceled, isTrue);
        expect(terminal.kind, NetTransferEventKind.canceled);
        expect(await destination.readAsString(), 'stable-data');
        expect(await _findTempArtifacts(destination.path), isEmpty);
      },
    );
  });
}

Future<List<NetTransferEvent>> _waitForEventsUntil(
  DioAdapter adapter,
  String taskId,
  bool Function(List<NetTransferEvent> events) predicate, {
  Duration timeout = const Duration(seconds: 5),
  List<NetTransferEvent>? seed,
}) async {
  final watch = Stopwatch()..start();
  final events = <NetTransferEvent>[...?seed];

  while (watch.elapsed < timeout) {
    final polled = await adapter.pollTransferEvents(limit: 32);
    events.addAll(polled.where((event) => event.id == taskId));
    if (predicate(events)) {
      return events;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  fail('Timed out waiting for transfer events for $taskId');
}

bool _hasTerminalEvent(List<NetTransferEvent> events) {
  return events.any(_isTerminalEvent);
}

bool _hasStartedOrProgressEvent(List<NetTransferEvent> events) {
  return events.any(
    (event) =>
        event.kind == NetTransferEventKind.started ||
        event.kind == NetTransferEventKind.progress,
  );
}

bool _isTerminalEvent(NetTransferEvent event) {
  return event.kind == NetTransferEventKind.completed ||
      event.kind == NetTransferEventKind.failed ||
      event.kind == NetTransferEventKind.canceled;
}

Future<List<String>> _findTempArtifacts(String destinationPath) async {
  final parent = File(destinationPath).parent;
  final prefix = '$destinationPath.dio-download-';
  final artifacts = <String>[];

  await for (final entity in parent.list()) {
    if (entity is File && entity.path.startsWith(prefix)) {
      artifacts.add(entity.path);
    }
  }

  return artifacts;
}
