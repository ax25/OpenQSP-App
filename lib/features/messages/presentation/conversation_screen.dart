import 'package:flutter/material.dart';

import '../application/messages_controller.dart';
import '../domain/message_models.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.controller, required this.remoteCallsign});
  final MessagesController controller;
  final String remoteCallsign;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _composer = TextEditingController();
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _load();
  }

  Future<void> _load() async {
    try {
      await widget.controller.openConversation(widget.remoteCallsign);
    } on Object catch (error) {
      _error = error.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _send() async {
    if (_sending || _composer.text.trim().isEmpty) return;
    setState(() { _sending = true; _error = null; });
    try {
      await widget.controller.send(widget.remoteCallsign, _composer.text);
      _composer.clear();
    } on Object catch (error) {
      _error = 'Message could not be sent: $error';
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<bool> _confirm(String title, String body) async => await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(title: Text(title), content: Text(body), actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
    ]),
  ) ?? false;

  Future<void> _deleteConversation() async {
    if (!await _confirm('Delete conversation?', 'This removes the complete conversation with ${widget.remoteCallsign}.')) return;
    try {
      await widget.controller.deleteConversation(widget.remoteCallsign);
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Conversation could not be deleted: $error')));
    }
  }

  Future<void> _deleteMessage(InternetMessage message) async {
    if (!await _confirm('Delete message?', 'This action cannot be undone.')) return;
    try {
      await widget.controller.deleteMessage(widget.remoteCallsign, message.id);
    } on Object catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Message could not be deleted: $error')));
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.controller.historyFor(widget.remoteCallsign);
    return Scaffold(
      appBar: AppBar(title: Text(widget.remoteCallsign), actions: [IconButton(key: const Key('deleteConversation'), onPressed: _deleteConversation, tooltip: 'Delete conversation', icon: const Icon(Icons.delete_outline))]),
      body: Column(children: [
        if (_error != null) MaterialBanner(content: Text(_error!), actions: [TextButton(onPressed: _load, child: const Text('Retry'))]),
        Expanded(
          child: _loading ? const Center(child: CircularProgressIndicator()) : messages.isEmpty ? const Center(child: Text('No messages yet')) : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: messages.length,
            itemBuilder: (_, index) {
              final message = messages[index];
              final sent = message.direction == MessageDirection.sent;
              return Align(
                alignment: sent ? Alignment.centerRight : Alignment.centerLeft,
                child: GestureDetector(
                  onLongPress: message.canDelete ? () => _deleteMessage(message) : null,
                  child: Card(
                    color: sent ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Text(message.text)),
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          Expanded(child: TextField(key: const Key('messageComposer'), controller: _composer, decoration: const InputDecoration(labelText: 'Message'), onSubmitted: (_) => _send())),
          const SizedBox(width: 8),
          IconButton(key: const Key('sendMessage'), onPressed: _sending ? null : _send, icon: _sending ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send)),
        ]))),
      ]),
    );
  }
}
