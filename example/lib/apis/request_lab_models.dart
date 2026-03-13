import 'package:flutter_rust_net/flutter_rust_net.dart';

enum RequestRouteMode {
  auto('Auto'),
  dio('Force Dio'),
  rust('Force Rust');

  const RequestRouteMode(this.label);

  final String label;

  NetChannel? get forceChannel {
    switch (this) {
      case RequestRouteMode.auto:
        return null;
      case RequestRouteMode.dio:
        return NetChannel.dio;
      case RequestRouteMode.rust:
        return NetChannel.rust;
    }
  }
}

enum RequestBodyMode {
  empty('Empty'),
  json('JSON'),
  text('Plain Text');

  const RequestBodyMode(this.label);

  final String label;
}

class RequestPreset {
  final String label;
  final NetHttpMethod method;
  final String url;
  final String headersText;
  final String queryText;
  final RequestBodyMode bodyMode;
  final String bodyText;
  final RequestRouteMode routeMode;
  final bool autoUseRust;
  final bool enableFallback;
  final bool expectLargeResponse;
  final String? baseUrlOverride;

  const RequestPreset({
    required this.label,
    required this.method,
    required this.url,
    this.headersText = '',
    this.queryText = '',
    this.bodyMode = RequestBodyMode.empty,
    this.bodyText = '',
    this.routeMode = RequestRouteMode.auto,
    this.autoUseRust = false,
    this.enableFallback = true,
    this.expectLargeResponse = false,
    this.baseUrlOverride,
  });

  String resolveBaseUrl(String defaultBaseUrl) {
    return baseUrlOverride ?? defaultBaseUrl;
  }
}

class RequestResult {
  final bool success;
  final String? errorMessage;
  final int? statusCode;
  final String? requestId;
  final NetChannel? channel;
  final String? routeReason;
  final bool fromFallback;
  final String? fallbackReason;
  final int? costMs;
  final int? materializedBytes;
  final int? bridgeBytes;
  final Map<String, String> headers;
  final String bodyText;

  const RequestResult.success({
    required this.statusCode,
    required this.requestId,
    required this.channel,
    required this.routeReason,
    required this.fromFallback,
    required this.fallbackReason,
    required this.costMs,
    required this.materializedBytes,
    required this.bridgeBytes,
    required this.headers,
    required this.bodyText,
  }) : success = true,
       errorMessage = null;

  const RequestResult.error({required String message})
    : success = false,
      errorMessage = message,
      statusCode = null,
      requestId = null,
      channel = null,
      routeReason = null,
      fromFallback = false,
      fallbackReason = null,
      costMs = null,
      materializedBytes = null,
      bridgeBytes = null,
      headers = const {},
      bodyText = '';

  String get summaryLines {
    final lines = <String>[
      'status=${statusCode ?? '-'}',
      'channel=${channel?.name ?? '-'}',
      'requestId=${requestId ?? '-'}',
      'routeReason=${routeReason ?? '-'}',
      'fromFallback=$fromFallback',
      'fallbackReason=${fallbackReason ?? '-'}',
      'costMs=${costMs ?? '-'}',
      'bodyBytes=${materializedBytes ?? '-'}',
      'bridgeBytes=${bridgeBytes ?? '-'}',
    ];
    return lines.join('\n');
  }

  String get headersText {
    if (headers.isEmpty) {
      return '[no headers]';
    }
    final entries = headers.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return entries.map((entry) => '${entry.key}: ${entry.value}').join('\n');
  }
}
