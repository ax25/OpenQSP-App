import 'dart:async';

import 'package:flutter/material.dart';

import '../core/network/server_status_client.dart';
import '../features/auth/application/auth_session.dart';
import '../features/auth/data/auth_client.dart';
import '../features/auth/data/auth_token_store.dart';
import '../features/auth/presentation/server_password_dialog.dart';
import '../features/aprs/application/aprs_session_controller.dart';
import '../features/aprs/application/tnc_settings_controller.dart';
import '../features/aprs/data/bluetooth_tnc_service.dart';
import '../features/aprs/data/bluetooth_tnc_storage.dart';
import '../features/aprs/data/burst_repair_bluetooth_tnc_service.dart';
import '../features/callsign/data/callsign_store.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/messages/data/messages_transport.dart';
import '../features/onboarding/presentation/callsign_onboarding_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import 'theme/openqsp_theme.dart';

class OpenQspApp extends StatefulWidget {
  const OpenQspApp({
    super.key,
    this.callsignStore,
    required this.serverStatusClient,
    required this.authClient,
    this.authTokenStore,
    required this.messagesRepository,
    required this.messagesRealtimeFactory,
    this.tncControllerFactory,
  });

  final CallsignStore? callsignStore;
  final ServerStatusClient serverStatusClient;
  final AuthClient authClient;
  final AuthTokenStore? authTokenStore;
  final MessagesRepository messagesRepository;
  final MessagesRealtimeClient Function() messagesRealtimeFactory;
  final TncSettingsController Function()? tncControllerFactory;

  @override
  State<OpenQspApp> createState() => _OpenQspAppState();
}

class _OpenQspAppState extends State<OpenQspApp> {
  late final CallsignStore _store;
  late final AuthSession _authSession;
  StreamSubscription<String>? _authenticationRequiredSubscription;
  String? _callsign;
  bool _loading = true;
  bool _reauthenticating = false;
  TncSettingsController? _tncController;
  AprsSessionController? _aprsSession;
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _store = widget.callsignStore ?? PreferencesCallsignStore();
    _authSession = AuthSession(
      client: widget.authClient,
      tokenStore: widget.authTokenStore ?? SecureAuthTokenStore(),
    );
    _authenticationRequiredSubscription = _authSession.authenticationRequired.listen(
      (callsign) => unawaited(_reauthenticate(callsign)),
    );
    _loadCallsign();
  }

  TncSettingsController _buildTncController(String callsign) =>
      widget.tncControllerFactory?.call() ??
      TncSettingsController(
        storage: PreferencesBluetoothTncStorage(),
        service: BurstRepairBluetoothTncService(AndroidBluetoothTncService()),
        sourceCallsign: callsign,
      );

  void _replaceAprsSession(String callsign) {
    final oldSession = _aprsSession;
    final oldTnc = _tncController;
    if (oldSession != null && oldSession.active) {
      unawaited(oldSession.deactivate());
    }
    oldSession?.dispose();
    oldTnc?.dispose();

    final tnc = _buildTncController(callsign);
    _tncController = tnc;
    _aprsSession = AprsSessionController(tncController: tnc);
  }

  Future<void> _loadCallsign() async {
    final callsign = await _store.read();
    if (!mounted) return;
    if (callsign != null) _replaceAprsSession(callsign);
    setState(() {
      _callsign = callsign;
      _loading = false;
    });
  }

  Future<void> _saveCallsign(String callsign) async {
    await _store.write(callsign);
    if (!mounted) return;
    if (_callsign != callsign) _replaceAprsSession(callsign);
    setState(() => _callsign = callsign);
  }

  Future<void> _reauthenticate(String callsign) async {
    if (_reauthenticating || !mounted || _callsign?.toUpperCase() != callsign) {
      return;
    }
    _reauthenticating = true;
    try {
      // Authentication loss can be reported while a Messages widget is in the
      // middle of a build/notification cycle. Do not mutate the Navigator until
      // that frame has completed.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      final navigator = _navigatorKey.currentState;
      navigator?.popUntil((route) => route.isFirst);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      String? error;
      while (mounted) {
        final context = _navigatorKey.currentContext;
        if (context == null) return;
        final password = await showServerPasswordDialog(
          context,
          callsign: callsign,
          error: error,
        );
        if (password == null || !mounted) return;
        final result = await _authSession.login(callsign, password);
        if (!mounted) return;
        if (result is LoginSuccess) return;

        final failure = (result as LoginError).failure;
        if (failure == LoginFailure.incorrectPassword) {
          error = 'Incorrect password';
          continue;
        }
        final context = _navigatorKey.currentContext;
        if (context != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  failure == LoginFailure.network
                      ? 'Server unavailable'
                      : 'Unable to connect to server',
                ),
              ),
            );
        }
        return;
      }
    } finally {
      _reauthenticating = false;
    }
  }

  @override
  void dispose() {
    unawaited(_authenticationRequiredSubscription?.cancel());
    unawaited(_authSession.close());
    _aprsSession?.dispose();
    _tncController?.dispose();
    widget.serverStatusClient.close();
    widget.authClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aprsSession = _aprsSession;
    return MaterialApp(
      title: 'OpenQSP',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: OpenQspTheme.light,
      home: _loading
          ? const Scaffold(body: SizedBox.shrink())
          : _callsign == null
          ? CallsignOnboardingScreen(onSave: _saveCallsign)
          : HomeScreen(
              callsign: _callsign!,
              serverStatusClient: widget.serverStatusClient,
              authSession: _authSession,
              messagesRepository: widget.messagesRepository,
              messagesRealtimeFactory: widget.messagesRealtimeFactory,
              aprsSession: aprsSession,
              onOpenSettings: aprsSession == null
                  ? null
                  : () => _navigatorKey.currentState!.push<void>(
                      MaterialPageRoute(
                        builder: (_) => SettingsScreen(
                          tncController: aprsSession.tncController,
                        ),
                      ),
                    ),
              onEditCallsign: () async {
                await _navigatorKey.currentState!.push<void>(
                  MaterialPageRoute(
                    builder: (routeContext) => CallsignOnboardingScreen(
                      initialCallsign: _callsign,
                      onSave: (value) async {
                        await _saveCallsign(value);
                        if (routeContext.mounted) {
                          Navigator.of(routeContext).pop();
                        }
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
