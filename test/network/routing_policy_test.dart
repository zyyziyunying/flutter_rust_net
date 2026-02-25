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

    test('routes transfer task to rust when rust is enabled', () {
      final decision = policy.decide(
        const NetRequest(
          method: 'GET',
          url: 'https://example.com/file',
          isTransferTask: true,
        ),
        const NetFeatureFlag(enableRustChannel: true),
      );

      expect(decision.channel, NetChannel.rust);
      expect(decision.reason, 'transfer_task');
    });

    test('routes jitter sensitive request to dio before rust heuristics', () {
      final decision = policy.decide(
        const NetRequest(
          method: 'GET',
          url: 'https://example.com/large',
          expectLargeResponse: true,
          isJitterSensitive: true,
        ),
        const NetFeatureFlag(enableRustChannel: true),
      );

      expect(decision.channel, NetChannel.dio);
      expect(decision.reason, 'jitter_sensitive_tag');
    });

    test('routes expect_large_response to rust', () {
      final decision = policy.decide(
        const NetRequest(
          method: 'GET',
          url: 'https://example.com/large',
          expectLargeResponse: true,
        ),
        const NetFeatureFlag(enableRustChannel: true),
      );

      expect(decision.channel, NetChannel.rust);
      expect(decision.reason, 'expect_large_response');
    });

    test('routes by large content hint', () {
      final decision = policy.decide(
        const NetRequest(
          method: 'GET',
          url: 'https://example.com/large',
          contentLengthHint: 2048,
        ),
        const NetFeatureFlag(
          enableRustChannel: true,
          rustBodyThresholdBytes: 1024,
        ),
      );

      expect(decision.channel, NetChannel.rust);
      expect(decision.reason, 'large_content_hint');
    });

    test('routes by allow list', () {
      final decision = policy.decide(
        const NetRequest(method: 'GET', url: 'https://example.com/api/v1/list'),
        const NetFeatureFlag(
          enableRustChannel: true,
          rustPathAllowList: {'/api/*'},
        ),
      );

      expect(decision.channel, NetChannel.rust);
      expect(decision.reason, 'allow_list');
    });

    test('routes dio deny list before rust allow list', () {
      final decision = policy.decide(
        const NetRequest(
          method: 'GET',
          url: 'https://example.com/api/v1/jitter',
        ),
        const NetFeatureFlag(
          enableRustChannel: true,
          rustPathAllowList: {'/api/*'},
          dioPathDenyList: {'/api/v1/jitter'},
        ),
      );

      expect(decision.channel, NetChannel.dio);
      expect(decision.reason, 'dio_deny_list');
    });

    test('falls back to dio when rust is disabled', () {
      final decision = policy.decide(
        const NetRequest(method: 'GET', url: 'https://example.com/a'),
        const NetFeatureFlag(enableRustChannel: false),
      );

      expect(decision.channel, NetChannel.dio);
      expect(decision.reason, 'rust_disabled');
    });
  });
}
