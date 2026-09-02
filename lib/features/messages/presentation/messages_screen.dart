import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../aprs/application/aprs_session_controller.dart';
import '../../aprs/presentation/aprs_receive_indicator.dart';
import '../application/messages_controller.dart';
import '../domain/message_models.dart';
import 'conversation_screen.dart';
import 'message_date_format.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({
    super.key,
    required this.controller,
    this.aprsSession,
  });
  final MessagesController controller;
  final AprsSessionController? aprsSession;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  bool _rebuildScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.controller.start();
  }

  void _changed() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      setState(() {});
      return;
    }
    if (_rebuildScheduled) return;
    _rebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildScheduled = false;
      if (mounted) setState(() {});
    });
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    final normalized = remote?.trim().toUpperCase() ?? '';
    if (!mounted || normalized.isEmpty) return;
    if (!RegExp(r'^[A-Z0-9]{1,6}(?:-[0-9]{1,2})?$').hasMatch(normalized) ||
        normalized == widget.controller.callsign.toUpperCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid callsign different from your own'),
        ),
      );
      return;
    }
    await _open(normalized);
  }

  Future<void> _open(String remote) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationScreen(
          controller: widget.controller,
          remoteCallsign: remote,
          aprsSession: widget.aprsSession,
        ),
      ),
    );
    widget.controller.closeConversation();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final session = widget.aprsSession;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Messages'),
            if (session != null) ...[
              const SizedBox(width: 10),
              AprsReceiveIndicator(session: session),
            ],
          ],
        ),
        actions: [
          IconButton(
            key: const Key('getNewMessages'),
            onPressed: controller.synchronizing ? null : controller.reconcile,
            tooltip: controller.synchronizing
                ? 'Getting new messages…'
                : 'Get new messages',
            icon: controller.synchronizing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('newConversation'),
        onPressed: _newConversation,
        tooltip: 'New conversation',
        child: const Icon(Icons.edit_outlined),
      ),
      body: Column(
        children: [
          if (controller.connectionState ==
                  RealtimeConnectionState.reconnecting ||
              controller.connectionState ==
                  RealtimeConnectionState.disconnected ||
              controller.connectionState ==
                  RealtimeConnectionState.authenticationRequired)
            MaterialBanner(
              content: Text(
                controller.connectionState ==
                        RealtimeConnectionState.authenticationRequired
                    ? 'Authentication expired. Return and connect again.'
                    : controller.connectionState ==
                          RealtimeConnectionState.reconnecting
                    ? 'Real-time connection reconnecting…'
                    : 'Real-time connection unavailable',
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
            const Text('Unable to load conversations'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: controller.loadConversations,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (controller.conversations.isEmpty) {
      return const Center(child: Text('No conversations yet'));
    }
    return ListView.separated(
      itemCount: controller.conversations.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final item = controller.conversations[index];
        final latest = item.latestMessage;
        final session = widget.aprsSession;
        final showPeerStatus = session != null &&
            session.messageReceivePeer != null &&
            session.messageReceivePeer!.toUpperCase() ==
                item.remoteCallsign.toUpperCase();
        return ListTile(
          key: Key('conversation-${item.remoteCallsign}'),
          title: Text(item.remoteCallsign),
          subtitle: latest == null
              ? null
              : Text(
                  latest.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showPeerStatus) ...[
                AprsReceiveIndicator(
                  session: session,
                  peer: item.remoteCallsign,
                  size: 20,
                ),
                const SizedBox(width: 8),
              ],
              if (latest != null)
                Text(formatConversationTimestamp(latest.createdAt)),
              if (item.unreadCount > 0) ...[
                if (latest != null) const SizedBox(width: 8),
                Badge(label: Text('${item.unreadCount}')),
              ],
            ],
          ),
          onTap: () => _open(item.remoteCallsign),
        );
      },
    );
  }
}
