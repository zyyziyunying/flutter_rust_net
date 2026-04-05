import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/benchmark/network_benchmark_harness.dart';

void main() {
  group('BenchmarkConfig defaults', () {
    test('preflights the primary request channel by default', () {
      const config = BenchmarkConfig();
      expect(config.preflightPrimaryChannel, isTrue);
      expect(config.requirePrimaryChannel, isFalse);
    });

    test('uses request key-space default 0', () {
      const config = BenchmarkConfig();
      expect(config.requestKeySpace, 0);
    });
  });

  group('BenchmarkConfig copyWith', () {
    test('updates primary channel flags without runtime knobs', () {
      const config = BenchmarkConfig(
        preflightPrimaryChannel: true,
        requirePrimaryChannel: false,
      );

      final updated = config.copyWith(
        preflightPrimaryChannel: false,
        requirePrimaryChannel: true,
      );

      expect(updated.preflightPrimaryChannel, isFalse);
      expect(updated.requirePrimaryChannel, isTrue);
    });
  });

  group('BenchmarkConfig validation', () {
    test('rejects large payload below minimum threshold', () {
      expect(
        () => const BenchmarkConfig(largePayloadBytes: 1024).validate(),
        throwsArgumentError,
      );
    });

    test('rejects negative request key-space', () {
      expect(
        () => const BenchmarkConfig(requestKeySpace: -1).validate(),
        throwsArgumentError,
      );
    });

    test('toJson omits legacy runtime knobs', () {
      const config = BenchmarkConfig(
        preflightPrimaryChannel: false,
        requirePrimaryChannel: true,
      );

      final json = config.toJson();
      expect(json['preflightPrimaryChannel'], isFalse);
      expect(json['requirePrimaryChannel'], isTrue);
      expect(json.containsKey('initializeRust'), isFalse);
      expect(json.containsKey('requireRust'), isFalse);
      expect(json.containsKey('rustMaxInFlightTasks'), isFalse);
      expect(json.containsKey('rustCacheDir'), isFalse);
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
