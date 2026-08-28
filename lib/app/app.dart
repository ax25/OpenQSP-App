import 'package:flutter/material.dart';

import '../core/network/server_status_client.dart';
import '../features/callsign/data/callsign_store.dart';
import '../features/auth/data/auth.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/messages/application/messages_controller.dart';
import '../features/messages/presentation/conversations_screen.dart';
import '../features/onboarding/presentation/callsign_onboarding_screen.dart';
import 'theme/openqsp_theme.dart';

class OpenQspApp extends StatefulWidget {
  const OpenQspApp({
    super.key,
    this.callsignStore,
    required this.serverStatusClient,
    this.authSession,
    this.messagesControllerFactory,
  });

  final CallsignStore? callsignStore;
  final ServerStatusClient serverStatusClient;
  final AuthSession? authSession;
  final MessagesController Function(String callsign)? messagesControllerFactory;

  @override
  State<OpenQspApp> createState() => _OpenQspAppState();
}

class _OpenQspAppState extends State<OpenQspApp> {
  late final CallsignStore _store;
  String? _callsign;
  bool _loading = true;
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _store = widget.callsignStore ?? PreferencesCallsignStore();
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

  Future<void> _openMessages() async {
    final auth = widget.authSession;
    final factory = widget.messagesControllerFactory;
    if (auth == null || factory == null) {
      await showDialog<void>(
        context: _navigatorKey.currentContext!,
        builder: (context) => const AlertDialog(
          title: Text('Messaging unavailable'),
          content: Text(
            'The server messaging and authentication contract is not documented. '
            'No network protocol has been guessed.',
          ),
        ),
      );
      return;
    }
    var authenticated = false;
    try {
      authenticated = await auth.restore(_callsign!);
    } catch (_) {
      authenticated = false;
    }
    if (!authenticated) {
      final password = await _askPassword();
      if (password == null) return;
      try {
        await auth.login(_callsign!, password);
      } catch (error) {
        if (_navigatorKey.currentContext!.mounted) {
          ScaffoldMessenger.of(_navigatorKey.currentContext!).showSnackBar(
            SnackBar(content: Text('Authentication failed: $error')),
          );
        }
        return;
      }
    }
    final controller = factory(_callsign!);
    try {
      await controller.start(auth.token!);
    } catch (_) {
      // The screen exposes retry and connection state without claiming success.
    }
    if (!_navigatorKey.currentContext!.mounted) return;
    await _navigatorKey.currentState!.push<void>(
      MaterialPageRoute(builder: (_) => ConversationsScreen(controller: controller)),
    );
    controller.dispose();
  }

  Future<String?> _askPassword() async {
    final password = TextEditingController();
    final result = await showDialog<String>(
      context: _navigatorKey.currentContext!,
      builder: (context) => AlertDialog(
        title: Text('Sign in as $_callsign'),
        content: TextField(
          key: const Key('passwordField'),
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, password.text), child: const Text('Sign in')),
        ],
      ),
    );
    password.dispose();
    return result;
  }

  @override
  void dispose() {
    widget.serverStatusClient.close();
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
              onMessages: _openMessages,
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
