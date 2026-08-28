import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _UppercaseTextInputFormatter extends TextInputFormatter {
  const _UppercaseTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final uppercasedText = newValue.text.toUpperCase();

    int uppercasedOffset(int offset) {
      if (offset < 0) return offset;
      return newValue.text.substring(0, offset).toUpperCase().length;
    }

    return newValue.copyWith(
      text: uppercasedText,
      selection: TextSelection(
        baseOffset: uppercasedOffset(newValue.selection.baseOffset),
        extentOffset: uppercasedOffset(newValue.selection.extentOffset),
        affinity: newValue.selection.affinity,
        isDirectional: newValue.selection.isDirectional,
      ),
      composing: newValue.composing.isValid
          ? TextRange(
              start: uppercasedOffset(newValue.composing.start),
              end: uppercasedOffset(newValue.composing.end),
            )
          : TextRange.empty,
    );
  }
}

class CallsignOnboardingScreen extends StatefulWidget {
  const CallsignOnboardingScreen({
    super.key,
    required this.onSave,
    this.initialCallsign,
  });

  final String? initialCallsign;
  final Future<void> Function(String callsign) onSave;

  @override
  State<CallsignOnboardingScreen> createState() =>
      _CallsignOnboardingScreenState();
}

class _CallsignOnboardingScreenState extends State<CallsignOnboardingScreen> {
  late final TextEditingController _callsignController;
  late bool _canContinue;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCallsign ?? '';
    _callsignController = TextEditingController(text: initial);
    _canContinue = initial.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _callsignController.dispose();
    super.dispose();
  }

  void _callsignChanged(String value) {
    final canContinue = value.trim().isNotEmpty;
    if (canContinue != _canContinue) {
      setState(() => _canContinue = canContinue);
    }
  }

  Future<void> _continue() async {
    final normalizedCallsign = _callsignController.text.trim();
    if (normalizedCallsign.isEmpty) return;

    _callsignController.value = TextEditingValue(
      text: normalizedCallsign,
      selection: TextSelection.collapsed(offset: normalizedCallsign.length),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await widget.onSave(normalizedCallsign);
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
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
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
                        inputFormatters: const [_UppercaseTextInputFormatter()],
                        decoration: const InputDecoration(
                          labelText: 'Callsign',
                        ),
                        onChanged: _callsignChanged,
                        onSubmitted: _canContinue ? (_) => _continue() : null,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        key: const Key('continueButton'),
                        onPressed: _canContinue ? _continue : null,
                        child: const Text('Continue'),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
