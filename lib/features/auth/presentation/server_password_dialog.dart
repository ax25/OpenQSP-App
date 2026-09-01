import 'package:flutter/material.dart';

Future<String?> showServerPasswordDialog(
  BuildContext context, {
  required String callsign,
  String? error,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ServerPasswordDialog(callsign: callsign, error: error),
);

class _ServerPasswordDialog extends StatefulWidget {
  const _ServerPasswordDialog({required this.callsign, this.error});

  final String callsign;
  final String? error;

  @override
  State<_ServerPasswordDialog> createState() => _ServerPasswordDialogState();
}

class _ServerPasswordDialogState extends State<_ServerPasswordDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _controller.text;
    if (password.isNotEmpty) {
      Navigator.of(context).pop(password);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect to server'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Password for ${widget.callsign}'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('serverPasswordField'),
            controller: _controller,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Password',
              errorText: widget.error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('connectButton'),
          onPressed: _submit,
          child: const Text('Connect'),
        ),
      ],
    );
  }
}
