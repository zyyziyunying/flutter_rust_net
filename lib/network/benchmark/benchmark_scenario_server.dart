import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'benchmark_types.dart';

const String scenarioBenchChannelHeader = 'x-network-bench-channel';

class ScenarioChannelCacheTelemetry {
  final int originRequests;
  final int conditionalRequests;
  final int repeatedOriginRequests;

  const ScenarioChannelCacheTelemetry({
    required this.originRequests,
    required this.conditionalRequests,
    required this.repeatedOriginRequests,
  });

  static const zero = ScenarioChannelCacheTelemetry(
    originRequests: 0,
    conditionalRequests: 0,
    repeatedOriginRequests: 0,
  );
}

class ScenarioServer {
  final HttpServer _server;
  final BenchmarkConfig _config;
  final BenchLogger _logger;
  final Uint8List _largePayload;
  final List<int> _largeJsonPayload;
  final List<int> _smallJsonPayload;
  final Map<String, _ChannelCacheTelemetryCollector> _cacheTelemetryByChannel =
      {};

  ScenarioServer._({
    required HttpServer server,
    required BenchmarkConfig config,
    required BenchLogger logger,
    required Uint8List largePayload,
    required List<int> largeJsonPayload,
    required List<int> smallJsonPayload,
  })  : _server = server,
        _config = config,
        _logger = logger,
        _largePayload = largePayload,
        _largeJsonPayload = largeJsonPayload,
        _smallJsonPayload = smallJsonPayload;

  String get baseUrl => 'http://${_server.address.address}:${_server.port}';

  static Future<ScenarioServer> start(
    BenchmarkConfig config, {
    required BenchLogger logger,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final largePayload = _buildLargePayload(config.largePayloadBytes);
    final largeJsonPayload = _buildLargeJsonPayload(config.largePayloadBytes);
    final smallJsonPayload = utf8.encode(
      jsonEncode({
        'title': 'network-bench',
        'ok': true,
        'payload': List.filled(160, 'x').join(),
      }),
    );

    final instance = ScenarioServer._(
      server: server,
      config: config,
      logger: logger,
      largePayload: largePayload,
      largeJsonPayload: largeJsonPayload,
      smallJsonPayload: smallJsonPayload,
    );
    instance._listen();
    logger('[network-bench] local scenario server at ${instance.baseUrl}');
    return instance;
  }

  void _listen() {
    _server.listen((request) async {
      _recordCacheTelemetry(request);
      if (request.method != 'GET') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }

      try {
        switch (request.uri.path) {
          case '/bench/small-json':
            await _handleSmallJson(request);
            return;
          case '/bench/large-json':
            await _handleLargeJson(request);
            return;
          case '/bench/large-payload':
            await _handleLargePayload(request);
            return;
          case '/bench/jitter':
            await _handleJitter(request);
            return;
          case '/bench/flaky':
            await _handleFlaky(request);
            return;
          default:
            request.response.statusCode = HttpStatus.notFound;
            request.response.write('not found');
            await request.response.close();
        }
      } catch (error) {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('server_error:$error');
        await request.response.close();
      }
    });
  }

  Future<void> _handleSmallJson(HttpRequest request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..headers.set(HttpHeaders.contentLengthHeader, _smallJsonPayload.length)
      ..add(_smallJsonPayload);
    await request.response.close();
  }

  Future<void> _handleLargePayload(HttpRequest request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.binary
      ..headers.set(HttpHeaders.contentLengthHeader, _largePayload.length)
      ..add(_largePayload);
    await request.response.close();
  }

  Future<void> _handleLargeJson(HttpRequest request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..headers.set(HttpHeaders.contentLengthHeader, _largeJsonPayload.length)
      ..add(_largeJsonPayload);
    await request.response.close();
  }

  Future<void> _handleJitter(HttpRequest request) async {
    final id = _parseInt(request.uri.queryParameters['id'], fallback: 0);
    final baseDelayMs = _parseInt(
      request.uri.queryParameters['baseDelayMs'],
      fallback: _config.jitterBaseDelayMs,
    );
    final extraDelayMs = _parseInt(
      request.uri.queryParameters['extraDelayMs'],
      fallback: _config.jitterExtraDelayMs,
    );
    final delayMs = baseDelayMs + (id.abs() % (extraDelayMs + 1));

    await Future<void>.delayed(Duration(milliseconds: delayMs));
    final body = utf8.encode(
      jsonEncode({'id': id, 'delayMs': delayMs, 'kind': 'jitter'}),
    );
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..headers.set(HttpHeaders.contentLengthHeader, body.length)
      ..add(body);
    await request.response.close();
  }

  Future<void> _handleFlaky(HttpRequest request) async {
    final id = _parseInt(request.uri.queryParameters['id'], fallback: 0);
    final failureEvery = _parseInt(
      request.uri.queryParameters['failureEvery'],
      fallback: _config.flakyFailureEvery,
    );
    final shouldFail = ((id + 1).abs() % failureEvery) == 0;

    if (shouldFail) {
      request.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..headers.contentType = ContentType.text
        ..write('temporary_unavailable');
      await request.response.close();
      return;
    }

    final body = utf8.encode(
      jsonEncode({'id': id, 'kind': 'flaky', 'ok': true}),
    );
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..headers.set(HttpHeaders.contentLengthHeader, body.length)
      ..add(body);
    await request.response.close();
  }

  Future<void> close() async {
    _logger('[network-bench] closing local scenario server');
    await _server.close(force: true);
  }

  ScenarioChannelCacheTelemetry cacheTelemetryForChannel(String channelName) {
    return _cacheTelemetryByChannel[channelName]?.snapshot() ??
        ScenarioChannelCacheTelemetry.zero;
  }

  void _recordCacheTelemetry(HttpRequest request) {
    final channelName = _resolveBenchChannel(request);
    if (channelName == null) {
      return;
    }
    final collector = _cacheTelemetryByChannel.putIfAbsent(
      channelName,
      _ChannelCacheTelemetryCollector.new,
    );
    collector.record(
      key: _normalizeRequestKey(request.uri),
      conditional: _hasConditionalHeaders(request),
    );
  }

  String? _resolveBenchChannel(HttpRequest request) {
    final raw = request.headers.value(scenarioBenchChannelHeader)?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    for (final channel in BenchmarkChannel.values) {
      if (channel.cliName == raw) {
        return raw;
      }
    }
    return null;
  }

  static bool _hasConditionalHeaders(HttpRequest request) {
    final ifNoneMatch = request.headers.value(HttpHeaders.ifNoneMatchHeader);
    if (ifNoneMatch != null && ifNoneMatch.trim().isNotEmpty) {
      return true;
    }
    final ifModifiedSince = request.headers.value(
      HttpHeaders.ifModifiedSinceHeader,
    );
    return ifModifiedSince != null && ifModifiedSince.trim().isNotEmpty;
  }

  static String _normalizeRequestKey(Uri uri) {
    if (uri.queryParametersAll.isEmpty) {
      return uri.path;
    }
    final entries = uri.queryParametersAll.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final parts = <String>[];
    for (final entry in entries) {
      for (final value in entry.value) {
        parts.add('${entry.key}=$value');
      }
    }
    return '${uri.path}?${parts.join('&')}';
  }
}

Uint8List _buildLargePayload(int bytes) {
  final data = Uint8List(bytes);
  for (var i = 0; i < bytes; i += 1) {
    data[i] = i % 251;
  }
  return data;
}

List<int> _buildLargeJsonPayload(int targetBytes) {
  final safeTargetBytes = max(64 * 1024, targetBytes);
  var payloadChars = max(1024, safeTargetBytes - 256);
  var encoded = const <int>[];

  for (var i = 0; i < 3; i += 1) {
    final payload = List.filled(payloadChars, 'x').join();
    encoded = utf8.encode(
      jsonEncode({
        'title': 'network-bench-large-json',
        'ok': true,
        'payload': payload,
      }),
    );

    final delta = safeTargetBytes - encoded.length;
    if (delta.abs() <= 512) {
      break;
    }
    payloadChars = max(1024, payloadChars + delta);
  }

  return encoded;
}

int _parseInt(String? raw, {required int fallback}) {
  final value = int.tryParse(raw ?? '');
  return value ?? fallback;
}

class _ChannelCacheTelemetryCollector {
  int originRequests = 0;
  int conditionalRequests = 0;
  int repeatedOriginRequests = 0;
  final Set<String> _seenOriginKeys = <String>{};

  void record({required String key, required bool conditional}) {
    if (conditional) {
      conditionalRequests += 1;
      return;
    }
    originRequests += 1;
    if (!_seenOriginKeys.add(key)) {
      repeatedOriginRequests += 1;
    }
  }

  ScenarioChannelCacheTelemetry snapshot() {
    return ScenarioChannelCacheTelemetry(
      originRequests: originRequests,
      conditionalRequests: conditionalRequests,
      repeatedOriginRequests: repeatedOriginRequests,
    );
  }
}
