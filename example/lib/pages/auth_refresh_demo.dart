import 'dart:async';

import 'package:common/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rust_net/flutter_rust_net.dart';

class AuthRefreshDemoCard extends StatefulWidget {
  const AuthRefreshDemoCard({super.key});

  @override
  State<AuthRefreshDemoCard> createState() => _AuthRefreshDemoCardState();
}

class _AuthRefreshDemoCardState extends State<AuthRefreshDemoCard> {
  CommonAuth? _auth;
  _RefreshDemoClientSetup? _clientSetup;
  StreamSubscription<AuthState>? _stateSubscription;

  TokenRefreshTrace? _lastTrace;
  bool _initializingClient = true;
  bool _running = false;
  String _statusText = AuthStatus.unknown.name;
  String _accessTokenPreview = '-';
  String _clientNote = 'Initializing external refresh client...';
  String _lastError = '';

  @override
  void initState() {
    super.initState();
    unawaited(_initializeAuth());
  }

  @override
  void dispose() {
    final subscription = _stateSubscription;
    final auth = _auth;
    final clientSetup = _clientSetup;
    _stateSubscription = null;
    _auth = null;
    _clientSetup = null;
    unawaited(_disposeResources(subscription, auth, clientSetup));
    super.dispose();
  }

  Future<void> _initializeAuth() async {
    try {
      final clientSetup = await _RefreshDemoClientSetup.create();
      final refresher = RustNetAuthTokenRefresher(
        client: clientSetup.client,
        onTrace: _onRefreshTrace,
        onError: _onRefreshError,
      );
      final auth = CommonAuth.memory(tokenRefresher: refresher);

      if (!mounted) {
        await auth.dispose();
        await clientSetup.dispose();
        return;
      }

      _auth = auth;
      _clientSetup = clientSetup;
      _stateSubscription = auth.watchState().listen(_onAuthStateUpdate);
      await auth.bootstrap();

      if (!mounted) {
        return;
      }
      setState(() {
        _initializingClient = false;
        _clientNote = clientSetup.note;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _initializingClient = false;
        _clientNote = 'Failed to prepare refresh client.';
        _lastError = '$error';
      });
    }
  }

  Future<void> _disposeResources(
    StreamSubscription<AuthState>? subscription,
    CommonAuth? auth,
    _RefreshDemoClientSetup? clientSetup,
  ) async {
    await subscription?.cancel();
    await auth?.dispose();
    await clientSetup?.dispose();
  }

  Future<void> _runRefreshDemo() async {
    final auth = _auth;
    if (_running || _initializingClient || auth == null) {
      return;
    }

    setState(() {
      _running = true;
      _lastTrace = null;
      _lastError = '';
    });

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final expiredSession = AuthSession(
      tokens: AuthTokenPair(
        accessToken: 'expired_access_$nowMs',
        refreshToken: 'demo_refresh_token_$nowMs',
      ),
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      subjectId: 'flutter_rust_net_example_user',
    );

    await auth.setSession(expiredSession);
    final refreshed = await auth.ensureValidSession();

    if (!mounted) {
      return;
    }

    setState(() {
      _running = false;
      if (refreshed == null && _lastError.isEmpty) {
        _lastError = 'refresh failed and session was cleared';
      }
    });
  }

  void _onAuthStateUpdate(AuthState state) {
    if (!mounted) {
      return;
    }
    setState(() {
      _statusText = state.status.name;
      final token = state.session?.tokens.accessToken;
      _accessTokenPreview = _previewToken(token);
    });
  }

  void _onRefreshTrace(TokenRefreshTrace trace) {
    if (!mounted) {
      return;
    }
    setState(() {
      _lastTrace = trace;
    });
  }

  void _onRefreshError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _lastError = message;
    });
  }

  String _previewToken(String? token) {
    if (token == null || token.isEmpty) {
      return '-';
    }
    if (token.length <= 20) {
      return token;
    }
    return '${token.substring(0, 20)}...';
  }

  @override
  Widget build(BuildContext context) {
    final trace = _lastTrace;
    final routeReason = trace?.routeReason ?? '-';
    final channelText = trace == null
        ? '-'
        : '${trace.channel.name}${trace.fromFallback ? ' (fallback)' : ''}';
    final responseText = trace == null
        ? '-'
        : '${trace.statusCode} (${trace.costMs} ms)';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Auth token refresh demo (flutter_rust_net)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Uses BytesFirstNetworkClient.standard() on the default Dio-safe path and '
              'calls https://httpbin.org/uuid to mint a demo access token.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Text(
              'Client: $_clientNote',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _running || _initializingClient
                  ? null
                  : _runRefreshDemo,
              icon: _running
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(
                _initializingClient
                    ? 'Preparing client...'
                    : _running
                    ? 'Refreshing...'
                    : 'Run token refresh',
              ),
            ),
            const SizedBox(height: 10),
            Text('Auth status: $_statusText'),
            Text('Access token: $_accessTokenPreview'),
            Text('Channel: $channelText'),
            Text('Route reason: $routeReason'),
            Text('Response: $responseText'),
            if (_lastError.isNotEmpty)
              Text(
                'Last error: $_lastError',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}

class RustNetAuthTokenRefresher implements AuthTokenRefresher {
  RustNetAuthTokenRefresher({
    required this._client,
    this.refreshUrl = 'https://httpbin.org/uuid',
    this.onTrace,
    this.onError,
  });

  final BytesFirstNetworkClient _client;
  final String refreshUrl;
  final void Function(TokenRefreshTrace trace)? onTrace;
  final void Function(String message)? onError;

  @override
  Future<AuthTokenPair> refresh(AuthTokenPair currentTokens) async {
    try {
      final response = await _client.requestJsonObject(
        NetRequest(
          method: 'GET',
          url: refreshUrl,
          headers: _buildHeaders(currentTokens),
        ),
      );
      _emitTrace(response.rawResponse);
      _assertSuccessStatus(response.rawResponse.statusCode);

      final nextAccessToken = _extractAccessToken(response.decoded);
      return AuthTokenPair(
        accessToken: nextAccessToken,
        refreshToken: currentTokens.refreshToken,
      );
    } catch (error) {
      onError?.call('$error');
      rethrow;
    }
  }

  Map<String, String> _buildHeaders(AuthTokenPair currentTokens) {
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

  void _emitTrace(NetResponse response) {
    onTrace?.call(
      TokenRefreshTrace(
        channel: response.channel,
        fromFallback: response.fromFallback,
        routeReason: response.routeReason ?? '-',
        statusCode: response.statusCode,
        costMs: response.costMs,
      ),
    );
  }

  void _assertSuccessStatus(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) {
      return;
    }
    throw StateError('refresh request failed with status code $statusCode');
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

    throw const FormatException(
      'response missing uuid/accessToken/token field',
    );
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
}

class TokenRefreshTrace {
  const TokenRefreshTrace({
    required this.channel,
    required this.fromFallback,
    required this.routeReason,
    required this.statusCode,
    required this.costMs,
  });

  final NetChannel channel;
  final bool fromFallback;
  final String routeReason;
  final int statusCode;
  final int costMs;
}

final class _RefreshDemoClientSetup {
  const _RefreshDemoClientSetup({required this.client, required this.note});

  final BytesFirstNetworkClient client;
  final String note;

  static Future<_RefreshDemoClientSetup> create() async {
    return _RefreshDemoClientSetup(
      client: BytesFirstNetworkClient.standard(),
      note:
          'Using BytesFirstNetworkClient.standard(); primary channel is opt-in.',
    );
  }

  Future<void> dispose() async {}
}
