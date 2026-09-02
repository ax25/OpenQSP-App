import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/openqsp_theme.dart';
import '../../../core/network/server_status_client.dart';
import '../../aprs/application/aprs_session_controller.dart';
import '../../aprs/presentation/aprs_receive_indicator.dart';
import '../../auth/application/auth_session.dart';
import '../../auth/data/auth_client.dart';
import '../../messages/application/messages_controller.dart';
import '../../messages/data/aprs_messages_transport.dart';
import '../../messages/data/messages_transport.dart';
import '../../messages/presentation/messages_screen.dart';

enum ServerConnectionState {
  checking('Checking server...'),
  available('Server available'),
  connected('Connected to server'),
  unavailable('Server unavailable');

  const ServerConnectionState(this.label);
  final String label;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.callsign,
    required this.onEditCallsign,
    required this.serverStatusClient,
    required this.authSession,
    required this.messagesRepository,
    required this.messagesRealtimeFactory,
    this.aprsSession,
    this.onOpenSettings,
  });

  final String callsign;
  final VoidCallback onEditCallsign;
  final ServerStatusClient serverStatusClient;
  final AuthSession authSession;
  final MessagesRepository messagesRepository;
  final MessagesRealtimeClient Function() messagesRealtimeFactory;
  final AprsSessionController? aprsSession;
  final VoidCallback? onOpenSettings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  ServerConnectionState _serverState = ServerConnectionState.checking;

  bool get _aprsActive => widget.aprsSession?.active ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkServer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_aprsActive) _checkServer();
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.callsign != widget.callsign &&
        _serverState == ServerConnectionState.connected) {
      _serverState = ServerConnectionState.available;
    }
  }

  Future<void> _checkServer() async {
    if (_aprsActive) return;
    final wasConnected = _serverState == ServerConnectionState.connected;
    if (_serverState != ServerConnectionState.checking && mounted) {
      setState(() => _serverState = ServerConnectionState.checking);
    }
    final available = await widget.serverStatusClient.isAvailable();
    if (!mounted || _aprsActive) return;
    setState(() {
      if (!available) {
        _serverState = ServerConnectionState.unavailable;
      } else if (!wasConnected) {
        _serverState = ServerConnectionState.available;
      } else {
        _serverState = ServerConnectionState.connected;
      }
    });
  }

  Future<void> _onMessagesTap() async {
    if (_aprsActive) {
      final session = widget.aprsSession;
      if (session == null || !session.serverReachable) {
        _showMessage(session?.statusLabel ?? 'APRS Server Unavailable');
        return;
      }
      _openAprsMessages(session);
      return;
    }
    if (_serverState == ServerConnectionState.unavailable ||
        _serverState == ServerConnectionState.checking) {
      _showMessage('Server unavailable');
      return;
    }
    final gate = await widget.authSession.authenticateStoredToken(
      widget.callsign,
    );
    if (!mounted) return;
    switch (gate) {
      case AuthGateResult.connected:
        _openMessages();
        return;
      case AuthGateResult.serverUnavailable:
        setState(() => _serverState = ServerConnectionState.unavailable);
        _showMessage('Server unavailable');
        return;
      case AuthGateResult.needsPassword:
        await _promptUntilAuthenticated();
        return;
    }
  }

  Future<void> _promptUntilAuthenticated() async {
    String? error;
    while (mounted) {
      final password = await _showPasswordDialog(error: error);
      if (password == null || !mounted) return;
      final result = await widget.authSession.login(widget.callsign, password);
      if (!mounted) return;
      if (result is LoginSuccess) {
        setState(() => _serverState = ServerConnectionState.connected);
        _openMessages();
        return;
      }
      final failure = (result as LoginError).failure;
      if (failure == LoginFailure.incorrectPassword) {
        setState(() => _serverState = ServerConnectionState.available);
        error = 'Incorrect password';
        continue;
      }
      if (failure == LoginFailure.network) {
        setState(() => _serverState = ServerConnectionState.unavailable);
        _showMessage('Server unavailable');
      } else {
        _showMessage('Unable to connect to server');
      }
      return;
    }
  }

  Future<String?> _showPasswordDialog({String? error}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Connect to server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Password for ${widget.callsign}'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('serverPasswordField'),
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Password',
                errorText: error,
              ),
              onSubmitted: (value) {
                if (value.isNotEmpty) Navigator.pop(dialogContext, value);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('connectButton'),
            onPressed: () {
              if (controller.text.isNotEmpty) {
                Navigator.pop(dialogContext, controller.text);
              }
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openMessages() {
    setState(() => _serverState = ServerConnectionState.connected);
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MessagesScreen(
          controller: MessagesController(
            callsign: widget.callsign,
            token: widget.authSession.tokenFor(widget.callsign)!,
            repository: SessionAwareMessagesRepository(
              delegate: widget.messagesRepository,
              onAuthenticationRequired: () =>
                  widget.authSession.invalidate(widget.callsign),
            ),
            realtime: widget.messagesRealtimeFactory(),
            onAuthenticationRequired: () =>
                widget.authSession.invalidate(widget.callsign),
          ),
        ),
      ),
    );
  }

  void _openAprsMessages(AprsSessionController session) {
    final transport = AprsMessagesTransport(
      session: session,
      callsign: widget.callsign,
    );
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MessagesScreen(
          aprsSession: session,
          controller: MessagesController(
            callsign: widget.callsign,
            token: '',
            repository: transport,
            realtime: transport,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aprsSession = widget.aprsSession;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  key: const Key('homeScrollView'),
                  padding: const EdgeInsets.only(top: 32, bottom: 16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _HomeHeader(
                            callsign: widget.callsign,
                            onEditCallsign: widget.onEditCallsign,
                            onOpenSettings: widget.onOpenSettings,
                            aprsSession: aprsSession,
                          ),
                          const SizedBox(height: 30),
                          Text(
                            'Services',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          _CapabilityTile(
                            key: const Key('messagesTile'),
                            icon: Icons.mail_outline,
                            status: aprsSession == null
                                ? null
                                : AprsReceiveIndicator(
                                    session: aprsSession,
                                    size: 18,
                                  ),
                            title: 'Messages',
                            subtitle: 'Private messages',
                            onTap: _onMessagesTap,
                          ),
                          const SizedBox(height: 12),
                          const _CapabilityTile(
                            icon: Icons.campaign_outlined,
                            title: 'Bulletins',
                            subtitle: 'Community bulletins',
                            onTap: null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                child: _TransportStatus(
                  aprsSession: aprsSession,
                  internetState: _serverState,
                  onInternetRetry: _checkServer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.callsign,
    required this.onEditCallsign,
    required this.onOpenSettings,
    required this.aprsSession,
  });

  final String callsign;
  final VoidCallback onEditCallsign;
  final VoidCallback? onOpenSettings;
  final AprsSessionController? aprsSession;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final title = Text(
          'OpenQSP',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        );
        final headerActions = _HeaderActions(
          callsign: callsign,
          onEdit: onEditCallsign,
          onOpenSettings: onOpenSettings,
          aprsSession: aprsSession,
          alignment: constraints.maxWidth < 600
              ? WrapAlignment.start
              : WrapAlignment.end,
        );

        if (constraints.maxWidth < 600) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [title, const SizedBox(height: 8), headerActions],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            const SizedBox(width: 24),
            Expanded(child: headerActions),
          ],
        );
      },
    );
  }
}

class _HeaderActions extends StatelessWidget {
  const _HeaderActions({
    required this.callsign,
    required this.onEdit,
    required this.onOpenSettings,
    required this.aprsSession,
    required this.alignment,
  });

  final String callsign;
  final VoidCallback onEdit;
  final VoidCallback? onOpenSettings;
  final AprsSessionController? aprsSession;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: alignment,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 6,
      children: [
        _CallsignAction(callsign: callsign, onEdit: onEdit),
        _TransportSelector(aprsSession: aprsSession),
        if (onOpenSettings != null)
          IconButton(
            key: const Key('settingsButton'),
            tooltip: 'Configuración',
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
      ],
    );
  }
}

class _CallsignAction extends StatelessWidget {
  const _CallsignAction({
    required this.callsign,
    required this.onEdit,
  });

  final String callsign;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CallsignText(callsign),
        IconButton(
          key: const Key('editCallsignButton'),
          tooltip: 'Change callsign',
          onPressed: onEdit,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.edit_outlined, size: 19),
        ),
      ],
    );
  }
}

class _CallsignText extends StatelessWidget {
  const _CallsignText(this.callsign);

  final String callsign;

  @override
  Widget build(BuildContext context) => Text(
    callsign,
    key: const Key('homeCallsign'),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.titleMedium,
  );
}

class _TransportSelector extends StatelessWidget {
  const _TransportSelector({required this.aprsSession});

  final AprsSessionController? aprsSession;

  @override
  Widget build(BuildContext context) {
    final session = aprsSession;
    if (session == null) return const _TransportSelectorBody();
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) => _TransportSelectorBody(
        aprsSelected: session.active,
        aprsEnabled: true,
        onSelected: (value) {
          if (value == 'APRS') {
            unawaited(session.activate());
          } else if (value == 'Internet') {
            unawaited(session.deactivate());
          }
        },
      ),
    );
  }
}

class _TransportSelectorBody extends StatelessWidget {
  const _TransportSelectorBody({
    this.aprsSelected = false,
    this.aprsEnabled = false,
    this.onSelected,
  });

  final bool aprsSelected;
  final bool aprsEnabled;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = aprsSelected ? 'APRS' : 'Internet';
    return PopupMenuButton<String>(
      key: const Key('transportSelector'),
      initialValue: selected,
      padding: EdgeInsets.zero,
      tooltip: 'Select transport',
      onSelected: onSelected,
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'Internet', child: Text('Internet')),
        PopupMenuItem(
          value: 'APRS',
          enabled: aprsEnabled,
          child: const Text('APRS'),
        ),
        const PopupMenuItem(enabled: false, child: Text('Winlink')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: OpenQspColors.secondaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: OpenQspColors.secondaryText,
            ),
          ],
        ),
      ),
    );
  }
}

class _TransportStatus extends StatelessWidget {
  const _TransportStatus({
    required this.aprsSession,
    required this.internetState,
    required this.onInternetRetry,
  });

  final AprsSessionController? aprsSession;
  final ServerConnectionState internetState;
  final VoidCallback onInternetRetry;

  @override
  Widget build(BuildContext context) {
    final session = aprsSession;
    if (session == null) {
      return _Status(state: internetState, onRetry: onInternetRetry);
    }
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        if (!session.active) {
          return _Status(state: internetState, onRetry: onInternetRetry);
        }
        final reachable = session.serverReachable;
        final slow = session.state == AprsSessionState.slow;
        final statusColor = slow
            ? OpenQspColors.warning
            : reachable
            ? OpenQspColors.positive
            : OpenQspColors.secondaryText;
        return InkWell(
          key: const Key('aprsStatusRetry'),
          borderRadius: BorderRadius.circular(16),
          onTap: session.state == AprsSessionState.connecting
              ? null
              : () => unawaited(session.retry()),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      reachable ? Icons.circle : Icons.circle_outlined,
                      size: 11,
                      color: statusColor,
                    ),
                    const SizedBox(width: 9),
                    Text(
                      session.statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (reachable) ...[
                  const SizedBox(height: 2),
                  Text(
                    session.detailLabel,
                    key: const Key('aprsStatusDetail'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: OpenQspColors.secondaryText,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.state, required this.onRetry});
  final ServerConnectionState state;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final positive = state == ServerConnectionState.available ||
        state == ServerConnectionState.connected;
    return InkWell(
      key: const Key('serverStatusRetry'),
      borderRadius: BorderRadius.circular(16),
      onTap: state == ServerConnectionState.checking ? null : onRetry,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              positive ? Icons.circle : Icons.circle_outlined,
              size: 11,
              color: positive
                  ? OpenQspColors.positive
                  : OpenQspColors.secondaryText,
            ),
            const SizedBox(width: 9),
            Text(
              state.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: positive
                    ? OpenQspColors.positive
                    : OpenQspColors.secondaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CapabilityTile extends StatelessWidget {
  const _CapabilityTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.status,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? status;
  @override
  Widget build(BuildContext context) => Material(
    color: OpenQspColors.surface,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: OpenQspColors.border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(icon, color: OpenQspColors.brand),
                  ),
                  if (status != null)
                    Positioned(right: -4, top: -6, child: status!),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: OpenQspColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    ),
  );
}
