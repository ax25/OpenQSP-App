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
    this.onAuthenticationRequired,
  });

  final String callsign;
  final String token;
  final MessagesRepository repository;
  final MessagesRealtimeClient realtime;
  final Future<void> Function()? onAuthenticationRequired;
  final List<ConversationSummary> conversations = [];
  final Map<String, InternetMessage> _messagesById = {};
  final Map<String, int> _unreadByPeer = {};
  StreamSubscription<MessagingEvent>? _events;
  StreamSubscription<RealtimeConnectionState>? _connections;
  String? _syncCursor;
  bool _hasConnected = false;
  bool loading = false;
  String? error;
  String? openRemoteCallsign;
  RealtimeConnectionState connectionState = RealtimeConnectionState.connecting;

  List<InternetMessage> historyFor(String remote) {
    final peer = _key(remote);
    final result = _messagesById.values
        .where((message) => _key(message.peerFor(callsign)) == peer)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List.unmodifiable(result);
  }

  Future<void> start() async {
    _events ??= realtime.events.listen(_applyEvent, onError: (_) {
      connectionState = RealtimeConnectionState.disconnected;
      notifyListeners();
    });
    _connections ??= realtime.connectionStates.listen(_connectionChanged);
    try {
      await realtime.connect(callsign: callsign, token: token);
    } on Object {
      connectionState = RealtimeConnectionState.disconnected;
    }
    await loadConversations();
  }

  void _connectionChanged(RealtimeConnectionState state) {
    connectionState = state;
    notifyListeners();
    if (state == RealtimeConnectionState.authenticationRequired) {
      final callback = onAuthenticationRequired;
      if (callback != null) unawaited(callback());
      return;
    }
    if (state != RealtimeConnectionState.connected) return;
    if (_hasConnected) {
      unawaited(reconcile());
    } else {
      _hasConnected = true;
    }
  }

  Future<void> loadConversations() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final loaded = await repository.messages(
        callsign: callsign,
        token: token,
      );
      _mergeAll(loaded);
      final initialSync = await repository.sync(token: token);
      _syncCursor = initialSync.cursor;
      _mergeAll(initialSync.messages);
    } on Object catch (value) {
      error = value.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> reconcile() async {
    try {
      final batch = await repository.sync(token: token, cursor: _syncCursor);
      _syncCursor = batch.cursor;
      _mergeAll(batch.messages);
      error = null;
      notifyListeners();
    } on Object catch (value) {
      error = value.toString();
      notifyListeners();
    }
  }

  Future<void> openConversation(String remote) async {
    final normalized = _key(remote);
    openRemoteCallsign = normalized;
    _unreadByPeer[normalized] = 0;
    notifyListeners();
    final loaded = await repository.messages(
      callsign: callsign,
      token: token,
      withCallsign: normalized,
    );
    _mergeAll(loaded);
    _unreadByPeer[normalized] = 0;
    _rebuildConversations();
    notifyListeners();
  }

  void closeConversation() => openRemoteCallsign = null;

  Future<void> send(String remote, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (trimmed.length > maximumMessageLength) {
      throw ArgumentError.value(
        text,
        'text',
        'Message cannot exceed $maximumMessageLength characters',
      );
    }
    final message = await repository.send(
      callsign: callsign,
      remoteCallsign: _key(remote),
      text: trimmed,
      token: token,
    );
    _merge(message);
    notifyListeners();
  }

  void _applyEvent(MessagingEvent event) {
    switch (event) {
      case MessageReceived(:final message):
        final isNew = !_messagesById.containsKey(message.id);
        final peer = _key(message.peerFor(callsign));
        if (isNew &&
            message.directionFor(callsign) == MessageDirection.received &&
            openRemoteCallsign != peer) {
          _unreadByPeer[peer] = (_unreadByPeer[peer] ?? 0) + 1;
        }
        _merge(message);
    }
    notifyListeners();
  }

  void _mergeAll(Iterable<InternetMessage> messages) {
    for (final message in messages) {
      _messagesById[message.id] = message;
    }
    _rebuildConversations();
  }

  void _merge(InternetMessage message) {
    _messagesById[message.id] = message;
    _rebuildConversations();
  }

  void _rebuildConversations() {
    final latestByPeer = <String, InternetMessage>{};
    for (final message in _messagesById.values) {
      final peer = _key(message.peerFor(callsign));
      final previous = latestByPeer[peer];
      if (previous == null || message.createdAt.isAfter(previous.createdAt)) {
        latestByPeer[peer] = message;
      }
    }
    conversations
      ..clear()
      ..addAll(
        latestByPeer.entries.map(
          (entry) => ConversationSummary(
            remoteCallsign: entry.key,
            latestMessage: entry.value,
            unreadCount: _unreadByPeer[entry.key] ?? 0,
          ),
        ),
      )
      ..sort(
        (a, b) => b.latestMessage.createdAt.compareTo(
          a.latestMessage.createdAt,
        ),
      );
  }

  String _key(String value) => value.trim().toUpperCase();

  @override
  void dispose() {
    unawaited(_events?.cancel());
    unawaited(_connections?.cancel());
    unawaited(realtime.close());
    super.dispose();
  }
}
