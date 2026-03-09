import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/net_models.dart';
import 'package:flutter_rust_net/network/request_body_codec.dart';

void main() {
  group('encodeRequestBody', () {
    test('encodes List<int> body as UTF-8 JSON bytes', () {
      final encoded = encodeRequestBody(
        <int>[1, 2, 256, -1],
        channel: NetChannel.dio,
      );

      expect(encoded, isNotNull);
      expect(utf8.decode(encoded!), '[1,2,256,-1]');
    });

    test('rejects ambiguous body plus bodyBytes', () {
      expect(
        () => encodeRequestBody(
          const <String, Object?>{'ok': true},
          bodyBytes: const <int>[1, 2, 3],
          channel: NetChannel.rust,
        ),
        throwsA(
          isA<NetException>().having(
            (error) => error.message,
            'message',
            contains('either body or bodyBytes'),
          ),
        ),
      );
    });

    test('rejects typed-data body and points callers to bodyBytes', () {
      expect(
        () => encodeRequestBody(
          Uint8List.fromList(const [1, 2, 3]),
          channel: NetChannel.dio,
        ),
        throwsA(
          isA<NetException>().having(
            (error) => error.message,
            'message',
            contains('must use bodyBytes'),
          ),
        ),
      );
    });

    test('rejects out-of-range explicit raw bytes', () {
      expect(
        () => encodeRequestBody(
          null,
          bodyBytes: const <int>[1, 2, 256],
          channel: NetChannel.rust,
        ),
        throwsA(
          isA<NetException>().having(
            (error) => error.message,
            'message',
            contains('bodyBytes[2]'),
          ),
        ),
      );
    });
  });
}
