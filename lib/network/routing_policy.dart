import 'net_feature_flag.dart';
import 'net_models.dart';

class RoutingDecision {
  final NetChannel channel;
  final String reason;

  const RoutingDecision({required this.channel, required this.reason});
}

class RoutingPolicy {
  const RoutingPolicy();

  RoutingDecision decide(NetRequest request, NetFeatureFlag featureFlag) {
    if (request.forceChannel != null) {
      return RoutingDecision(
        channel: request.forceChannel!,
        reason: 'force_channel',
      );
    }

    if (!featureFlag.enableRustChannel) {
      return const RoutingDecision(
        channel: NetChannel.dio,
        reason: 'rust_disabled',
      );
    }

    if (request.isJitterSensitive) {
      return const RoutingDecision(
        channel: NetChannel.dio,
        reason: 'jitter_sensitive_tag',
      );
    }

    final uri = Uri.tryParse(request.url);
    if (uri != null && featureFlag.isDioDenyListMatch(uri)) {
      return const RoutingDecision(
        channel: NetChannel.dio,
        reason: 'dio_deny_list',
      );
    }

    if (request.isTransferTask) {
      return const RoutingDecision(
        channel: NetChannel.rust,
        reason: 'transfer_task',
      );
    }

    if (request.expectLargeResponse) {
      return const RoutingDecision(
        channel: NetChannel.rust,
        reason: 'expect_large_response',
      );
    }

    if (request.contentLengthHint != null &&
        request.contentLengthHint! >= featureFlag.rustBodyThresholdBytes) {
      return const RoutingDecision(
        channel: NetChannel.rust,
        reason: 'large_content_hint',
      );
    }

    if (uri != null && featureFlag.isRustAllowListMatch(uri)) {
      return const RoutingDecision(
        channel: NetChannel.rust,
        reason: 'allow_list',
      );
    }

    return const RoutingDecision(
      channel: NetChannel.dio,
      reason: 'default_dio',
    );
  }
}
