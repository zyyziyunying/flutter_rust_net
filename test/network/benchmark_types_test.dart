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

    test('uses rust cache budget defaults', () {
      const config = BenchmarkConfig();
      expect(config.rustCacheDir, isNull);
      expect(config.rustCacheResponseNamespace, 'responses');
      expect(
        config.rustCacheMaxNamespaceBytes,
        BenchmarkConfig.defaultRustCacheMaxNamespaceBytes,
      );
      expect(config.rustCacheRootMaxBytes, isNull);
    });
  });

  group('BenchmarkConfig rust init mapping', () {
    test('maps rust cache settings into RustEngineInitOptions', () {
      const config = BenchmarkConfig(
        rustMaxInFlightTasks: 24,
        rustCacheDir: '  build/bench_cache  ',
        rustCacheResponseNamespace: 'tenant_cache',
        rustCacheMaxNamespaceBytes: 4096,
        rustCacheRootMaxBytes: 8192,
      );

      final options = config.toRustEngineInitOptions();
      expect(options.maxInFlightTasks, 24);
      expect(options.cacheDir, '  build/bench_cache  ');
      expect(options.cacheResponseNamespace, 'tenant_cache');
      expect(options.cacheMaxNamespaceBytes, 4096);
      expect(options.cacheRootMaxBytes, 8192);
    });

    test('copyWith can clear nullable rust cache fields back to null', () {
      const config = BenchmarkConfig(
        rustCacheDir: 'build/bench_cache',
        rustCacheRootMaxBytes: 8192,
      );

      final updated = config.copyWith(
        rustCacheDir: null,
        rustCacheRootMaxBytes: null,
      );

      expect(updated.rustCacheDir, isNull);
      expect(updated.rustCacheRootMaxBytes, isNull);
    });
  });

  group('BenchmarkConfig validation', () {
    test('rejects rust cache namespace budget above u32 max', () {
      expect(
        () => const BenchmarkConfig(
          rustCacheMaxNamespaceBytes: 0x1_0000_0000,
        ).validate(),
        throwsArgumentError,
      );
    });

    test('rejects rust root cache budget above u32 max', () {
      expect(
        () => const BenchmarkConfig(
          rustCacheRootMaxBytes: 0x1_0000_0000,
        ).validate(),
        throwsArgumentError,
      );
    });

    test('ignores rust cache budgets above u32 max when cache is disabled', () {
      expect(
        () => const BenchmarkConfig(
          rustCacheDir: '   ',
          rustCacheMaxNamespaceBytes: 0x1_0000_0000,
          rustCacheRootMaxBytes: 0x1_0000_0000,
        ).validate(),
        returnsNormally,
      );
    });
  });

  group('BenchmarkConfig runtime config', () {
    test('uses run-unique default cache root when rustCacheDir is omitted', () {
      const config = BenchmarkConfig();

      final runtimeConfig = config.resolveRuntimeConfig(
        defaultRustCacheDir: 'build/bench_cache/run_1',
      );

      expect(runtimeConfig.rustCacheDir, 'build/bench_cache/run_1');
      expect(runtimeConfig.rustCacheEnabled, isTrue);
    });

    test('normalizes rust cache fields to effective init values', () {
      const config = BenchmarkConfig(
        rustCacheDir: '  build/bench_cache  ',
        rustCacheResponseNamespace: ' tenant_cache ',
        rustCacheMaxNamespaceBytes: 0,
        rustCacheRootMaxBytes: 0,
      );

      final runtimeConfig = config.resolveRuntimeConfig();

      expect(runtimeConfig.rustCacheDir, 'build/bench_cache');
      expect(runtimeConfig.rustCacheResponseNamespace, 'tenant_cache');
      expect(
        runtimeConfig.rustCacheMaxNamespaceBytes,
        BenchmarkConfig.defaultRustCacheMaxNamespaceBytes,
      );
      expect(runtimeConfig.rustCacheRootMaxBytes, isNull);
    });

    test('drops cache-only overrides when cache is disabled', () {
      const config = BenchmarkConfig(
        rustCacheDir: '   ',
        rustCacheResponseNamespace: '../outside',
        rustCacheMaxNamespaceBytes: 8192,
        rustCacheRootMaxBytes: 8192,
      );

      final runtimeConfig = config.resolveRuntimeConfig(
        defaultRustCacheDir: 'build/bench_cache/run_2',
      );

      expect(runtimeConfig.rustCacheDir, '');
      expect(runtimeConfig.rustCacheResponseNamespace, 'responses');
      expect(
        runtimeConfig.rustCacheMaxNamespaceBytes,
        BenchmarkConfig.defaultRustCacheMaxNamespaceBytes,
      );
      expect(runtimeConfig.rustCacheRootMaxBytes, isNull);
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
