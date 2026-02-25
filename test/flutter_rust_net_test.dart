import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_rust_net/flutter_rust_net.dart';

void main() {
  test('exports core network models', () {
    const request = NetRequest(method: 'GET', url: 'https://example.com');
    expect(request.method, 'GET');
    expect(request.url, 'https://example.com');
  });
}
