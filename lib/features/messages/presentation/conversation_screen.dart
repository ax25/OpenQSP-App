import 'dart:async';

import 'package:flutter/material.dart';

import '../../aprs/application/aprs_session_controller.dart';
import '../../aprs/presentation/aprs_receive_indicator.dart';
import '../application/messages_controller.dart';
import '../data/messages_transport.dart';
import '../domain/message_models.dart';
import 'message_date_format.dart';
import 'pending_message_composer.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.controller,
    required this.remoteCallsign,
    this.aprsSession,
  });
  final MessagesController controller;
  final String remoteCallsign;
  final AprsSessionController? aprsSession;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen>
    with WidgetsBindingObserver {
  final _composer = TextEditingController();
  final _composerFocus = FocusNode();
  final _scrollController = ScrollController();
  final Set<int> _downloadingMissingSequences = <int>{};
  final Set<String> _highlightedMessageIds = <String>{};
  final Map<String, Timer> _highlightTimers = <String, Timer>{};
  bool _loading = true;
  String? _error;
  int _messageCount = 0;
  bool _keepBottomVisibleDuringKeyboardResize = false;
  int _initialBottomScrollGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
    pendingMessageComposer.addListener(_pendingComposerChanged);
    _scrollController.addListener(_scrollChanged);
    final pendingText = pendingMessageComposer.textFor(
      widget.controller,
      widget.remoteCallsign,
    );
    if (pendingText.isNotEmpty) _composer.text = pendingText;
    _load();
  }

  Future<void> _load() async {
    try {
      await widget.controller.openConversation(widget.remoteCallsign);
    } on Object catch (error) {
      _error = error.toString();
    }
    if (!mounted) return;
    _messageCount = widget.controller.historyFor(widget.remoteCallsign).length;
    setState(() => _loading = false);
    _stabilizeInitialBottomScroll();
  }

  void _changed() {
    if (!mounted) return;
    final nextCount = widget.controller.historyFor(widget.remoteCallsign).length;
    final hasNewMessage = nextCount > _messageCount;
    _messageCount = nextCount;
    setState(() {});
    if (hasNewMessage) _stabilizeInitialBottomScroll();
  }

  void _pendingComposerChanged() {
    if (!mounted) return;
    final text = pendingMessageComposer.textFor(
      widget.controller,
      widget.remoteCallsign,
    );
    final sending = pendingMessageComposer.isSending(
      widget.controller,
      widget.remoteCallsign,
    );
    if (_composer.text != text && (text.isNotEmpty || !sending)) {
      _composer.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    setState(() {});
  }

  bool _isAtBottom() {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels <= 24;
  }

  void _prepareForKeyboard() {
    _keepBottomVisibleDuringKeyboardResize = _isAtBottom();
  }

  void _scrollChanged() {
    if (!_composerFocus.hasFocus) return;
    _keepBottomVisibleDuringKeyboardResize = _isAtBottom();
  }

  @override
  void didChangeMetrics() {
    if (!_keepBottomVisibleDuringKeyboardResize) return;
    _scrollToLatest(immediate: true);
  }

  void _stabilizeInitialBottomScroll() {
    final generation = ++_initialBottomScrollGeneration;
    double? previousExtent;
    var stableFrames = 0;

    void settle(_) {
      if (!mounted || generation != _initialBottomScrollGeneration) return;
      if (!_scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback(settle);
        return;
      }

      final position = _scrollController.position;
      final extent = position.maxScrollExtent;
      if (previousExtent == null || (extent - previousExtent!).abs() > 0.5) {
        stableFrames = 0;
      } else {
        stableFrames++;
      }
      previousExtent = extent;

      if ((position.pixels - extent).abs() > 0.5) {
        position.jumpTo(extent);
      }

      if (stableFrames < 2) {
        WidgetsBinding.instance.addPostFrameCallback(settle);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback(settle);
  }

  void _scrollToLatest({bool immediate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (immediate) {
        _scrollController.jumpTo(target);
        return;
      }
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _clearConversation() async {
    await widget.controller.clearConversation(widget.remoteCallsign);
    if (!mounted) return;
    _messageCount = 0;
    _composerFocus.requestFocus();
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    final sending = pendingMessageComposer.isSending(
      widget.controller,
      widget.remoteCallsign,
    );
    if (sending || text.isEmpty || !messageBodyFitsProtocol(text)) return;

    _keepBottomVisibleDuringKeyboardResize = true;
    _composerFocus.requestFocus();
    _scrollToLatest(immediate: true);
    setState(() => _error = null);
    try {
      await pendingMessageComposer.send(
        controller: widget.controller,
        remoteCallsign: widget.remoteCallsign,
        text: text,
      );
      if (!mounted) return;
      _composerFocus.requestFocus();
      _scrollToLatest();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Message could not be sent: $error');
      _composerFocus.requestFocus();
    }
  }

  Future<void> _downloadMissingMessage(int sequence) async {
    if (_downloadingMissingSequences.contains(sequence)) return;
    final repository = widget.controller.repository;
    if (repository is! MissingMessageRepository) {
      setState(() {
        _error = 'Selective message download is not supported by this transport.';
      });
      return;
    }

    setState(() {
      _error = null;
      _downloadingMissingSequences.add(sequence);
    });
    try {
      final message = await repository.getMessage(
        peer: widget.remoteCallsign,
        conversationSequence: sequence,
        token: widget.controller.token,
      );
      await widget.controller.localStore.upsert(
        widget.controller.callsign,
        message,
      );
      await widget.controller.loadConversations();
      if (!mounted) return;

      _highlightTimers.remove(message.id)?.cancel();
      setState(() {
        _downloadingMissingSequences.remove(sequence);
        _highlightedMessageIds.add(message.id);
      });
      _highlightTimers[message.id] = Timer(const Duration(seconds: 4), () {
        _highlightTimers.remove(message.id);
        if (!mounted) return;
        setState(() => _highlightedMessageIds.remove(message.id));
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _downloadingMissingSequences.remove(sequence);
        _error = 'Message could not be downloaded: $error';
      });
    }
  }

  @override
  void dispose() {
    _initialBottomScrollGeneration++;
    for (final timer in _highlightTimers.values) {
      timer.cancel();
    }
    _highlightTimers.clear();
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_changed);
    pendingMessageComposer.removeListener(_pendingComposerChanged);
    _scrollController.removeListener(_scrollChanged);
    _composer.dispose();
    _composerFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.controller.historyFor(widget.remoteCallsign);
    final timeline = _buildConversationTimeline(
      messages,
      localCallsign: widget.controller.callsign,
      remoteCallsign: widget.remoteCallsign,
    );
    final sending = pendingMessageComposer.isSending(
      widget.controller,
      widget.remoteCallsign,
    );
    final composerText = _composer.text.trim();
    final composerBytes = messageBodyUtf8Length(composerText);
    final composerFits = composerBytes <= maximumMessageLength;
    final canSend = !sending && composerText.isNotEmpty && composerFits;
    final session = widget.aprsSession;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.remoteCallsign),
            if (session != null) ...[
              const SizedBox(width: 10),
              AprsReceiveIndicator(
                session: session,
                peer: widget.remoteCallsign,
              ),
            ],
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            key: const Key('conversationMenu'),
            tooltip: 'Conversation options',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'clear') _clearConversation();
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                value: 'clear',
                enabled: messages.isNotEmpty,
                child: const Text('Vaciar conversación'),
              ),
            ],
          ),
        ],
      ),
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
                  key: const Key('messageList'),
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: timeline.length,
                  itemBuilder: (_, index) {
                    final item = timeline[index];
                    final Widget content;
                    final Key contentKey;
                    if (item is _MissingConversationMessage) {
                      contentKey = ValueKey<String>('missing-${item.sequence}');
                      content = _MissingMessagePlaceholder(
                        sequence: item.sequence,
                        downloading: _downloadingMissingSequences.contains(
                          item.sequence,
                        ),
                        onTap: () => _downloadMissingMessage(item.sequence),
                      );
                    } else {
                      final messageItem = item as _ConversationMessage;
                      final message = messageItem.message;
                      final sent =
                          message.directionFor(widget.controller.callsign) ==
                          MessageDirection.sent;
                      final colors = Theme.of(context).colorScheme;
                      final highlighted = _highlightedMessageIds.contains(
                        message.id,
                      );
                      contentKey = ValueKey<String>('timeline-message-${message.id}');
                      content = Column(
                        children: [
                          if (messageItem.showDate)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Text(
                                formatMessageDateSeparator(message.createdAt),
                                key: Key('date-${message.id}'),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
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
                                  child: AnimatedContainer(
                                    key: Key('message-highlight-${message.id}'),
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOut,
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: highlighted
                                          ? colors.tertiaryContainer
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Card(
                                      color: sent
                                          ? colors.surfaceContainerHighest
                                          : colors.primaryContainer,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        child: Text(
                                          message.body,
                                          style: TextStyle(
                                            color: sent
                                                ? colors.onSurfaceVariant
                                                : colors.onPrimaryContainer,
                                          ),
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
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: colors.onSurfaceVariant,
                                            ),
                                      ),
                                      if (sent) ...[
                                        const SizedBox(width: 3),
                                        _MessageStatusIcon(
                                          message: message,
                                          controller: widget.controller,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      reverseDuration: const Duration(milliseconds: 120),
                      switchInCurve: Curves.easeIn,
                      switchOutCurve: Curves.easeOut,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: child,
                      ),
                      child: KeyedSubtree(key: contentKey, child: content),
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
                  focusNode: _composerFocus,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    labelText: 'Message',
                    counterText: '$composerBytes/$maximumMessageLength bytes',
                    counterStyle: composerFits
                        ? null
                        : TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  onChanged: (_) => setState(() {}),
                  onTap: _prepareForKeyboard,
                  onSubmitted: (_) {
                    _keepBottomVisibleDuringKeyboardResize = true;
                    _composerFocus.requestFocus();
                    _send();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const Key('sendMessage'),
                onPressed: canSend ? _send : null,
                icon: sending
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

sealed class _ConversationTimelineItem {
  const _ConversationTimelineItem();
}

final class _ConversationMessage extends _ConversationTimelineItem {
  const _ConversationMessage({required this.message, required this.showDate});

  final InternetMessage message;
  final bool showDate;
}

final class _MissingConversationMessage extends _ConversationTimelineItem {
  const _MissingConversationMessage(this.sequence);

  final int sequence;
}

List<_ConversationTimelineItem> _buildConversationTimeline(
  List<InternetMessage> messages, {
  required String localCallsign,
  required String remoteCallsign,
}) {
  final timeline = <_ConversationTimelineItem>[];
  InternetMessage? previousMessage;
  int? previousIncomingSequence;
  final normalizedRemote = remoteCallsign.toUpperCase();

  for (final message in messages) {
    final isIncomingFromPeer =
        message.directionFor(localCallsign) == MessageDirection.received &&
        message.from.toUpperCase() == normalizedRemote;
    final sequence = isIncomingFromPeer ? message.conversationSequence : null;

    if (sequence != null && previousIncomingSequence != null) {
      for (
        var missing = previousIncomingSequence + 1;
        missing < sequence;
        missing++
      ) {
        timeline.add(_MissingConversationMessage(missing));
      }
    }

    final showDate = previousMessage == null ||
        !messagesAreOnSameLocalDay(
          previousMessage.createdAt,
          message.createdAt,
        );
    timeline.add(_ConversationMessage(message: message, showDate: showDate));
    previousMessage = message;

    if (sequence != null &&
        (previousIncomingSequence == null || sequence > previousIncomingSequence)) {
      previousIncomingSequence = sequence;
    }
  }

  return timeline;
}

class _MissingMessagePlaceholder extends StatelessWidget {
  const _MissingMessagePlaceholder({
    required this.sequence,
    required this.downloading,
    required this.onTap,
  });

  final int sequence;
  final bool downloading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: !downloading,
      label: downloading
          ? 'Downloading missing message, sequence $sequence'
          : 'Message not downloaded, sequence $sequence. Tap to download.',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Material(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              key: Key('missing-message-$sequence'),
              borderRadius: BorderRadius.circular(12),
              onTap: downloading ? null : onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (downloading)
                      SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          key: Key('missing-message-spinner-$sequence'),
                          strokeWidth: 2,
                        ),
                      )
                    else
                      Icon(
                        Icons.arrow_downward,
                        key: Key('missing-message-download-$sequence'),
                        size: 16,
                        color: colors.onSurfaceVariant,
                      ),
                    const SizedBox(width: 6),
                    Text(
                      downloading ? 'Downloading message' : 'Message not downloaded',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '#$sequence',
                      key: Key('missing-message-sequence-$sequence'),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageStatusIcon extends StatelessWidget {
  const _MessageStatusIcon({
    required this.message,
    required this.controller,
  });

  final InternetMessage message;
  final MessagesController controller;

  @override
  Widget build(BuildContext context) {
    switch (message.deliveryStatus) {
      case MessageDeliveryStatus.processing:
        return const Tooltip(
          message: 'Waiting for server confirmation',
          child: SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(
              key: Key('status-processing'),
              strokeWidth: 1.8,
            ),
          ),
        );
      case MessageDeliveryStatus.retry:
        return Tooltip(
          message: 'No confirmation received. Tap to retry',
          child: InkResponse(
            key: Key('retry-${message.id}'),
            onTap: () => controller.retryMessage(message.id),
            radius: 14,
            child: const Padding(
              padding: EdgeInsets.all(1),
              child: Icon(Icons.refresh, size: 16),
            ),
          ),
        );
      case MessageDeliveryStatus.stored:
        return _check('Stored on server', Colors.grey);
      case MessageDeliveryStatus.delivered:
        return _check('Delivered to recipient', Colors.green);
      case MessageDeliveryStatus.read:
        return _check('Read by recipient', Colors.blue);
    }
  }

  Widget _check(String label, Color color) => Tooltip(
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
