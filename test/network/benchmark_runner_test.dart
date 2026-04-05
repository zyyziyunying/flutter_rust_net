import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/benchmark/network_benchmark_harness.dart';
import 'package:flutter_rust_net/network/rhttp_adapter.dart';

void main() {
  group('benchmark runner thin-gateway rust channel', () {
    test(
      'preflights the rust request channel without using rust bridge lifecycle',
      () async {
        final requestAdapter = _buildBenchmarkRequestAdapter();
        const config = BenchmarkConfig(
          scenario: BenchmarkScenario.smallJson,
          requests: 4,
          warmupRequests: 0,
          concurrency: 1,
          channels: {BenchmarkChannel.rust},
          preflightPrimaryChannel: true,
          requirePrimaryChannel: true,
          enableFallback: false,
          verbose: false,
        );

        final first = await runNetworkBenchmark(
          config,
          primaryRequestAdapter: requestAdapter,
        );
        final second = await runNetworkBenchmark(
          config,
          primaryRequestAdapter: requestAdapter,
        );

        expect(first.primaryChannelPreflighted, isTrue);
        expect(second.primaryChannelPreflighted, isTrue);
        expect(first.channelResults.single.exceptions, 0);
        expect(second.channelResults.single.exceptions, 0);
        expect(first.channelResults.single.completedRequests, 4);
        expect(second.channelResults.single.completedRequests, 4);
        expect(first.channelResults.single.responseChannels['rust'], 4);
        expect(second.channelResults.single.responseChannels['rust'], 4);
        expect(first.toJson()['primaryChannelPreflighted'], isTrue);
        expect(first.toJson().containsKey('rustInitialized'), isFalse);
        expect(
          first.toPrettyText(),
          contains('primaryChannelPreflighted=true'),
        );
        expect(first.toPrettyText(), isNot(contains('rustInitialized=')));
      },
    );

    test(
      'rust benchmark request path does not require explicit initialization',
      () async {
        final requestAdapter = _buildBenchmarkRequestAdapter();

        final report = await runNetworkBenchmark(
          const BenchmarkConfig(
            scenario: BenchmarkScenario.smallJson,
            requests: 4,
            warmupRequests: 0,
            concurrency: 1,
            channels: {BenchmarkChannel.rust},
            preflightPrimaryChannel: false,
            requirePrimaryChannel: false,
            enableFallback: false,
            verbose: false,
          ),
          primaryRequestAdapter: requestAdapter,
        );

        expect(report.primaryChannelPreflighted, isFalse);
        expect(report.channelResults.single.exceptions, 0);
        expect(report.channelResults.single.completedRequests, 4);
        expect(report.channelResults.single.responseChannels['rust'], 4);
        expect(report.toJson()['primaryChannelPreflighted'], isFalse);
        expect(report.toJson().containsKey('rustInitialized'), isFalse);
        expect(
          report.toPrettyText(),
          contains('primaryChannelPreflighted=false'),
        );
      },
    );

    test('rejects duplicate primary request adapter injection', () {
      final requestAdapter = _buildBenchmarkRequestAdapter();
      expect(
        () => runNetworkBenchmark(
          const BenchmarkConfig(
            scenario: BenchmarkScenario.smallJson,
            requests: 1,
            warmupRequests: 0,
            concurrency: 1,
            channels: {BenchmarkChannel.rust},
            preflightPrimaryChannel: false,
            requirePrimaryChannel: false,
            enableFallback: false,
            verbose: false,
          ),
          primaryRequestAdapter: requestAdapter,
          rustAdapter: requestAdapter,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains(
              'Provide only one of primaryRequestAdapter or rustAdapter',
            ),
          ),
        ),
      );
    });
  });
}

RhttpAdapter _buildBenchmarkRequestAdapter() {
  return RhttpAdapter(
    requestHandler: (request) async {
      final uri = Uri.parse(request.url);
      final body = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'ok': true,
            'path': uri.path,
            'requestId': uri.queryParameters['id'],
          }),
        ),
      );
      return RhttpAdapterResponse(
        statusCode: HttpStatus.ok,
        headers: const [('content-type', 'application/json')],
        bodyBytes: body,
      );
    },
  );
}
