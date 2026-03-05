import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/benchmark/network_benchmark_harness.dart';

void main() {
  group('BenchmarkConfig defaults', () {
    test('uses rust max in-flight default 32', () {
      const config = BenchmarkConfig();
      expect(config.rustMaxInFlightTasks, 32);
    });

    test('uses request key-space default 0', () {
      const config = BenchmarkConfig();
      expect(config.requestKeySpace, 0);
    });
  });

  group('resolveScenarioBaseUrl', () {
    test('normalizes trailing slash and empty value', () {
      expect(resolveScenarioBaseUrl('  '), isNull);
      expect(
        resolveScenarioBaseUrl('https://example.com/bench///'),
        'https://example.com/bench',
      );
    });
  });
}
