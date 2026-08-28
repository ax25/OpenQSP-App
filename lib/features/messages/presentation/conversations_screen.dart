import 'package:flutter/material.dart';

import '../application/messages_controller.dart';
import '../domain/models.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key, required this.controller});
  final MessagesController controller;

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      floatingActionButton: FloatingActionButton(
        key: const Key('newConversation'),
        onPressed: _newConversation,
        tooltip: 'New conversation',
        child: const Icon(Icons.add_comment_outlined),
      ),
      body: Column(
        children: [
          if (controller.connection == MessagingConnectionState.reconnecting ||
              controller.connection == MessagingConnectionState.disconnected)
            MaterialBanner(
              content: Text(
                controller.connection == MessagingConnectionState.reconnecting
                    ? 'Real-time connection lost. Reconnecting…'
                    : 'Real-time updates are disconnected.',
              ),
              actions: const [SizedBox.shrink()],
            ),
          Expanded(child: _body(controller)),
        ],
      ),
    );
  }

  Widget _body(MessagesController controller) {
    if (controller.loading && controller.conversations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.error != null && controller.conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Unable to load conversations.'),
            const SizedBox(height: 8),
            FilledButton(onPressed: controller.reload, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (controller.conversations.isEmpty) {
      return const Center(child: Text('No conversations yet'));
    }
    return ListView.builder(
      itemCount: controller.conversations.length,
      itemBuilder: (context, index) {
        final conversation = controller.conversations[index];
        return ListTile(
          key: Key('conversation-${conversation.remoteCallsign}'),
          leading: CircleAvatar(child: Text(conversation.remoteCallsign.characters.first)),
          title: Text(conversation.remoteCallsign),
          subtitle: Text(conversation.latestMessage?.text ?? 'No messages yet', maxLines: 1),
          trailing: conversation.unread > 0
              ? Badge(label: Text('${conversation.unread}'))
              : conversation.latestMessage == null
                  ? null
                  : Text(_time(conversation.latestMessage!.sentAt)),
          onTap: () => _open(conversation.remoteCallsign),
          onLongPress: () => _deleteConversation(conversation.remoteCallsign),
        );
      },
    );
  }

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  Future<void> _newConversation() async {
    final text = TextEditingController();
    final remote = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New conversation'),
        content: TextField(
          key: const Key('destinationCallsign'),
          controller: text,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Destination callsign'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final value = text.text.trim().toUpperCase();
              final valid = RegExp(r'^[A-Z0-9]{1,6}(-[0-9]{1,2})?$').hasMatch(value);
              if (valid && value != widget.controller.localCallsign.toUpperCase()) {
                Navigator.pop(context, value);
              }
            },
            child: const Text('Open'),
          ),
        ],
      ),
    );
    text.dispose();
    if (remote != null && mounted) await _open(remote);
  }

  Future<void> _open(String remote) async {
    widget.controller.markRead(remote);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationScreen(controller: widget.controller, remote: remote),
      ),
    );
  }

  Future<void> _deleteConversation(String remote) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: Text('Delete the complete conversation with $remote?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.deleteConversation(remote);
  }
}

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.controller,
    required this.remote,
  });
  final MessagesController controller;
  final String remote;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _composer = TextEditingController();
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.controller.loadHistory(widget.remote);
  }

  void _changed() => setState(() {});
  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.controller.messagesFor(widget.remote);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.remote),
        actions: [
          IconButton(
            tooltip: 'Delete conversation',
            onPressed: _deleteConversation,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.controller.error != null)
            MaterialBanner(
              content: const Text('The last messaging operation failed.'),
              actions: [TextButton(onPressed: () => widget.controller.loadHistory(widget.remote), child: const Text('Retry'))],
            ),
          Expanded(
            child: messages.isEmpty
                ? const Center(child: Text('No messages yet'))
                : ListView.builder(
                    itemCount: messages.length,
                    itemBuilder: (_, index) => _bubble(messages[index]),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(child: TextField(key: const Key('messageComposer'), controller: _composer, decoration: const InputDecoration(hintText: 'Message'))),
                  IconButton(
                    key: const Key('sendMessage'),
                    onPressed: widget.controller.sending ? null : _send,
                    icon: widget.controller.sending
                        ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(InternetMessage message) {
    final sent = message.sender.toUpperCase() == widget.controller.localCallsign.toUpperCase();
    return Align(
      alignment: sent ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: message.canDelete ? () => _deleteMessage(message) : null,
        child: Card(
          color: sent ? Theme.of(context).colorScheme.primaryContainer : null,
          child: Padding(padding: const EdgeInsets.all(12), child: Text(message.text)),
        ),
      ),
    );
  }

  Future<void> _send() async {
    if (await widget.controller.send(widget.remote, _composer.text)) _composer.clear();
  }

  Future<void> _deleteMessage(InternetMessage message) async {
    final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Delete message?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
      ],
    ));
    if (yes == true) await widget.controller.deleteMessage(message.id);
  }

  Future<void> _deleteConversation() async {
    final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Delete conversation?'),
      content: Text('Delete the complete conversation with ${widget.remote}?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
      ],
    ));
    if (yes == true && await widget.controller.deleteConversation(widget.remote) && mounted) {
      Navigator.pop(context);
    }
  }
}
