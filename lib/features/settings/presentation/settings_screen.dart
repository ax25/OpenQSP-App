import 'package:flutter/material.dart';

import '../../aprs/application/tnc_settings_controller.dart';
import '../../aprs/presentation/tnc_settings_section.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.tncController});
  final TncSettingsController tncController;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Configuración')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('APRS', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                TncSettingsSection(controller: tncController),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
