part of 'auth_app_integration_demo_card.dart';

final class _ExampleNetworkClientSetup {
  const _ExampleNetworkClientSetup({
    required this.client,
    required this.modeLabel,
    required this.note,
  });

  final BytesFirstNetworkClient client;
  final String modeLabel;
  final String note;

  static Future<_ExampleNetworkClientSetup> create() async {
    return _ExampleNetworkClientSetup(
      client: BytesFirstNetworkClient.standard(),
      modeLabel: 'Default gateway',
      note:
          'Default Dio-safe path; enable the primary channel explicitly when needed.',
    );
  }

  Future<void> dispose() async {}
}

final class _ExampleAuthApiClient {
  const _ExampleAuthApiClient({
    required this._client,
    required this.loginUrl,
    required this.refreshUrl,
    required this.onLoginTrace,
    required this.onRefreshTrace,
  });

  final BytesFirstNetworkClient _client;
  final String loginUrl;
  final String refreshUrl;
  final void Function(_ExampleRequestTrace trace) onLoginTrace;
  final void Function(_ExampleRequestTrace trace) onRefreshTrace;

  Future<_ExampleLoginResult> login({
    required String username,
    required String password,
  }) async {
    final response = await _client.requestDecoded<String>(
      NetRequest(
        method: 'POST',
        url: loginUrl,
        headers: const <String, String>{
          'accept': 'application/json',
          'content-type': 'application/json',
        },
        body: <String, String>{'username': username, 'password': password},
      ),
      decoder: const Utf8BodyDecoder(),
    );
    onLoginTrace(
      _ExampleRequestTrace.fromResponse(
        url: loginUrl,
        response: response.rawResponse,
      ),
    );
    _assertSuccessStatus(response.rawResponse.statusCode, operation: 'login');

    final payload = _normalizePayload(response.decoded);
    final extractedToken = _extractToken(payload);
    final accessToken = extractedToken ?? _buildDemoAccessToken(username);

    final jwtExpiry = _readJwtExpireTime(accessToken);
    String expiresAtSource;
    if (jwtExpiry != null) {
      expiresAtSource = 'JWT exp claim';
    } else if (extractedToken == null) {
      expiresAtSource = 'demo fallback (+10m; login response exposed no token)';
    } else {
      expiresAtSource =
          'demo fallback (+10m; login response exposed no JWT exp)';
    }
    return _ExampleLoginResult(
      accessToken: accessToken,
      refreshToken: _buildDemoRefreshToken(username),
      expiresAtUtc:
          jwtExpiry ?? DateTime.now().add(const Duration(minutes: 10)),
      expiresAtSource: expiresAtSource,
    );
  }

  Future<AuthTokenPair> refresh(AuthTokenPair currentTokens) async {
    final response = await _client.requestJsonObject(
      NetRequest(
        method: 'GET',
        url: refreshUrl,
        headers: _buildRefreshHeaders(currentTokens),
      ),
    );
    onRefreshTrace(
      _ExampleRequestTrace.fromResponse(
        url: refreshUrl,
        response: response.rawResponse,
      ),
    );
    _assertSuccessStatus(response.rawResponse.statusCode, operation: 'refresh');

    final nextAccessToken = _extractAccessToken(response.decoded);
    return AuthTokenPair(
      accessToken: nextAccessToken,
      refreshToken:
          currentTokens.refreshToken ?? _buildDemoRefreshToken('refresh'),
    );
  }

  void _assertSuccessStatus(int statusCode, {required String operation}) {
    if (statusCode >= 200 && statusCode < 300) {
      return;
    }
    throw StateError('$operation request failed with status code $statusCode');
  }

  Map<String, String> _buildRefreshHeaders(AuthTokenPair currentTokens) {
    final headers = <String, String>{
      'accept': 'application/json',
      'idempotency-key':
          'auth-refresh-${DateTime.now().microsecondsSinceEpoch}',
    };
    final refreshToken = currentTokens.refreshToken;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      headers['x-refresh-token'] = refreshToken;
    }
    return headers;
  }
}

final class _ExampleAuthTokenRefresher implements AuthTokenRefresher {
  const _ExampleAuthTokenRefresher({required this.apiClient});

  final _ExampleAuthApiClient apiClient;

  @override
  Future<AuthTokenPair> refresh(AuthTokenPair currentTokens) {
    return apiClient.refresh(currentTokens);
  }
}

final class _ExampleLoginResult {
  const _ExampleLoginResult({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAtUtc,
    required this.expiresAtSource,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAtUtc;
  final String expiresAtSource;
}

final class _ExampleRequestTrace {
  const _ExampleRequestTrace({
    required this.url,
    required this.channel,
    required this.fromFallback,
    required this.routeReason,
    required this.statusCode,
    required this.costMs,
  });

  factory _ExampleRequestTrace.fromResponse({
    required String url,
    required NetResponse response,
  }) {
    return _ExampleRequestTrace(
      url: url,
      channel: response.channel,
      fromFallback: response.fromFallback,
      routeReason: response.routeReason ?? '-',
      statusCode: response.statusCode,
      costMs: response.costMs,
    );
  }

  final String url;
  final NetChannel channel;
  final bool fromFallback;
  final String routeReason;
  final int statusCode;
  final int costMs;
}

String _buildDemoRefreshToken(String? seed) {
  final normalizedSeed = (seed == null || seed.isEmpty) ? 'demo' : seed;
  return 'demo_refresh_${normalizedSeed}_${DateTime.now().millisecondsSinceEpoch}';
}

String _buildDemoAccessToken(String? seed) {
  final normalizedSeed = (seed == null || seed.isEmpty) ? 'demo' : seed;
  return 'demo_access_${normalizedSeed}_${DateTime.now().millisecondsSinceEpoch}';
}

Object? _normalizePayload(Object? raw) {
  if (raw is! String) {
    return raw;
  }
  try {
    return jsonDecode(raw);
  } catch (_) {
    return raw;
  }
}

String? _extractToken(Object? raw) {
  final payload = _normalizePayload(raw);
  if (payload is String && payload.trim().isNotEmpty) {
    return payload.trim();
  }
  if (payload is! Map) {
    return null;
  }
  return _extractTokenFromMap(payload);
}

String? _extractTokenFromMap(Map payload) {
  String? pickByKey(String key) {
    final value = payload[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  const keys = <String>[
    'token',
    'accessToken',
    'access_token',
    'jwt',
    'bearerToken',
  ];
  for (final key in keys) {
    final token = pickByKey(key);
    if (token != null) {
      return token;
    }
  }

  final nestedCandidates = <Object?>[
    payload['data'],
    payload['result'],
    payload['payload'],
  ];
  for (final candidate in nestedCandidates) {
    if (candidate is Map) {
      final nestedToken = _extractTokenFromMap(candidate);
      if (nestedToken != null && nestedToken.isNotEmpty) {
        return nestedToken;
      }
    } else if (candidate is String && candidate.trim().isNotEmpty) {
      return candidate.trim();
    }
  }
  return null;
}

DateTime? _readJwtExpireTime(String token) {
  final parts = token.split('.');
  if (parts.length != 3) {
    return null;
  }
  try {
    final normalized = base64Url.normalize(parts[1]);
    final decoded = utf8.decode(base64Url.decode(normalized));
    final payload = jsonDecode(decoded);
    if (payload is! Map) {
      return null;
    }
    final exp = payload['exp'];
    final expSeconds = exp is int ? exp : int.tryParse('$exp');
    if (expSeconds == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(expSeconds * 1000, isUtc: true);
  } catch (_) {
    return null;
  }
}

String _extractAccessToken(Object? payload) {
  final map = _normalizeObjectMap(payload);
  if (map == null) {
    throw const FormatException('refresh response is not a json object');
  }

  final uuid = map['uuid'];
  if (uuid is String && uuid.isNotEmpty) {
    return uuid;
  }

  final accessToken = map['accessToken'];
  if (accessToken is String && accessToken.isNotEmpty) {
    return accessToken;
  }

  final token = map['token'];
  if (token is String && token.isNotEmpty) {
    return token;
  }

  throw const FormatException('response missing uuid/accessToken/token field');
}

Map<String, Object?>? _normalizeObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    final normalized = <String, Object?>{};
    for (final entry in value.entries) {
      normalized[entry.key.toString()] = entry.value;
    }
    return normalized;
  }
  return null;
}
