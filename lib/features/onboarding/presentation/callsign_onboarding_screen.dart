import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CallsignOnboardingScreen extends StatefulWidget {
  const CallsignOnboardingScreen({super.key});

  @override
  State<CallsignOnboardingScreen> createState() =>
      _CallsignOnboardingScreenState();
}

class _CallsignOnboardingScreenState extends State<CallsignOnboardingScreen> {
  final _callsignController = TextEditingController();
  bool _canContinue = false;

  @override
  void dispose() {
    _callsignController.dispose();
    super.dispose();
  }

  void _callsignChanged(String value) {
    final canContinue = value.isNotEmpty;
    if (canContinue != _canContinue) {
      setState(() => _canContinue = canContinue);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final topSpace = (constraints.maxHeight * 0.27)
                .clamp(112.0, 208.0)
                .toDouble();

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: topSpace),
                  Text(
                    'OpenQSP',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 36),
                  Text(
                    'Insert your callsign',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    key: const Key('callsignField'),
                    controller: _callsignController,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    enableSuggestions: false,
                    inputFormatters: [
                      TextInputFormatter.withFunction((oldValue, newValue) {
                        final normalized = newValue.text.trim().toUpperCase();
                        return TextEditingValue(
                          text: normalized,
                          selection: TextSelection.collapsed(
                            offset: normalized.length,
                          ),
                        );
                      }),
                    ],
                    decoration: const InputDecoration(labelText: 'Callsign'),
                    onChanged: _callsignChanged,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    key: const Key('continueButton'),
                    onPressed: _canContinue ? () {} : null,
                    child: const Text('Continue'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
