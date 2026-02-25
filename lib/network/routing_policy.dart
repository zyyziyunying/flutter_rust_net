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

    return const RoutingDecision(
      channel: NetChannel.rust,
      reason: 'rust_enabled',
    );
  }
}
