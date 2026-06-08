part of 'auth_app_integration_demo_card.dart';

class _AuthDemoHeader extends StatelessWidget {
  const _AuthDemoHeader({
    required this.clientMode,
    required this.clientNote,
    required this.sessionKey,
    required this.loginUrl,
    required this.refreshUrl,
  });

  final String clientMode;
  final String clientNote;
  final String sessionKey;
  final String loginUrl;
  final String refreshUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Auth app integration demo',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'This page shows one app-side composition root: '
          'an external client handles login + refresh, while '
          'CommonAuth.secureStorage(...) persists the session.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Text('Client mode: $clientMode'),
        Text('Client note: $clientNote'),
        Text('Session key: $sessionKey'),
        Text('Login endpoint: $loginUrl'),
        Text('Refresh endpoint: $refreshUrl'),
      ],
    );
  }
}

class _AuthDemoActionButtons extends StatelessWidget {
  const _AuthDemoActionButtons({
    required this.busy,
    required this.logining,
    required this.refreshing,
    required this.recreating,
    required this.clearing,
    required this.onLogin,
    required this.onRefresh,
    required this.onRecreate,
    required this.onClear,
  });

  final bool busy;
  final bool logining;
  final bool refreshing;
  final bool recreating;
  final bool clearing;
  final Future<void> Function() onLogin;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onRecreate;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed: busy ? null : onLogin,
          icon: logining
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.login),
          label: Text(logining ? 'Logging in...' : 'Login demo account'),
        ),
        FilledButton.tonalIcon(
          onPressed: busy ? null : onRefresh,
          icon: refreshing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          label: Text(refreshing ? 'Refreshing...' : 'Expire + refresh'),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : onRecreate,
          icon: recreating
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.restart_alt),
          label: Text(recreating ? 'Recreating...' : 'Recreate auth'),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : onClear,
          icon: clearing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_outline),
          label: Text(clearing ? 'Clearing...' : 'Clear session'),
        ),
      ],
    );
  }
}

class _AuthDemoStatusSection extends StatelessWidget {
  const _AuthDemoStatusSection({
    required this.statusText,
    required this.subjectIdText,
    required this.accessTokenPreview,
    required this.refreshTokenPreview,
    required this.expiresAtText,
    required this.expiresAtSource,
    required this.restoredFromStorage,
    required this.refreshClearedExpiry,
    required this.lastMessage,
    required this.lastError,
    required this.messageColor,
    required this.errorColor,
    required this.lastLoginTraceSummary,
    required this.lastRefreshTraceSummary,
  });

  final String statusText;
  final String subjectIdText;
  final String accessTokenPreview;
  final String refreshTokenPreview;
  final String expiresAtText;
  final String expiresAtSource;
  final bool restoredFromStorage;
  final bool refreshClearedExpiry;
  final String lastMessage;
  final String lastError;
  final Color? messageColor;
  final Color errorColor;
  final String lastLoginTraceSummary;
  final String lastRefreshTraceSummary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Auth status: $statusText'),
        Text('Subject: $subjectIdText'),
        Text('Access token: $accessTokenPreview'),
        Text('Refresh token: $refreshTokenPreview'),
        Text('ExpiresAt: $expiresAtText'),
        Text('ExpiresAt source: $expiresAtSource'),
        Text('Restored from storage: ${restoredFromStorage ? 'yes' : 'no'}'),
        Text(
          'Last result: $lastMessage',
          style: TextStyle(color: messageColor),
        ),
        if (refreshClearedExpiry)
          Text(
            'Note: DefaultAuthRepository currently writes refreshed sessions '
            'with expiresAt = null. This demo surfaces that contract explicitly.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (lastError.isNotEmpty)
          Text('Last error: $lastError', style: TextStyle(color: errorColor)),
        const SizedBox(height: 12),
        Text(
          'Last login trace: $lastLoginTraceSummary',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          'Last refresh trace: $lastRefreshTraceSummary',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
