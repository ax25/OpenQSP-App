import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/contracts.dart';
import '../domain/models.dart';

class MessagesController extends ChangeNotifier {
  MessagesController({
    required this.localCallsign,
    required this.api,
    required this.socket,
  });

  final String localCallsign;
  final MessagesApi api;
  final MessagesSocket socket;
  final Map<String, List<InternetMessage>> _messages = {};
  List<Conversation> conversations = const [];
  Object? error;
  bool loading = false;
  bool sending = false;
  MessagingConnectionState connection = MessagingConnectionState.disconnected;
  StreamSubscription<MessagingEvent>? _events;
  StreamSubscription<MessagingConnectionState>? _states;

  List<InternetMessage> messagesFor(String remote) =>
      List.unmodifiable(_messages[remote.toUpperCase()] ?? const []);

  Future<void> start(String token) async {
    _events = socket.events.listen(_applyEvent, onError: _socketError);
    _states = socket.states.listen((value) {
      connection = value;
      notifyListeners();
      if (value == MessagingConnectionState.connected) reload();
    });
    await Future.wait([reload(), socket.connect(token)]);
  }

  Future<void> reload() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      conversations = await api.conversations();
    } catch (value) {
      error = value;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadHistory(String remote) async {
    error = null;
    notifyListeners();
    try {
      final values = await api.history(remote);
      _messages[remote.toUpperCase()] = _deduplicate(values)..sort(_byTime);
    } catch (value) {
      error = value;
    }
    notifyListeners();
  }

  Future<bool> send(String remote, String text) async {
    if (sending || text.trim().isEmpty) return false;
    sending = true;
    error = null;
    notifyListeners();
    try {
      _merge(await api.send(remote, text.trim()));
      return true;
    } catch (value) {
      error = value;
      return false;
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  Future<bool> deleteMessage(String id) async {
    try {
      await api.deleteMessage(id);
      _remove(id);
      notifyListeners();
      return true;
    } catch (value) {
      error = value;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteConversation(String remote) async {
    try {
      await api.deleteConversation(remote);
      final key = remote.toUpperCase();
      _messages.remove(key);
      conversations = conversations
          .where((item) => item.remoteCallsign.toUpperCase() != key)
          .toList();
      notifyListeners();
      return true;
    } catch (value) {
      error = value;
      notifyListeners();
      return false;
    }
  }

  void markRead(String remote) {
    final key = remote.toUpperCase();
    conversations = conversations
        .map((c) => c.remoteCallsign.toUpperCase() == key
            ? Conversation(remoteCallsign: c.remoteCallsign, latestMessage: c.latestMessage)
            : c)
        .toList();
    notifyListeners();
  }

  void _applyEvent(MessagingEvent event) {
    if (event is MessageReceived) _merge(event.message, incoming: true);
    if (event is MessageDeleted) _remove(event.messageId);
    notifyListeners();
  }

  void _merge(InternetMessage message, {bool incoming = false}) {
    final remote = message.remoteFor(localCallsign).toUpperCase();
    final list = _messages.putIfAbsent(remote, () => []);
    final index = list.indexWhere((item) => item.id == message.id);
    if (index < 0) {
      list.add(message);
    } else {
      list[index] = message;
    }
    list.sort(_byTime);
    Conversation? old;
    for (final conversation in conversations) {
      if (conversation.remoteCallsign.toUpperCase() == remote) {
        old = conversation;
        break;
      }
    }
    conversations = [
      Conversation(
        remoteCallsign: remote,
        latestMessage: message,
        unread: incoming && message.sender.toUpperCase() != localCallsign.toUpperCase()
            ? (old?.unread ?? 0) + (index < 0 ? 1 : 0)
            : old?.unread ?? 0,
      ),
      ...conversations.where((c) => c.remoteCallsign.toUpperCase() != remote),
    ];
  }

  void _remove(String id) {
    for (final entry in _messages.entries) {
      entry.value.removeWhere((item) => item.id == id);
    }
  }

  List<InternetMessage> _deduplicate(List<InternetMessage> values) =>
      {for (final value in values) value.id: value}.values.toList();
  int _byTime(InternetMessage a, InternetMessage b) => a.sentAt.compareTo(b.sentAt);
  void _socketError(Object value) { error = value; notifyListeners(); }

  @override
  void dispose() {
    _events?.cancel();
    _states?.cancel();
    socket.disconnect();
    super.dispose();
  }
}
