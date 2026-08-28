import 'package:flutter/material.dart';

import '../features/onboarding/presentation/callsign_onboarding_screen.dart';
import 'theme/openqsp_theme.dart';

class OpenQspApp extends StatelessWidget {
  const OpenQspApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenQSP',
      debugShowCheckedModeBanner: false,
      theme: OpenQspTheme.light,
      home: const CallsignOnboardingScreen(),
    );
  }
}
