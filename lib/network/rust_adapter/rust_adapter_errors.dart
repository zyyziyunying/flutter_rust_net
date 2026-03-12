part of 'package:flutter_rust_net/network/rust_adapter.dart';

class _RustAdapterErrors {
  static const String _rustRebuildHintCommand =
      'cd ../native/rust/net_engine && cargo build --release -p net_engine';

  static NetException mapRustException(Object error, {String? requestId}) {
    final message = '$error';
    if (message.contains('not initialized')) {
      return NetException.infrastructure(
        message: message,
        channel: NetChannel.rust,
        requestId: requestId,
      );
    }
    if (message.contains('Failed to lookup symbol') ||
        message.contains('loadExternalLibrary') ||
        message.contains('cannot open shared object file') ||
        message.contains('The specified module could not be found')) {
      return NetException.infrastructure(
        message: 'Rust bridge not available: $message',
        channel: NetChannel.rust,
        requestId: requestId,
        cause: error,
      );
    }
    return mapRustError(message, requestId: requestId);
  }

  static NetException mapRustError(
    String message, {
    rust_api.NetErrorKind? kind,
    int? statusCode,
    String? requestId,
  }) {
    if (kind != null) {
      return _mapTypedRustError(
        kind,
        message,
        statusCode: statusCode,
        requestId: requestId,
      );
    }
    return _mapLegacyRustError(
      message,
      statusCode: statusCode,
      requestId: requestId,
    );
  }

  static NetException wrapInitError(Object error, String text) {
    if (_looksLikeStaleNativeBridge(text)) {
      return NetException.infrastructure(
        message:
            'Rust init failed: $error. Native net_engine library may be stale; '
            'rebuild with `$_rustRebuildHintCommand`.',
        channel: NetChannel.rust,
        cause: error,
      );
    }
    return NetException.infrastructure(
      message: 'Rust init failed: $error',
      channel: NetChannel.rust,
      cause: error,
    );
  }

  static NetException _mapTypedRustError(
    rust_api.NetErrorKind kind,
    String message, {
    int? statusCode,
    String? requestId,
  }) {
    final parsedStatusCode = statusCode == null || statusCode == 0
        ? null
        : statusCode;
    switch (kind) {
      case rust_api.NetErrorKind.timeout:
        return NetException(
          code: NetErrorCode.timeout,
          message: message,
          channel: NetChannel.rust,
          fallbackEligible: true,
          requestId: requestId,
        );
      case rust_api.NetErrorKind.dns:
        return NetException(
          code: NetErrorCode.dns,
          message: message,
          channel: NetChannel.rust,
          fallbackEligible: true,
          requestId: requestId,
        );
      case rust_api.NetErrorKind.tls:
        return NetException(
          code: NetErrorCode.tls,
          message: message,
          channel: NetChannel.rust,
          fallbackEligible: true,
          requestId: requestId,
        );
      case rust_api.NetErrorKind.http4Xx:
        return NetException(
          code: NetErrorCode.http4xx,
          message: message,
          channel: NetChannel.rust,
          statusCode: parsedStatusCode,
          fallbackEligible: false,
          requestId: requestId,
        );
      case rust_api.NetErrorKind.http5Xx:
        return NetException(
          code: NetErrorCode.http5xx,
          message: message,
          channel: NetChannel.rust,
          statusCode: parsedStatusCode,
          fallbackEligible: false,
          requestId: requestId,
        );
      case rust_api.NetErrorKind.canceled:
        return NetException(
          code: NetErrorCode.canceled,
          message: message,
          channel: NetChannel.rust,
          fallbackEligible: false,
          requestId: requestId,
        );
      case rust_api.NetErrorKind.parse:
        return NetException(
          code: NetErrorCode.parse,
          message: message,
          channel: NetChannel.rust,
          fallbackEligible: false,
          requestId: requestId,
        );
      case rust_api.NetErrorKind.io:
        return NetException(
          code: NetErrorCode.io,
          message: message,
          channel: NetChannel.rust,
          fallbackEligible: true,
          requestId: requestId,
        );
      case rust_api.NetErrorKind.internal:
        return NetException(
          code: NetErrorCode.internal,
          message: message,
          channel: NetChannel.rust,
          fallbackEligible: false,
          requestId: requestId,
        );
    }
  }

  static NetException _mapLegacyRustError(
    String message, {
    int? statusCode,
    String? requestId,
  }) {
    final normalized = message.trim().toLowerCase();
    if (normalized.startsWith('timeout:')) {
      return NetException(
        code: NetErrorCode.timeout,
        message: message,
        channel: NetChannel.rust,
        fallbackEligible: true,
        requestId: requestId,
      );
    }
    if (normalized.startsWith('dns:')) {
      return NetException(
        code: NetErrorCode.dns,
        message: message,
        channel: NetChannel.rust,
        fallbackEligible: true,
        requestId: requestId,
      );
    }
    if (normalized.startsWith('tls:')) {
      return NetException(
        code: NetErrorCode.tls,
        message: message,
        channel: NetChannel.rust,
        fallbackEligible: true,
        requestId: requestId,
      );
    }
    if (normalized.startsWith('parse:')) {
      return NetException(
        code: NetErrorCode.parse,
        message: message,
        channel: NetChannel.rust,
        fallbackEligible: false,
        requestId: requestId,
      );
    }
    if (normalized.startsWith('io:')) {
      return NetException(
        code: NetErrorCode.io,
        message: message,
        channel: NetChannel.rust,
        fallbackEligible: true,
        requestId: requestId,
      );
    }
    if (normalized.startsWith('canceled:')) {
      return NetException(
        code: NetErrorCode.canceled,
        message: message,
        channel: NetChannel.rust,
        fallbackEligible: false,
        requestId: requestId,
      );
    }

    var parsedStatusCode = statusCode == null || statusCode == 0
        ? null
        : statusCode;
    if (parsedStatusCode == null) {
      final match = RegExp(r'^http\s+(\d{3})[:\s]').firstMatch(normalized);
      if (match != null) {
        parsedStatusCode = int.tryParse(match.group(1)!);
      }
    }
    if (parsedStatusCode != null) {
      final code = parsedStatusCode >= 400 && parsedStatusCode < 500
          ? NetErrorCode.http4xx
          : NetErrorCode.http5xx;
      return NetException(
        code: code,
        message: message,
        channel: NetChannel.rust,
        statusCode: parsedStatusCode,
        fallbackEligible: false,
        requestId: requestId,
      );
    }

    if (normalized.contains('not initialized')) {
      return NetException.infrastructure(
        message: message,
        channel: NetChannel.rust,
        requestId: requestId,
      );
    }

    if (normalized.startsWith('internal:')) {
      return NetException(
        code: NetErrorCode.internal,
        message: message,
        channel: NetChannel.rust,
        fallbackEligible: false,
        requestId: requestId,
      );
    }

    return NetException(
      code: NetErrorCode.internal,
      message: message,
      channel: NetChannel.rust,
      fallbackEligible: false,
      requestId: requestId,
    );
  }

  static bool _looksLikeStaleNativeBridge(String text) {
    final lower = text.toLowerCase();
    return lower.contains('unexpectedeof') ||
        lower.contains('failed to fill whole buffer') ||
        lower.contains('content hash on dart side');
  }
}
