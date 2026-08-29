import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/local_messages_store.dart';
import '../data/messages_transport.dart';
import '../domain/message_models.dart';

class MessagesController extends ChangeNotifier {
  MessagesController({
    required this.callsign,
    required this.token,
    required this.repository,
    required this.realtime,
    LocalMessagesStore? localStore,
    this.onAuthenticationRequired,
  }) : localStore = localStore ?? PreferencesLocalMessagesStore();

  final String callsign;
  final String token;
  final MessagesRepository repository;
  final MessagesRealtimeClient realtime;
  final LocalMessagesStore localStore;
  final Future<void> Function()? onAuthenticationRequired;
  final List<ConversationSummary> conversations = [];
  final Map<String, InternetMessage> _messagesById = {};
  final Map<String, int> _unreadByPeer = {};
  StreamSubscription<MessagingEvent>? _events;
  StreamSubscription<RealtimeConnectionState>? _connections;
  Future<void>? _reconcileInFlight;
  bool _hasConnected = false;
  bool loading = false;
  String? error;
  String? openRemoteCallsign;
  RealtimeConnectionState connectionState = RealtimeConnectionState.connecting;

  String get _syncCursorKey => messagesSyncCursorKey(repository);
  bool get synchronizing => _reconcileInFlight != null;

  List<InternetMessage> historyFor(String remote) {
    final peer = _key(remote);
    final result = _messagesById.values
        .where((message) => _key(message.peerFor(callsign)) == peer)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List.unmodifiable(result);
  }

  Future<void> start() async {
    await _loadLocal();
    _events ??= realtime.events.listen(
      (event) => unawaited(_applyEvent(event)),
      onError: (_) {
        connectionState = RealtimeConnectionState.disconnected;
        notifyListeners();
      },
    );
    _connections ??= realtime.connectionStates.listen(_connectionChanged);
    try {
      await realtime.connect(callsign: callsign, token: token);
    } on Object {
      connectionState = RealtimeConnectionState.disconnected;
      notifyListeners();
      return;
    }
    await _bootstrapLocalHistoryIfNeeded();
    await reconcile();
  }

  Future<void> _loadLocal() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      _messagesById.clear();
      _mergeAll(await localStore.messages(callsign));
    } on Object catch (value) {
      error = value.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _bootstrapLocalHistoryIfNeeded() async {
    if (_messagesById.isNotEmpty ||
        await localStore.cursor(callsign, _syncCursorKey) != null) {
      return;
    }
    try {
      final historical = await repository.messages(
        callsign: callsign,
        token: token,
      );
      if (historical.isEmpty) return;
      await localStore.upsertAll(callsign, historical);
      _mergeAll(historical);
      notifyListeners();
    } on Object {
      // Incremental sync below is authoritative. APRS deliberately has no
      // complete sent-history operation, and offline local history remains usable.
    }
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
    await _loadLocal();
    await _bootstrapLocalHistoryIfNeeded();
    await reconcile();
  }

  Future<void> reconcile() {
    final active = _reconcileInFlight;
    if (active != null) return active;
    final future = _reconcile();
    _reconcileInFlight = future;
    notifyListeners();
    return future.whenComplete(() {
      if (identical(_reconcileInFlight, future)) {
        _reconcileInFlight = null;
        notifyListeners();
      }
    });
  }

  Future<void> _reconcile() async {
    try {
      var cursor = await localStore.cursor(callsign, _syncCursorKey);
      var pages = 0;
      bool hasMore;
      do {
        final batch = await repository.sync(token: token, cursor: cursor);
        await localStore.upsertAll(callsign, batch.messages);
        _mergeAll(batch.messages);
        cursor = batch.cursor;
        await localStore.setCursor(callsign, _syncCursorKey, cursor);
        hasMore = batch.hasMore;
        pages++;
        if (pages > 10000) {
          throw StateError('Message synchronization exceeded page limit');
        }
      } while (hasMore);
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
    _rebuildConversations();
    notifyListeners();
    try {
      await repository.markConversationRead(
        remoteCallsign: normalized,
        token: token,
      );
      _unreadByPeer[normalized] = 0;
      _rebuildConversations();
      notifyListeners();
    } on Object {
      // Local history remains available. A future transport sync/read operation
      // can retry the server-side read cursor.
    }
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
    await localStore.upsert(callsign, message);
    _merge(message);
    notifyListeners();
  }

  Future<void> _applyEvent(MessagingEvent event) async {
    switch (event) {
      case MessageReceived(:final message):
        final isNew = !_containsLogicalMessage(message);
        final peer = _key(message.peerFor(callsign));
        if (isNew &&
            message.directionFor(callsign) == MessageDirection.received) {
          if (openRemoteCallsign == peer) {
            unawaited(_markOpenConversationRead(peer));
          } else {
            _unreadByPeer[peer] = (_unreadByPeer[peer] ?? 0) + 1;
          }
        }
        await localStore.upsert(callsign, message);
        _merge(message);
      case MessageDelivered(:final messageId, :final deliveredAt):
        final current = _messagesById[messageId];
        if (current != null &&
            current.deliveryStatus != MessageDeliveryStatus.read) {
          final updated = current.copyWith(
            deliveryStatus: MessageDeliveryStatus.delivered,
            deliveredAt: deliveredAt,
          );
          _messagesById[messageId] = updated;
          await localStore.upsert(callsign, updated);
          _rebuildConversations();
        }
      case MessageRead(:final peer, :final lastReadMessageId):
        await _applyReadCursor(_key(peer), lastReadMessageId);
    }
    notifyListeners();
  }

  Future<void> _markOpenConversationRead(String peer) async {
    try {
      await repository.markConversationRead(remoteCallsign: peer, token: token);
      _unreadByPeer[peer] = 0;
      _rebuildConversations();
      notifyListeners();
    } on Object {
      // A later transport sync/open can retry the durable read update.
    }
  }

  Future<void> _applyReadCursor(String peer, String lastReadMessageId) async {
    final history = historyFor(peer);
    final target = history.indexWhere((message) => message.id == lastReadMessageId);
    if (target < 0) {
      unawaited(reconcile());
      return;
    }
    final changed = <InternetMessage>[];
    for (var index = 0; index <= target; index++) {
      final message = history[index];
      if (message.directionFor(callsign) != MessageDirection.sent) continue;
      final updated = message.copyWith(
        deliveryStatus: MessageDeliveryStatus.read,
      );
      _messagesById[message.id] = updated;
      changed.add(updated);
    }
    await localStore.upsertAll(callsign, changed);
    _rebuildConversations();
  }

  void _mergeAll(Iterable<InternetMessage> messages) {
    for (final message in messages) {
      _mergeOne(message);
    }
    _rebuildConversations();
  }

  void _merge(InternetMessage message) {
    _mergeOne(message);
    _rebuildConversations();
  }

  bool _containsLogicalMessage(InternetMessage message) {
    if (_messagesById.containsKey(message.id)) return true;
    if (message.id.startsWith('aprs-local-')) return false;
    return _messagesById.values.any(
      (existing) =>
          existing.id.startsWith('aprs-local-') &&
          _sameLogicalMessage(existing, message),
    );
  }

  void _mergeOne(InternetMessage message) {
    var existing = _messagesById[message.id];
    if (existing == null && !message.id.startsWith('aprs-local-')) {
      String? provisionalId;
      for (final entry in _messagesById.entries) {
        if (entry.key.startsWith('aprs-local-') &&
            _sameLogicalMessage(entry.value, message)) {
          provisionalId = entry.key;
          existing = entry.value;
          break;
        }
      }
      if (provisionalId != null) _messagesById.remove(provisionalId);
    }
    if (existing == null ||
        _statusRank(message.deliveryStatus) >=
            _statusRank(existing.deliveryStatus)) {
      _messagesById[message.id] = message;
    }
  }

  static bool _sameLogicalMessage(
    InternetMessage first,
    InternetMessage second,
  ) =>
      first.from == second.from &&
      first.to == second.to &&
      first.body == second.body &&
      first.createdAt.millisecondsSinceEpoch ~/ 1000 ==
          second.createdAt.millisecondsSinceEpoch ~/ 1000;

  int _statusRank(MessageDeliveryStatus status) => switch (status) {
    MessageDeliveryStatus.stored => 0,
    MessageDeliveryStatus.delivered => 1,
    MessageDeliveryStatus.read => 2,
  };

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
