import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_net/network/net_feature_flag.dart';
import 'package:flutter_rust_net/network/net_models.dart';
import 'package:flutter_rust_net/network/routing_policy.dart';

void main() {
  const policy = RoutingPolicy();

  group('RoutingPolicy', () {
    test('respects force_channel first', () {
      final decision = policy.decide(
        const NetRequest(
          method: 'GET',
          url: 'https://example.com/a',
          forceChannel: NetChannel.rust,
        ),
        const NetFeatureFlag(enableRustChannel: false),
      );

      expect(decision.channel, NetChannel.rust);
      expect(decision.reason, 'force_channel');
    });

    test('routes to rust when switch is enabled', () {
      final decision = policy.decide(
        const NetRequest(method: 'GET', url: 'https://example.com/file'),
        const NetFeatureFlag(enableRustChannel: true),
      );

      expect(decision.channel, NetChannel.rust);
      expect(decision.reason, 'rust_enabled');
    });

    test('ignores non-routing hints when deciding the channel', () {
      final decision = policy.decide(
        const NetRequest(
          method: 'GET',
          url: 'https://example.com/api/v1/jitter',
          isTransferTask: true,
          expectLargeResponse: true,
          contentLengthHint: 2048,
          isJitterSensitive: true,
        ),
        const NetFeatureFlag(enableRustChannel: true),
      );

      expect(decision.channel, NetChannel.rust);
      expect(decision.reason, 'rust_enabled');
    });

    test('falls back to dio when rust is disabled', () {
      final decision = policy.decide(
        const NetRequest(method: 'GET', url: 'https://example.com/a'),
        const NetFeatureFlag(enableRustChannel: false),
      );

      expect(decision.channel, NetChannel.dio);
      expect(decision.reason, 'rust_disabled');
    });

    test('defaults to rust when no switch is provided', () {
      final decision = policy.decide(
        const NetRequest(method: 'GET', url: 'https://example.com/a'),
        const NetFeatureFlag(),
      );

      expect(decision.channel, NetChannel.rust);
      expect(decision.reason, 'rust_enabled');
    });
  });
}
