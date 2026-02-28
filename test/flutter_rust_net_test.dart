import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_rust_net/flutter_rust_net.dart';

void main() {
  test('exports core network models', () {
    const request = NetRequest(method: 'GET', url: 'https://example.com');
    expect(request.method, 'GET');
    expect(request.httpMethod, NetHttpMethod.get);
    expect(request.url, 'https://example.com');
  });

  test('supports enum-based request constructors', () {
    final request = NetRequest.post(
      url: 'https://example.com/upload',
      body: const {'ok': true},
    );

    expect(request.method, 'POST');
    expect(request.httpMethod, NetHttpMethod.post);
    expect(request.body, const {'ok': true});
  });

  test('exports common header names', () {
    expect(NetHeaderName.contentType.wireName, 'content-type');
    expect(NetHeaderName.idempotencyKey.wireName, 'idempotency-key');
  });
}
