import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/messages_controller.dart';
import '../domain/message_models.dart';
import 'message_date_format.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.controller,
    required this.remoteCallsign,
  });
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
    final text = _composer.text.trim();
    if (_sending || text.isEmpty || text.length > maximumMessageLength) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.controller.send(widget.remoteCallsign, text);
      _composer.clear();
    } on Object catch (error) {
      _error = 'Message could not be sent: $error';
    } finally {
      if (mounted) setState(() => _sending = false);
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
      appBar: AppBar(title: Text(widget.remoteCallsign)),
      body: Column(children: [
        if (_error != null)
          MaterialBanner(
            content: Text(_error!),
            actions: [
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : messages.isEmpty
              ? const Center(child: Text('No messages yet'))
              : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: messages.length,
            itemBuilder: (_, index) {
              final message = messages[index];
              final sent =
                  message.directionFor(widget.controller.callsign) ==
                  MessageDirection.sent;
              final showDate = index == 0 ||
                  !messagesAreOnSameLocalDay(
                    messages[index - 1].createdAt,
                    message.createdAt,
                  );
              final colors = Theme.of(context).colorScheme;
              return Column(
                children: [
                  if (showDate)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        formatMessageDateSeparator(message.createdAt),
                        key: Key('date-${message.id}'),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  Align(
                    key: Key('message-${message.id}'),
                    alignment: sent
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Flexible(
                          child: Card(
                            color: sent
                                ? colors.primaryContainer
                                : colors.surfaceContainerHighest,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Text(
                                message.body,
                                style: TextStyle(
                                  color: sent
                                      ? colors.onPrimaryContainer
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                formatMessageTime(message.createdAt),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                              if (sent) ...[
                                const SizedBox(width: 3),
                                _MessageStatusIcon(message: message),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('messageComposer'),
                  controller: _composer,
                  maxLength: maximumMessageLength,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(maximumMessageLength),
                  ],
                  decoration: const InputDecoration(labelText: 'Message'),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const Key('sendMessage'),
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _MessageStatusIcon extends StatelessWidget {
  const _MessageStatusIcon({required this.message});

  final InternetMessage message;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (message.deliveryStatus) {
      MessageDeliveryStatus.stored => ('Stored on server', Colors.grey),
      MessageDeliveryStatus.delivered => ('Delivered to recipient', Colors.green),
      MessageDeliveryStatus.read => ('Read by recipient', Colors.blue),
    };
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Icon(
          Icons.check,
          key: Key('status-${message.id}'),
          size: 16,
          color: color,
        ),
      ),
    );
  }
}
