import 'package:flutter/material.dart';

import '../application/messages_controller.dart';
import '../domain/message_models.dart';
import 'conversation_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key, required this.controller});
  final MessagesController controller;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.controller.start();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  Future<void> _newConversation() async {
    final input = TextEditingController();
    final remote = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New conversation'),
        content: TextField(
          key: const Key('destinationCallsign'),
          controller: input,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Destination callsign'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, input.text), child: const Text('Open')),
        ],
      ),
    );
    final normalized = remote?.trim().toUpperCase() ?? '';
    if (!mounted || normalized.isEmpty) return;
    if (!RegExp(r'^[A-Z0-9]{1,6}(?:-[0-9]{1,2})?$').hasMatch(normalized) || normalized == widget.controller.callsign.toUpperCase()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid callsign different from your own')));
      return;
    }
    await _open(normalized);
  }

  Future<void> _open(String remote) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => ConversationScreen(controller: widget.controller, remoteCallsign: remote)),
    );
    widget.controller.closeConversation();
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
        child: const Icon(Icons.edit_outlined),
      ),
      body: Column(
        children: [
          if (controller.connectionState == RealtimeConnectionState.reconnecting || controller.connectionState == RealtimeConnectionState.disconnected)
            MaterialBanner(
              content: Text(controller.connectionState == RealtimeConnectionState.reconnecting ? 'Real-time connection reconnecting…' : 'Real-time connection unavailable'),
              actions: const [SizedBox.shrink()],
            ),
          Expanded(child: _body(controller)),
        ],
      ),
    );
  }

  Widget _body(MessagesController controller) {
    if (controller.loading && controller.conversations.isEmpty) return const Center(child: CircularProgressIndicator());
    if (controller.error != null && controller.conversations.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Unable to load conversations'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: controller.loadConversations, child: const Text('Retry')),
        ]),
      );
    }
    if (controller.conversations.isEmpty) return const Center(child: Text('No conversations yet'));
    return ListView.separated(
      itemCount: controller.conversations.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final item = controller.conversations[index];
        return ListTile(
          key: Key('conversation-${item.remoteCallsign}'),
          title: Text(item.remoteCallsign),
          subtitle: item.latestMessage == null ? null : Text(item.latestMessage!, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: item.unreadCount > 0 ? Badge(label: Text('${item.unreadCount}')) : item.latestActivity == null ? null : Text(_time(item.latestActivity!)),
          onTap: () => _open(item.remoteCallsign),
        );
      },
    );
  }

  String _time(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
