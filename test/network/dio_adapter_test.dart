import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/dio_adapter.dart';
import 'package:flutter_rust_net/network/net_models.dart';

void main() {
  group('DioAdapter', () {
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
              .having(
                (error) => error.channel,
                'channel',
                NetChannel.dio,
              )
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
  });
}
