import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/benchmark/benchmark_config.dart';
import 'package:flutter_rust_net/network/benchmark/benchmark_scenario_server.dart';

void main() {
  group('ScenarioServer download bench endpoint', () {
    test(
      'download-file endpoint returns requested byte count and checksum',
      () async {
        final config = const BenchmarkConfig(largePayloadBytes: 1024);
        final server = await ScenarioServer.start(config, logger: (_) {});
        addTearDown(server.close);

        final client = HttpClient();
        addTearDown(client.close);

        final request = await client.getUrl(
          Uri.parse(
            '${server.baseUrl}/bench/download-file?bytes=4096&chunkBytes=1024',
          ),
        );
        final response = await request.close();
        final body = await response.fold<BytesBuilder>(
          BytesBuilder(copy: false),
          (builder, chunk) {
            builder.add(chunk);
            return builder;
          },
        );
        final bytes = body.takeBytes();

        expect(response.statusCode, HttpStatus.ok);
        expect(response.headers.contentLength, 4096);
        expect(bytes.length, 4096);
        expect(
          _rollingChecksum(bytes),
          _rollingChecksum(_expectedDownloadPayload(4096)),
        );
      },
    );
  });
}

Uint8List _expectedDownloadPayload(int bytes) {
  final data = Uint8List(bytes);
  for (var i = 0; i < bytes; i += 1) {
    data[i] = (i * 31 + 17) % 251;
  }
  return data;
}

int _rollingChecksum(List<int> bytes) {
  var checksum = 0;
  for (final byte in bytes) {
    checksum = ((checksum * 33) + byte) & 0x7fffffff;
  }
  return checksum;
}
