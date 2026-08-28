import 'package:flutter/material.dart';

import '../core/network/server_status_client.dart';
import '../features/auth/application/auth_session.dart';
import '../features/auth/data/auth_client.dart';
import '../features/auth/data/auth_token_store.dart';
import '../features/callsign/data/callsign_store.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/onboarding/presentation/callsign_onboarding_screen.dart';
import 'theme/openqsp_theme.dart';

class OpenQspApp extends StatefulWidget {
  const OpenQspApp({
    super.key,
    this.callsignStore,
    required this.serverStatusClient,
    required this.authClient,
    this.authTokenStore,
  });

  final CallsignStore? callsignStore;
  final ServerStatusClient serverStatusClient;
  final AuthClient authClient;
  final AuthTokenStore? authTokenStore;

  @override
  State<OpenQspApp> createState() => _OpenQspAppState();
}

class _OpenQspAppState extends State<OpenQspApp> {
  late final CallsignStore _store;
  late final AuthSession _authSession;
  String? _callsign;
  bool _loading = true;
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _store = widget.callsignStore ?? PreferencesCallsignStore();
    _authSession = AuthSession(
      widget.authClient,
      widget.authTokenStore ?? SecureAuthTokenStore(),
    );
    _loadCallsign();
  }

  Future<void> _loadCallsign() async {
    final callsign = await _store.read();
    if (mounted) {
      setState(() {
        _callsign = callsign;
        _loading = false;
      });
    }
  }

  Future<void> _saveCallsign(String callsign) async {
    await _store.write(callsign);
    if (mounted) setState(() => _callsign = callsign);
  }

  @override
  void dispose() {
    widget.serverStatusClient.close();
    widget.authClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
