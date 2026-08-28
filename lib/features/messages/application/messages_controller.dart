import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/messages_transport.dart';
import '../domain/message_models.dart';

class MessagesController extends ChangeNotifier {
  MessagesController({
    required this.callsign,
    required this.token,
    required this.repository,
    required this.realtime,
  });

  final String callsign;
  final String token;
  final MessagesRepository repository;
  final MessagesRealtimeClient realtime;
  final List<ConversationSummary> conversations = [];
  final Map<String, List<InternetMessage>> _history = {};
  StreamSubscription<MessagingEvent>? _events;
  StreamSubscription<RealtimeConnectionState>? _connections;
  bool loading = false;
  String? error;
  String? openRemoteCallsign;
  RealtimeConnectionState connectionState = RealtimeConnectionState.connecting;

  List<InternetMessage> historyFor(String remote) =>
      List.unmodifiable(_history[_key(remote)] ?? const []);

  Future<void> start() async {
    _events ??= realtime.events.listen(_applyEvent, onError: (_) {
      connectionState = RealtimeConnectionState.disconnected;
      notifyListeners();
    });
    _connections ??= realtime.connectionStates.listen((state) {
      connectionState = state;
      notifyListeners();
      if (state == RealtimeConnectionState.connected) {
        unawaited(loadConversations());
      }
    });
    try {
      await realtime.connect(callsign: callsign, token: token);
    } on Object {
      connectionState = RealtimeConnectionState.disconnected;
    }
    await loadConversations();
  }

  Future<void> loadConversations() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final loaded = await repository.conversations(
        callsign: callsign,
        token: token,
      );
      conversations
        ..clear()
        ..addAll(loaded);
      _sortConversations();
    } on Object catch (value) {
      error = value.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> openConversation(String remote) async {
    final normalized = _key(remote);
    openRemoteCallsign = normalized;
    notifyListeners();
    final loaded = await repository.history(
      callsign: callsign,
      remoteCallsign: normalized,
      token: token,
    );
    _history[normalized] = [];
    for (final message in loaded) {
      _mergeMessage(message);
    }
    final index = _conversationIndex(normalized);
    if (index >= 0) {
      conversations[index] = conversations[index].copyWith(unreadCount: 0);
    }
    notifyListeners();
  }

  void closeConversation() => openRemoteCallsign = null;

  Future<void> send(String remote, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final message = await repository.send(
      callsign: callsign,
      remoteCallsign: _key(remote),
      text: trimmed,
      token: token,
    );
    _mergeMessage(message);
    notifyListeners();
  }

  Future<void> deleteMessage(String remote, String id) async {
    await repository.deleteMessage(
      callsign: callsign,
      remoteCallsign: _key(remote),
      messageId: id,
      token: token,
    );
    _removeMessage(_key(remote), id);
    notifyListeners();
  }

  Future<void> deleteConversation(String remote) async {
    await repository.deleteConversation(
      callsign: callsign,
      remoteCallsign: _key(remote),
      token: token,
    );
    _removeConversation(_key(remote));
    notifyListeners();
  }

  void _applyEvent(MessagingEvent event) {
    switch (event) {
      case MessageReceived(:final message):
        _mergeMessage(message, live: true);
      case MessageRemoved(:final remoteCallsign, :final messageId):
        _removeMessage(_key(remoteCallsign), messageId);
      case ConversationRemoved(:final remoteCallsign):
        _removeConversation(_key(remoteCallsign));
    }
    notifyListeners();
  }

  void _mergeMessage(InternetMessage message, {bool live = false}) {
    final remote = _key(message.remoteCallsign);
    final messages = _history.putIfAbsent(remote, () => []);
    if (!messages.any((existing) => existing.id == message.id)) {
      messages.add(message);
      messages.sort(
        (a, b) => (a.sentAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(b.sentAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
    }
    final index = _conversationIndex(remote);
    final unread =
        live &&
        message.direction == MessageDirection.received &&
        openRemoteCallsign != remote;
    final summary = ConversationSummary(
      remoteCallsign: remote,
      latestMessage: message.text,
      latestActivity: message.sentAt,
      unreadCount:
          (index < 0 ? 0 : conversations[index].unreadCount) +
          (unread ? 1 : 0),
    );
    if (index < 0) {
      conversations.add(summary);
    } else {
      conversations[index] = summary;
    }
    _sortConversations();
  }

  void _removeMessage(String remote, String id) {
    _history[remote]?.removeWhere((message) => message.id == id);
  }

  void _removeConversation(String remote) {
    conversations.removeWhere((item) => _key(item.remoteCallsign) == remote);
    _history.remove(remote);
  }

  int _conversationIndex(String remote) => conversations.indexWhere(
    (item) => _key(item.remoteCallsign) == remote,
  );
  String _key(String value) => value.trim().toUpperCase();
  void _sortConversations() => conversations.sort(
    (a, b) => (b.latestActivity ?? DateTime.fromMillisecondsSinceEpoch(0))
        .compareTo(a.latestActivity ?? DateTime.fromMillisecondsSinceEpoch(0)),
  );

  @override
  void dispose() {
    _events?.cancel();
    _connections?.cancel();
    unawaited(realtime.close());
    super.dispose();
  }
}
