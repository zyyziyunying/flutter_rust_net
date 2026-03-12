import 'net_models.dart';

String? normalizeBaseUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  var normalized = trimmed;
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

bool hasBaseUrl(String raw) => normalizeBaseUrl(raw) != null;

NetRequest resolveNetRequestUrl(
  NetRequest request, {
  bool requireBaseUrlForRelative = true,
}) {
  final resolvedUrl = requireBaseUrlForRelative
      ? resolveUrl(
          request.url,
          baseUrl: request.baseUrl,
          urlLabel: 'NetRequest.url',
          baseUrlLabel: 'NetRequest.baseUrl',
        )
      : maybeResolveUrl(
          request.url,
          baseUrl: request.baseUrl,
          urlLabel: 'NetRequest.url',
          baseUrlLabel: 'NetRequest.baseUrl',
        );
  if (resolvedUrl == request.url) {
    return request;
  }
  return request.withResolvedUrl(resolvedUrl);
}

NetTransferTaskRequest resolveNetTransferTaskUrl(
  NetTransferTaskRequest request, {
  bool requireBaseUrlForRelative = true,
}) {
  final resolvedUrl = requireBaseUrlForRelative
      ? resolveUrl(
          request.url,
          baseUrl: request.baseUrl,
          urlLabel: 'NetTransferTaskRequest.url',
          baseUrlLabel: 'NetTransferTaskRequest.baseUrl',
        )
      : maybeResolveUrl(
          request.url,
          baseUrl: request.baseUrl,
          urlLabel: 'NetTransferTaskRequest.url',
          baseUrlLabel: 'NetTransferTaskRequest.baseUrl',
        );
  if (resolvedUrl == request.url) {
    return request;
  }
  return request.withResolvedUrl(resolvedUrl);
}

String maybeResolveUrl(
  String url, {
  String baseUrl = '',
  String urlLabel = 'url',
  String baseUrlLabel = 'baseUrl',
}) {
  if (!hasBaseUrl(baseUrl)) {
    return url.trim();
  }
  return resolveUrl(
    url,
    baseUrl: baseUrl,
    urlLabel: urlLabel,
    baseUrlLabel: baseUrlLabel,
  );
}

String resolveUrl(
  String url, {
  required String baseUrl,
  String urlLabel = 'url',
  String baseUrlLabel = 'baseUrl',
}) {
  final trimmedUrl = url.trim();
  if (trimmedUrl.isEmpty) {
    throw ArgumentError.value(url, urlLabel, 'must not be empty');
  }
  if (_isAbsoluteUrl(trimmedUrl)) {
    return trimmedUrl;
  }

  final normalizedBaseUrl = normalizeBaseUrl(baseUrl);
  if (normalizedBaseUrl == null) {
    throw ArgumentError.value(
      url,
      urlLabel,
      'relative URL requires a non-empty $baseUrlLabel',
    );
  }

  final baseUri = Uri.tryParse(normalizedBaseUrl);
  if (baseUri == null || !baseUri.hasScheme || !baseUri.hasAuthority) {
    throw ArgumentError.value(
      baseUrl,
      baseUrlLabel,
      'must be an absolute http/https URL',
    );
  }
  if (baseUri.scheme != 'http' && baseUri.scheme != 'https') {
    throw ArgumentError.value(baseUrl, baseUrlLabel, 'must use http or https');
  }
  if (baseUri.hasQuery || baseUri.hasFragment) {
    throw ArgumentError.value(
      baseUrl,
      baseUrlLabel,
      'must not contain query or fragment',
    );
  }

  if (trimmedUrl.startsWith('?') || trimmedUrl.startsWith('#')) {
    return '$normalizedBaseUrl$trimmedUrl';
  }
  if (trimmedUrl.startsWith('/')) {
    return '$normalizedBaseUrl$trimmedUrl';
  }
  return '$normalizedBaseUrl/$trimmedUrl';
}

bool _isAbsoluteUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null && uri.hasScheme && uri.hasAuthority;
}
