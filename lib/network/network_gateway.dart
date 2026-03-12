import 'net_adapter.dart';
import 'net_feature_flag.dart';
import 'net_models.dart';
import 'routing_policy.dart';

class NetworkGateway {
  static const int _maxTrackedTransferTasks = 256;
  static const String _rustNotReadyRouteSuffix = 'rust_not_ready_dio';
  static const Set<String> _idempotentMethods = {
    'GET',
    'HEAD',
    'OPTIONS',
    'TRACE',
    'PUT',
    'DELETE',
  };
  static const Set<NetErrorCode> _fallbackEligibleCodes = {
    NetErrorCode.timeout,
    NetErrorCode.dns,
    NetErrorCode.tls,
    NetErrorCode.io,
    NetErrorCode.infrastructure,
  };
  static const Set<NetTransferEventKind> _terminalTransferEventKinds = {
    NetTransferEventKind.completed,
    NetTransferEventKind.failed,
    NetTransferEventKind.canceled,
  };

  final RoutingPolicy routingPolicy;
  final NetFeatureFlag featureFlag;
  final NetAdapter dioAdapter;
  final NetAdapter rustAdapter;
  final Map<String, NetChannel> _transferTaskChannels = <String, NetChannel>{};

  NetworkGateway({
    required this.routingPolicy,
    required this.featureFlag,
    required this.dioAdapter,
    required this.rustAdapter,
  });

  Future<NetResponse> request(
    NetRequest request, {
    NetChannel? forceChannel,
  }) async {
    final effectiveRequest = forceChannel == null
        ? request
        : request.withForceChannel(forceChannel);
    final decision = routingPolicy.decide(effectiveRequest, featureFlag);

    if (decision.channel == NetChannel.rust) {
      if (!rustAdapter.isReady) {
        final response = await dioAdapter.request(effectiveRequest);
        return response.withMeta(
          routeReason: '${decision.reason} -> $_rustNotReadyRouteSuffix',
        );
      }
      return _requestFromRust(effectiveRequest, routeReason: decision.reason);
    }

    final response = await dioAdapter.request(effectiveRequest);
    return response.withMeta(routeReason: decision.reason);
  }

  Future<NetTransferTaskStartResult> startTransferTask(
    NetTransferTaskRequest request, {
    NetChannel? forceChannel,
  }) async {
    final effectiveRequest = forceChannel == null
        ? request
        : request.withForceChannel(forceChannel);
    final decision = routingPolicy.decide(
      _toTransferProbeRequest(effectiveRequest),
      featureFlag,
    );

    if (decision.channel == NetChannel.rust) {
      if (!rustAdapter.isReady) {
        return _startTransferOnChannel(
          request: effectiveRequest,
          channel: NetChannel.dio,
          routeReason: '${decision.reason} -> $_rustNotReadyRouteSuffix',
        );
      }
      return _startTransferFromRust(
        effectiveRequest,
        routeReason: decision.reason,
      );
    }

    return _startTransferOnChannel(
      request: effectiveRequest,
      channel: NetChannel.dio,
      routeReason: decision.reason,
    );
  }

  Future<List<NetTransferEvent>> pollTransferEvents({int limit = 64}) async {
    if (limit <= 0) {
      return const [];
    }

    final rustEvents = await _safePollTransferEvents(rustAdapter, limit: limit);
    final remaining = limit - rustEvents.length;
    final dioEvents = remaining > 0
        ? await _safePollTransferEvents(dioAdapter, limit: remaining)
        : const <NetTransferEvent>[];

    final merged = [...rustEvents, ...dioEvents];
    for (final event in merged) {
      if (_terminalTransferEventKinds.contains(event.kind)) {
        _transferTaskChannels.remove(event.id);
      } else {
        _trackTransferTaskChannel(event.id, event.channel);
      }
    }
    return merged;
  }

  Future<bool> cancelTransferTask(String taskId) async {
    final tracked = _transferTaskChannels[taskId];
    if (tracked == NetChannel.rust) {
      final canceled = await rustAdapter.cancelTransferTask(taskId);
      if (canceled) {
        _transferTaskChannels.remove(taskId);
        return true;
      }
      _transferTaskChannels.remove(taskId);
      return _safeCancelTransferTask(dioAdapter, taskId);
    }
    if (tracked == NetChannel.dio) {
      final canceled = await dioAdapter.cancelTransferTask(taskId);
      if (canceled) {
        _transferTaskChannels.remove(taskId);
        return true;
      }
      _transferTaskChannels.remove(taskId);
      return _safeCancelTransferTask(rustAdapter, taskId);
    }

    final dioCanceled = await _safeCancelTransferTask(dioAdapter, taskId);
    final rustCanceled = await _safeCancelTransferTask(rustAdapter, taskId);
    final canceled = dioCanceled || rustCanceled;
    if (canceled) {
      _transferTaskChannels.remove(taskId);
    }
    return canceled;
  }

  Future<NetResponse> _requestFromRust(
    NetRequest request, {
    required String routeReason,
  }) async {
    try {
      final response = await rustAdapter.request(request);
      return response.withMeta(routeReason: routeReason);
    } catch (error) {
      final netError = error is NetException
          ? error
          : NetException.infrastructure(
              message: 'Rust request failed: $error',
              channel: NetChannel.rust,
              cause: error,
            );

      if (!_shouldFallback(netError, request)) {
        throw netError;
      }

      final fallbackResponse = await dioAdapter.request(
        request,
        fromFallback: true,
      );
      return fallbackResponse.withMeta(
        routeReason: '$routeReason -> fallback_dio',
        fallbackReason: netError.code.name,
        fromFallback: true,
        fallbackError: netError,
      );
    }
  }

  Future<NetTransferTaskStartResult> _startTransferFromRust(
    NetTransferTaskRequest request, {
    required String routeReason,
  }) async {
    try {
      return await _startTransferOnChannel(
        request: request,
        channel: NetChannel.rust,
        routeReason: routeReason,
      );
    } catch (error) {
      final netError = error is NetException
          ? error
          : NetException.infrastructure(
              message: 'Rust transfer start failed: $error',
              channel: NetChannel.rust,
              cause: error,
            );

      if (!_shouldTransferFallback(netError, request)) {
        throw netError;
      }

      return await _startTransferOnChannel(
        request: request,
        channel: NetChannel.dio,
        routeReason: '$routeReason -> fallback_dio',
        fromFallback: true,
        fallbackReason: netError.code.name,
        fallbackError: netError,
      );
    }
  }

  Future<NetTransferTaskStartResult> _startTransferOnChannel({
    required NetTransferTaskRequest request,
    required NetChannel channel,
    required String routeReason,
    bool fromFallback = false,
    String? fallbackReason,
    NetException? fallbackError,
  }) async {
    final adapter = channel == NetChannel.rust ? rustAdapter : dioAdapter;
    final taskId = await adapter.startTransferTask(request);
    _trackTransferTaskChannel(taskId, channel);
    return NetTransferTaskStartResult(
      taskId: taskId,
      channel: channel,
      routeReason: routeReason,
      fromFallback: fromFallback,
      fallbackReason: fallbackReason,
      fallbackError: fallbackError,
    );
  }

  bool _shouldFallback(NetException error, NetRequest request) {
    return featureFlag.enableFallback &&
        error.channel == NetChannel.rust &&
        _fallbackEligibleCodes.contains(error.code) &&
        error.fallbackEligible &&
        _isRequestFallbackSafe(request);
  }

  bool _shouldTransferFallback(
    NetException error,
    NetTransferTaskRequest request,
  ) {
    return featureFlag.enableFallback &&
        error.channel == NetChannel.rust &&
        _fallbackEligibleCodes.contains(error.code) &&
        error.fallbackEligible &&
        _isTransferFallbackSafe(request);
  }

  bool _isRequestFallbackSafe(NetRequest request) {
    final method = request.method.trim().toUpperCase();
    if (_idempotentMethods.contains(method)) {
      return true;
    }

    for (final entry in request.headers.entries) {
      if (entry.key.toLowerCase() == 'idempotency-key' &&
          entry.value.trim().isNotEmpty) {
        return true;
      }
    }

    return false;
  }

  bool _isTransferFallbackSafe(NetTransferTaskRequest request) {
    if (request.kind == NetTransferKind.download) {
      return !request.isResumeDownload;
    }

    return _isRequestFallbackSafe(
      NetRequest(
        method: request.method,
        url: request.url,
        headers: request.headers,
      ),
    );
  }

  NetRequest _toTransferProbeRequest(NetTransferTaskRequest request) {
    return NetRequest(
      method: request.method,
      url: request.url,
      headers: request.headers,
      forceChannel: request.forceChannel,
    );
  }

  Future<List<NetTransferEvent>> _safePollTransferEvents(
    NetAdapter adapter, {
    required int limit,
  }) async {
    try {
      return adapter.pollTransferEvents(limit: limit);
    } on UnsupportedError {
      return const [];
    } on NetException catch (error) {
      if (_isTransferInfrastructureIssue(error)) {
        return const [];
      }
      rethrow;
    }
  }

  Future<bool> _safeCancelTransferTask(
    NetAdapter adapter,
    String taskId,
  ) async {
    try {
      return adapter.cancelTransferTask(taskId);
    } on UnsupportedError {
      return false;
    } on NetException catch (error) {
      if (_isTransferInfrastructureIssue(error)) {
        return false;
      }
      rethrow;
    }
  }

  bool _isTransferInfrastructureIssue(NetException error) {
    return error.code == NetErrorCode.infrastructure ||
        error.code == NetErrorCode.internal;
  }

  void _trackTransferTaskChannel(String taskId, NetChannel channel) {
    _transferTaskChannels[taskId] = channel;
    final overflow = _transferTaskChannels.length - _maxTrackedTransferTasks;
    if (overflow <= 0) {
      return;
    }

    final staleTaskIds = _transferTaskChannels.keys
        .take(overflow)
        .toList(growable: false);
    for (final staleTaskId in staleTaskIds) {
      _transferTaskChannels.remove(staleTaskId);
    }
  }
}
