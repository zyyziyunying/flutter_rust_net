import 'dart:async';
import 'dart:convert';

import 'package:common/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rust_net/flutter_rust_net.dart';

import '../../apis/example_app_config.dart';

part 'auth_app_integration_demo_sections.dart';
part 'auth_app_integration_demo_support.dart';

class AuthAppIntegrationDemoCard extends StatefulWidget {
  const AuthAppIntegrationDemoCard({super.key, required this.config});

  final AuthAppDemoConfig config;

  @override
  State<AuthAppIntegrationDemoCard> createState() =>
      _AuthAppIntegrationDemoCardState();
}

class _AuthAppIntegrationDemoCardState
    extends State<AuthAppIntegrationDemoCard> {
  static const String _sessionKey = 'flutter_rust_net_auth_app_demo_v1';

  _ExampleNetworkClientSetup? _clientSetup;
  _ExampleAuthApiClient? _apiClient;
  _ExampleAuthTokenRefresher? _tokenRefresher;
  CommonAuth? _auth;
  StreamSubscription<AuthState>? _stateSubscription;

  bool _initializing = true;
  bool _logining = false;
  bool _refreshing = false;
  bool _recreating = false;
  bool _clearing = false;

  String _clientMode = 'Preparing...';
  String _clientNote = 'Preparing external client...';
  String _statusText = AuthStatus.unknown.name;
  String _subjectIdText = '-';
  String _accessTokenPreview = '-';
  String _refreshTokenPreview = '-';
  String _expiresAtText = '-';
  String _expiresAtSource = '-';
  String _lastMessage = 'Preparing app-style auth demo...';
  String _lastError = '';

  bool _restoredFromStorage = false;
  bool _refreshClearedExpiry = false;
  _ExampleRequestTrace? _lastLoginTrace;
  _ExampleRequestTrace? _lastRefreshTrace;

  bool get _busy =>
      _initializing || _logining || _refreshing || _recreating || _clearing;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeDemo());
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

  Future<void> _initializeDemo() async {
    try {
      final clientSetup = await _ExampleNetworkClientSetup.create();
      final apiClient = _ExampleAuthApiClient(
        client: clientSetup.client,
        loginUrl: widget.config.loginUrl,
        refreshUrl: widget.config.refreshUrl,
        onLoginTrace: _handleLoginTrace,
        onRefreshTrace: _handleRefreshTrace,
      );
      final tokenRefresher = _ExampleAuthTokenRefresher(apiClient: apiClient);
      final auth = _buildAuth(tokenRefresher);

      if (!mounted) {
        await auth.dispose();
        await clientSetup.dispose();
        return;
      }

      await _replaceAuth(auth, disposeCurrent: false);
      await auth.bootstrap();

      if (!mounted) {
        await auth.dispose();
        await clientSetup.dispose();
        return;
      }

      final restored = auth.currentState.session != null;
      setState(() {
        _clientSetup = clientSetup;
        _apiClient = apiClient;
        _tokenRefresher = tokenRefresher;
        _clientMode = clientSetup.modeLabel;
        _clientNote = clientSetup.note;
        _initializing = false;
        _restoredFromStorage = restored;
        _expiresAtSource = restored ? 'restored from secure storage' : '-';
        _lastMessage = restored
            ? 'Recovered a stored session. Tap "Recreate auth" to simulate app restart.'
            : 'Ready. Login, then expire + refresh, then recreate auth to verify secure-storage bootstrap.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _initializing = false;
        _lastError = '$error';
        _clientMode = 'Initialization failed';
        _clientNote = 'Could not prepare the external auth client.';
        _lastMessage = 'Demo initialization failed.';
      });
    }
  }

  Future<void> _disposeResources(
    StreamSubscription<AuthState>? subscription,
    CommonAuth? auth,
    _ExampleNetworkClientSetup? clientSetup,
  ) async {
    await subscription?.cancel();
    await auth?.dispose();
    await clientSetup?.dispose();
  }

  CommonAuth _buildAuth(_ExampleAuthTokenRefresher tokenRefresher) {
    return CommonAuth.secureStorage(
      tokenRefresher: tokenRefresher,
      sessionKey: _sessionKey,
    );
  }

  Future<void> _replaceAuth(
    CommonAuth nextAuth, {
    required bool disposeCurrent,
  }) async {
    final currentSubscription = _stateSubscription;
    final currentAuth = _auth;

    _stateSubscription = null;
    await currentSubscription?.cancel();
    if (disposeCurrent) {
      await currentAuth?.dispose();
    }

    _auth = nextAuth;
    _stateSubscription = nextAuth.watchState().listen(_handleAuthStateChange);
    _handleAuthStateChange(nextAuth.currentState);
  }

  Future<void> _loginDemoAccount() async {
    final apiClient = _apiClient;
    final auth = _auth;
    if (_busy || apiClient == null || auth == null) {
      return;
    }

    setState(() {
      _logining = true;
      _lastError = '';
      _lastLoginTrace = null;
      _restoredFromStorage = false;
      _refreshClearedExpiry = false;
      _lastMessage =
          'Calling login endpoint and storing the resulting session...';
    });

    try {
      final loginResult = await apiClient.login(
        username: widget.config.username,
        password: widget.config.password,
      );
      await auth.setSession(
        AuthSession(
          tokens: AuthTokenPair(
            accessToken: loginResult.accessToken,
            refreshToken: loginResult.refreshToken,
          ),
          expiresAt: loginResult.expiresAtUtc,
          subjectId: widget.config.username,
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _expiresAtSource = loginResult.expiresAtSource;
        _lastMessage =
            'Login succeeded and session was written to secure storage.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastError = '$error';
        _lastMessage = 'Login failed.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _logining = false;
        });
      }
    }
  }

  Future<void> _expireAndRefreshSession() async {
    final auth = _auth;
    if (_busy || auth == null) {
      return;
    }

    final currentSession = auth.currentState.session;
    if (currentSession == null) {
      setState(() {
        _lastError = '';
        _lastMessage =
            'No session available. Login first or recreate from secure storage.';
      });
      return;
    }

    final currentRefreshToken = currentSession.tokens.refreshToken;
    final expiredSession = currentSession.copyWith(
      tokens: currentSession.tokens.copyWith(
        refreshToken:
            currentRefreshToken ??
            _buildDemoRefreshToken(currentSession.subjectId),
      ),
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );

    setState(() {
      _refreshing = true;
      _lastError = '';
      _lastRefreshTrace = null;
      _expiresAtSource = 'manually expired for demo';
      _lastMessage =
          'Marked the current session expired and triggered ensureValidSession().';
    });

    try {
      await auth.setSession(expiredSession);
      final refreshedSession = await auth.ensureValidSession();

      if (!mounted) {
        return;
      }

      setState(() {
        if (refreshedSession == null) {
          _lastMessage = 'Refresh failed and the session was cleared.';
          _expiresAtSource = '-';
          _refreshClearedExpiry = false;
          return;
        }

        _refreshClearedExpiry = refreshedSession.expiresAt == null;
        _expiresAtSource = refreshedSession.expiresAt == null
            ? 'current refresh contract resets expiresAt to null'
            : 'refreshed session';
        _lastMessage =
            'Refresh succeeded through the external refresher adapter.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastError = '$error';
        _lastMessage = 'Refresh failed.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _recreateAuth() async {
    final tokenRefresher = _tokenRefresher;
    if (_busy || tokenRefresher == null) {
      return;
    }

    setState(() {
      _recreating = true;
      _lastError = '';
      _lastMessage =
          'Rebuilding CommonAuth and bootstrapping again from secure storage...';
    });

    try {
      final nextAuth = _buildAuth(tokenRefresher);
      await _replaceAuth(nextAuth, disposeCurrent: true);
      await nextAuth.bootstrap();

      if (!mounted) {
        return;
      }

      final restored = nextAuth.currentState.session != null;
      setState(() {
        _restoredFromStorage = restored;
        _expiresAtSource = restored ? 'restored from secure storage' : '-';
        _lastMessage = restored
            ? 'Recreated CommonAuth and restored the stored session.'
            : 'Recreated CommonAuth. No persisted session was found.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastError = '$error';
        _lastMessage = 'Failed to recreate CommonAuth.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _recreating = false;
        });
      }
    }
  }

  Future<void> _clearSession() async {
    final auth = _auth;
    if (_busy || auth == null) {
      return;
    }

    setState(() {
      _clearing = true;
      _lastError = '';
      _restoredFromStorage = false;
      _refreshClearedExpiry = false;
      _expiresAtSource = '-';
      _lastMessage = 'Clearing the stored session...';
    });

    try {
      await auth.clearSession();
      if (!mounted) {
        return;
      }
      setState(() {
        _lastMessage = 'Session cleared from memory and secure storage.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastError = '$error';
        _lastMessage = 'Failed to clear the session.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _clearing = false;
        });
      }
    }
  }

  void _handleAuthStateChange(AuthState state) {
    if (!mounted) {
      return;
    }

    final session = state.session;
    final expiresAt = session?.expiresAt;
    setState(() {
      _statusText = state.status.name;
      _subjectIdText = session?.subjectId ?? '-';
      _accessTokenPreview = _previewToken(session?.tokens.accessToken);
      _refreshTokenPreview = _previewToken(session?.tokens.refreshToken);
      _expiresAtText = expiresAt == null
          ? '-'
          : expiresAt.toLocal().toIso8601String();
    });
  }

  void _handleLoginTrace(_ExampleRequestTrace trace) {
    if (!mounted) {
      return;
    }
    setState(() {
      _lastLoginTrace = trace;
    });
  }

  void _handleRefreshTrace(_ExampleRequestTrace trace) {
    if (!mounted) {
      return;
    }
    setState(() {
      _lastRefreshTrace = trace;
    });
  }

  String _previewToken(String? token) {
    if (token == null || token.isEmpty) {
      return '-';
    }
    if (token.length <= 28) {
      return token;
    }
    return '${token.substring(0, 28)}...';
  }

  String _traceSummary(_ExampleRequestTrace? trace) {
    if (trace == null) {
      return '-';
    }
    final fallbackText = trace.fromFallback ? ' (fallback)' : '';
    return '${trace.channel.name}$fallbackText, '
        'status=${trace.statusCode}, '
        'cost=${trace.costMs} ms, '
        'route=${trace.routeReason}, '
        'url=${trace.url}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final messageColor = _lastError.isNotEmpty ? colorScheme.error : null;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AuthDemoHeader(
              clientMode: _clientMode,
              clientNote: _clientNote,
              sessionKey: _sessionKey,
              loginUrl: widget.config.loginUrl,
              refreshUrl: widget.config.refreshUrl,
            ),
            const SizedBox(height: 12),
            _AuthDemoActionButtons(
              busy: _busy,
              logining: _logining,
              refreshing: _refreshing,
              recreating: _recreating,
              clearing: _clearing,
              onLogin: _loginDemoAccount,
              onRefresh: _expireAndRefreshSession,
              onRecreate: _recreateAuth,
              onClear: _clearSession,
            ),
            const SizedBox(height: 12),
            _AuthDemoStatusSection(
              statusText: _statusText,
              subjectIdText: _subjectIdText,
              accessTokenPreview: _accessTokenPreview,
              refreshTokenPreview: _refreshTokenPreview,
              expiresAtText: _expiresAtText,
              expiresAtSource: _expiresAtSource,
              restoredFromStorage: _restoredFromStorage,
              refreshClearedExpiry: _refreshClearedExpiry,
              lastMessage: _lastMessage,
              lastError: _lastError,
              messageColor: messageColor,
              errorColor: colorScheme.error,
              lastLoginTraceSummary: _traceSummary(_lastLoginTrace),
              lastRefreshTraceSummary: _traceSummary(_lastRefreshTrace),
            ),
          ],
        ),
      ),
    );
  }
}
