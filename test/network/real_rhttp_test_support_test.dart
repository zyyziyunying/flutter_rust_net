import 'package:flutter_test/flutter_test.dart';

import 'test_support/real_rhttp_test_support.dart';

void main() {
  group('realRhttpSkipReason', () {
    test('uses legacy env var when both env vars are configured', () {
      final reason = realRhttpSkipReason(
        environment: const {
          'RHTTP_NATIVE_LIB_DIR': '/tmp/new',
          'FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR': '/tmp/old',
        },
        fileExists: (path) => path == '/tmp/old/librhttp.dylib',
      );

      expect(reason, isNull);
    });

    test('falls back to legacy env var when neutral env var is absent', () {
      final reason = realRhttpSkipReason(
        environment: const {
          'FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR': '/tmp/old',
        },
        fileExists: (path) => path == '/tmp/old/librhttp.dylib',
      );

      expect(reason, isNull);
    });

    test('falls back to legacy env var when neutral env var is empty', () {
      final reason = realRhttpSkipReason(
        environment: const {
          'RHTTP_NATIVE_LIB_DIR': '',
          'FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR': '/tmp/old',
        },
        fileExists: (path) => path == '/tmp/old/librhttp.dylib',
      );

      expect(reason, isNull);
    });

    test('returns loader-correct guidance when no env var is configured', () {
      final reason = realRhttpSkipReason(
        environment: const {},
        fileExists: (_) => false,
      );

      expect(
        reason,
        'Set FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR to a directory '
        'containing librhttp.dylib to run opt-in real-rhttp tests.',
      );
    });

    test('keeps tests skipped when only neutral env var is configured', () {
      final reason = realRhttpSkipReason(
        environment: const {
          'RHTTP_NATIVE_LIB_DIR': '/tmp/new',
        },
        fileExists: (path) => path == '/tmp/new/librhttp.dylib',
      );

      expect(
        reason,
        'RHTTP_NATIVE_LIB_DIR is set to /tmp/new, but the current rhttp '
        'native loader still reads '
        'FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR. Mirror the same '
        'directory into FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR to run '
        'opt-in real-rhttp tests.',
      );
    });

    test('returns compatibility guidance when configured dir misses library', () {
      final reason = realRhttpSkipReason(
        environment: const {
          'FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR': '/tmp/old',
        },
        fileExists: (_) => false,
      );

      expect(
        reason,
        'Missing librhttp.dylib under the configured native rhttp library '
        'directory: /tmp/old.',
      );
    });
  });
}
