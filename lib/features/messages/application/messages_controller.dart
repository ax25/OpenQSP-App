import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/conversation_visibility_store.dart';
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
    ConversationVisibilityStore? visibilityStore,
    this.onAuthenticationRequired,
  }) : localStore = localStore ?? PreferencesLocalMessagesStore(),
       visibilityStore = visibilityStore ??
           (localStore == null
               ? PreferencesConversationVisibilityStore()
               : MemoryConversationVisibilityStore());

  final String callsign;
  final String token;
  final MessagesRepository repository;
  final MessagesRealtimeClient realtime;
  final LocalMessagesStore localStore;
  final ConversationVisibilityStore visibilityStore;
  final Future<void> Function()? onAuthenticationRequired;
  final List<ConversationSummary> conversations = [];
  final Map<String, InternetMessage> _messagesById = {};
  final Map<String, int> _unreadByPeer = {};
  final Map<String, MessageDeliveryStatus> _earlySendStatuses = {};
  final Map<String, DateTime> _clearBeforeByPeer = {};
  StreamSubscription<MessagingEvent>? _events;
  StreamSubscription<RealtimeConnectionState>? _connections;
  Future<void>? _reconcileInFlight;
  Future<void> _eventTail = Future<void>.value();
  bool _hasConnected = false;
  bool loading = false;
  String? error;
  String? openRemoteCallsign;
  RealtimeConnectionState connectionState = RealtimeConnectionState.connecting;

  String get _syncCursorKey => messagesSyncCursorKey(repository);
  bool get synchronizing => _reconcileInFlight != null;

  List<InternetMessage> historyFor(String remote) {
    final peer = _key(remote);
    final cutoff = _clearBeforeByPeer[peer];
    final result = _allHistoryFor(peer)
        .where((message) => cutoff == null || message.createdAt.isAfter(cutoff))
        .toList();
    return List.unmodifiable(result);
  }

  List<InternetMessage> _allHistoryFor(String remote) {
    final peer = _key(remote);
    final result = _messagesById.values
        .where((message) => _key(message.peerFor(callsign)) == peer)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return result;
  }

  Future<void> start() async {
    await _loadLocal();
    _events ??= realtime.events.listen(
      (event) {
        _eventTail = _eventTail.then((_) => _applyEvent(event));
      },
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
      _clearBeforeByPeer
        ..clear()
        ..addAll(await visibilityStore.cutoffs(callsign));
      final local = await localStore.messages(callsign);
      final recovered = <InternetMessage>[];
      final changed = <InternetMessage>[];
      for (final message in local) {
        if (message.id.startsWith('aprs-local-') &&
            message.deliveryStatus == MessageDeliveryStatus.processing) {
          final retryable = message.copyWith(
            deliveryStatus: MessageDeliveryStatus.retry,
          );
          recovered.add(retryable);
          changed.add(retryable);
        } else {
          recovered.add(message);
        }
      }
      if (changed.isNotEmpty) {
        await localStore.upsertAll(callsign, changed);
      }
      _mergeAll(recovered);
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
    final previous = connectionState;
    if (previous == state) return;

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
      // Mark-read is best effort; local conversation access must still work.
    }
  }

  Future<void> clearConversation(String remote) async {
    final peer = _key(remote);
    final history = _allHistoryFor(peer);
    if (history.isEmpty) return;
    final newest = history.last.createdAt.toUtc();
    final current = _clearBeforeByPeer[peer];
    if (current == null || newest.isAfter(current)) {
      _clearBeforeByPeer[peer] = newest;
      await visibilityStore.setCutoff(callsign, peer, newest);
    }
    _unreadByPeer[peer] = 0;
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
    final earlyStatus = _earlySendStatuses.remove(message.id);
    final resolved = earlyStatus != null &&
            _statusRank(earlyStatus) >= _statusRank(message.deliveryStatus)
        ? message.copyWith(deliveryStatus: earlyStatus)
        : message;
    _merge(resolved);
    notifyListeners();
    await localStore.upsert(callsign, resolved);
  }

  Future<void> retryMessage(String messageId) async {
    final retryable = repository;
    if (retryable is! RetryableMessagesRepository) return;
    final current = _messagesById[messageId];
    if (current == null || current.deliveryStatus != MessageDeliveryStatus.retry) {
      return;
    }
    final updated = current.copyWith(
      deliveryStatus: MessageDeliveryStatus.processing,
    );
    _messagesById[messageId] = updated;
    await localStore.upsert(callsign, updated);
    _rebuildConversations();
    notifyListeners();
    try {
      await (retryable as RetryableMessagesRepository).retryMessage(current);
    } on Object {
      final failed = updated.copyWith(deliveryStatus: MessageDeliveryStatus.retry);
      _messagesById[messageId] = failed;
      await localStore.upsert(callsign, failed);
      _rebuildConversations();
      notifyListeners();
    }
  }

  Future<void> _applyEvent(MessagingEvent event) async {
    switch (event) {
      case MessageReceived(:final message, :final syncCursor):
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
        if (syncCursor != null) {
          await localStore.setCursor(callsign, _syncCursorKey, syncCursor);
        }
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
      case MessageSendStatusChanged(:final messageId, :final status):
        final current = _messagesById[messageId];
        if (current == null) {
          final previous = _earlySendStatuses[messageId];
          if (previous == null ||
              _statusRank(status) >= _statusRank(previous) ||
              ((status == MessageDeliveryStatus.processing ||
                      status == MessageDeliveryStatus.retry) &&
                  (previous == MessageDeliveryStatus.processing ||
                      previous == MessageDeliveryStatus.retry))) {
            _earlySendStatuses[messageId] = status;
          }
        } else if (_statusRank(status) >= _statusRank(current.deliveryStatus)) {
          final updated = current.copyWith(deliveryStatus: status);
          _messagesById[messageId] = updated;
          await localStore.upsert(callsign, updated);
          _rebuildConversations();
        } else if ((status == MessageDeliveryStatus.processing ||
                status == MessageDeliveryStatus.retry) &&
            (current.deliveryStatus == MessageDeliveryStatus.processing ||
                current.deliveryStatus == MessageDeliveryStatus.retry)) {
          final updated = current.copyWith(deliveryStatus: status);
          _messagesById[messageId] = updated;
          await localStore.upsert(callsign, updated);
          _rebuildConversations();
        }
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
      // Mark-read is best effort; realtime delivery remains usable.
    }
  }

  Future<void> _applyReadCursor(String peer, String lastReadMessageId) async {
    final history = _allHistoryFor(peer);
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
    MessageDeliveryStatus.processing || MessageDeliveryStatus.retry => 0,
    MessageDeliveryStatus.stored => 1,
    MessageDeliveryStatus.delivered => 2,
    MessageDeliveryStatus.read => 3,
  };

  void _rebuildConversations() {
    final latestAllByPeer = <String, InternetMessage>{};
    final latestVisibleByPeer = <String, InternetMessage>{};
    for (final message in _messagesById.values) {
      final peer = _key(message.peerFor(callsign));
      final previousAll = latestAllByPeer[peer];
      if (previousAll == null || message.createdAt.isAfter(previousAll.createdAt)) {
        latestAllByPeer[peer] = message;
      }
      final cutoff = _clearBeforeByPeer[peer];
      if (cutoff != null && !message.createdAt.isAfter(cutoff)) continue;
      final previousVisible = latestVisibleByPeer[peer];
      if (previousVisible == null ||
          message.createdAt.isAfter(previousVisible.createdAt)) {
        latestVisibleByPeer[peer] = message;
      }
    }
    conversations
      ..clear()
      ..addAll(
        latestAllByPeer.entries.map(
          (entry) => ConversationSummary(
            remoteCallsign: entry.key,
            latestMessage: latestVisibleByPeer[entry.key],
            lastActivityAt: latestVisibleByPeer[entry.key]?.createdAt ?? entry.value.createdAt,
            unreadCount: _unreadByPeer[entry.key] ?? 0,
          ),
        ),
      )
      ..sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));
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
