import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/benchmark/download_benchmark_support.dart';

void main() {
  group('streamDeterministicDownloadPayload', () {
    test('emits deterministic bytes in bounded chunks', () async {
      final chunks = await streamDeterministicDownloadPayload(
        10,
        chunkBytes: 4,
      ).toList();

      expect(chunks.map((item) => item.length), [4, 4, 2]);
      expect(
        chunks.expand((item) => item),
        buildDeterministicDownloadPayload(10),
      );
    });
  });
}
