import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../../core/openqsp_protocol/openqsp_codec.dart';
import '../../../core/openqsp_protocol/openqsp_models.dart';
import '../../../core/openqsp_protocol/openqsp_operation.dart';
import '../../aprs/aprs/aprs_message_encoder.dart';
import '../../aprs/aprs/aprs_packet.dart';
import '../../aprs/application/aprs_session_controller.dart';
import '../../aprs/application/tnc_settings_controller.dart';
import '../../aprs/ax25/ax25_address.dart';
import '../../aprs/ax25/ax25_encoder.dart';
import '../../aprs/kiss/kiss_frame.dart';
import '../../aprs/openqsp_carriage/openqsp_aprs_carriage.dart';
import '../domain/message_models.dart';
import 'messages_transport.dart';

/// Message transport backed by the already-active APRS/KISS session.
final class AprsMessagesTransport
    implements
        MessagesRepository,
        MessagesRealtimeClient,
        MessagesSyncCursorNamespace,
        RetryableMessagesRepository {
  AprsMessagesTransport({
    required this.session,
    required String callsign,
    this.responseTimeout = const Duration(seconds: 65),
    String Function()? transactionIdFactory,
  }) : callsign = callsign.trim().toUpperCase(),
       _transactionIdFactory = transactionIdFactory ?? _randomTransactionId;

  final AprsSessionController session;
  final String callsign;
  final Duration responseTimeout;
  final String Function() _transactionIdFactory;

  static const OpenQspCodec _codec = OpenQspCodec();
  static const Ax25Encoder _ax25Encoder = Ax25Encoder();
  static const AprsMessageEncoder _messageEncoder = AprsMessageEncoder();
  static final RegExp _aprsResponseId = RegExp(r'\bID: ([0-9A-Za-z]{1,5})\b');

  final StreamController<MessagingEvent> _events =
      StreamController<MessagingEvent>.broadcast();
  final StreamController<RealtimeConnectionState> _connections =
      StreamController<RealtimeConnectionState>.broadcast();
  final List<InternetMessage> _messages = [];
  final Map<String, _PendingSend> _pendingSends = {};
  final Map<String, _PendingSend> _pendingByAprsMessageId = {};
  final List<_PendingSend> _pendingStoredOrder = [];
  Future<void> _txTail = Future<void>.value();
  Future<SyncBatch>? _syncInFlight;
  int _lastObservedOpenQspFrameCount = 0;
  int _lastObservedOpenQspFragments = 0;
  int _lastObservedAprsAcks = 0;
  int _lastObservedAprsRejects = 0;
  RealtimeConnectionState? _lastEmittedConnectionState;
  _PendingSync? _pendingSync;
  int _localSequence = 0;
  int _nextAprsMessageId = 0;
  bool _connected = false;
  bool _closed = false;

  TncSettingsController get _tnc => session.tncController;

  bool get _serverReachable =>
      session.state == AprsSessionState.available ||
      session.state == AprsSessionState.slow;

  @override
  String get syncCursorKey => 'aprs';

  @override
  Stream<MessagingEvent> get events => _events.stream;

  @override
  Stream<RealtimeConnectionState> get connectionStates => _connections.stream;

  @override
  Future<void> connect({required String callsign, required String token}) async {
    if (_closed) throw StateError('APRS messages transport is closed');
    if (callsign.trim().toUpperCase() != this.callsign) {
      throw ArgumentError.value(callsign, 'callsign', 'Unexpected APRS identity');
    }
    if (!_connected) {
      _connected = true;
      _lastObservedOpenQspFrameCount = _tnc.openQspFramesRx;
      _lastObservedOpenQspFragments = _tnc.openQspFragmentsRx;
      _lastObservedAprsAcks = _tnc.aprsAcks;
      _lastObservedAprsRejects = _tnc.aprsRejects;
      session.addListener(_onSessionChanged);
      _tnc.addListener(_onTncChanged);
    }
    _emitConnectionState();
    if (!_serverReachable) {
      throw StateError('APRS OpenQSP session is not available');
    }
  }

  void _onSessionChanged() => _emitConnectionState();

  void _emitConnectionState() {
    if (_closed) return;
    final state = switch (session.state) {
      AprsSessionState.available || AprsSessionState.slow =>
        RealtimeConnectionState.connected,
      AprsSessionState.connecting => RealtimeConnectionState.reconnecting,
      AprsSessionState.inactive ||
      AprsSessionState.notResponding ||
      AprsSessionState.unavailable => RealtimeConnectionState.disconnected,
    };
    if (_lastEmittedConnectionState == state) return;
    _lastEmittedConnectionState = state;
    _connections.add(state);
  }

  void _onTncChanged() {
    if (_closed) return;

    final ackCount = _tnc.aprsAcks;
    if (ackCount != _lastObservedAprsAcks) {
      final delta = ackCount - _lastObservedAprsAcks;
      _lastObservedAprsAcks = ackCount;
      if (delta > 0) {
        for (final id in _recentAprsResponseIds(kind: 'ACK', count: delta)) {
          _handleAprsAck(id);
        }
      }
    }

    final rejectCount = _tnc.aprsRejects;
    if (rejectCount != _lastObservedAprsRejects) {
      final delta = rejectCount - _lastObservedAprsRejects;
      _lastObservedAprsRejects = rejectCount;
      if (delta > 0) {
        for (final id in _recentAprsResponseIds(kind: 'REJ', count: delta)) {
          _handleAprsReject(id);
        }
      }
    }

    final fragmentCount = _tnc.openQspFragmentsRx;
    if (fragmentCount != _lastObservedOpenQspFragments) {
      _lastObservedOpenQspFragments = fragmentCount;
      final pending = _pendingSync;
      pending?.touch(responseTimeout);
      if (pending != null) {
        session.setActivity(AprsActivityState.gettingNewMessages);
      }
    }

    final frameCount = _tnc.openQspFramesRx;
    if (frameCount == _lastObservedOpenQspFrameCount) return;
    _lastObservedOpenQspFrameCount = frameCount;
    final object = _tnc.lastOpenQspObject;
    if (object == null) return;

    switch (object) {
      case OpenQspStored():
        final pending = _oldestPendingStoredConfirmation();
        if (pending != null) _markStored(pending);
      case OpenQspError(:final requestOperation, :final detail):
        final message = detail.isEmpty ? 'Server rejected APRS request' : detail;
        if (requestOperation == OpenQspOperation.sendMessage.code) {
          final pending = _oldestPendingStoredConfirmation();
          if (pending != null) {
            _setPendingStatus(pending, MessageDeliveryStatus.retry);
            pending.cancelTimeout();
          }
        } else if (requestOperation == OpenQspOperation.getNewMessages.code) {
          final pending = _pendingSync;
          if (pending != null && !pending.completer.isCompleted) {
            pending.completer.completeError(StateError(message));
          }
        }
      case OpenQspMessage(:final sequence):
        final message = _fromOpenQspMessage(object);
        final pending = _pendingSync;
        String? progressiveCursor;
        if (pending != null) {
          if (pending.messages.every((existing) => existing.id != message.id)) {
            pending.messages.add(message);
          }
          progressiveCursor = pending.advance(sequence);
        }

        final isNew = _messages.every((existing) => existing.id != message.id);
        if (isNew) _messages.add(message);
        session.setActivity(AprsActivityState.newMessageReceived);
        if (isNew || progressiveCursor != null) {
          _events.add(MessageReceived(message, syncCursor: progressiveCursor));
        }
      case OpenQspEnd(
        :final requestOperation,
        :final returnedCount,
        :final nextSince,
        :final hasMore,
      ):
        if (requestOperation == OpenQspOperation.getNewMessages) {
          session.setActivity(
            returnedCount == 0
                ? AprsActivityState.noNewMessages
                : AprsActivityState.newMessageReceived,
          );
          final pending = _pendingSync;
          if (pending != null && !pending.completer.isCompleted) {
            _mergeSessionMessages(pending.messages);
            pending.completer.complete(
              SyncBatch(
                messages: List.unmodifiable(pending.messages),
                cursor: '$nextSince',
                hasMore: hasMore,
              ),
            );
          }
        }
      default:
        break;
    }
  }

  List<String> _recentAprsResponseIds({
    required String kind,
    required int count,
  }) {
    final ids = <String>[];
    for (final entry in _tnc.aprsActivity) {
      if (!entry.contains('$kind  ')) continue;
      final match = _aprsResponseId.firstMatch(entry);
      final id = match?.group(1)?.toUpperCase();
      if (id == null) continue;
      ids.add(id);
      if (ids.length == count) break;
    }
    return ids.reversed.toList(growable: false);
  }

  void _handleAprsAck(String id) {
    final pending = _pendingByAprsMessageId[id];
    if (pending == null || pending.stored) return;

    _pendingByAprsMessageId.remove(id);
    if (pending.commitAckAttempt && id.startsWith('C')) {
      final isCommitAck = pending.isCommitAck(id);
      pending.acknowledge(id);
      if (isCommitAck && pending.hasBeenTransmitted) {
        _markStored(pending);
      } else {
        _setPendingStatus(pending, MessageDeliveryStatus.processing);
        pending.touch(responseTimeout, () => _timeoutPending(pending));
      }
      return;
    }

    // Legacy APRS ACK only proves that this transport packet reached the
    // server. Durable SEND_MESSAGE confirmation still comes from STORED.
    pending.forgetAck(id);
    _setPendingStatus(pending, MessageDeliveryStatus.processing);
    pending.touch(responseTimeout, () => _timeoutPending(pending));
  }

  void _handleAprsReject(String id) {
    final pending = _pendingByAprsMessageId[id];
    if (pending == null || pending.stored) return;

    _pendingByAprsMessageId.removeWhere((_, value) => identical(value, pending));
    pending.rejectAttempt();
    _setPendingStatus(pending, MessageDeliveryStatus.retry);
    pending.cancelTimeout();
  }

  _PendingSend? _oldestPendingStoredConfirmation() {
    for (final pending in _pendingStoredOrder) {
      if (!pending.stored &&
          pending.hasBeenTransmitted &&
          !pending.commitAckAttempt) {
        return pending;
      }
    }
    return null;
  }

  void _timeoutPending(_PendingSend pending) {
    if (_closed || pending.stored) return;
    _setPendingStatus(pending, MessageDeliveryStatus.retry);
  }

  void _setPendingStatus(_PendingSend pending, MessageDeliveryStatus status) {
    if (pending.stored && status != MessageDeliveryStatus.stored) return;
    if (pending.status == status) return;
    pending.status = status;
    final index = _messages.indexWhere((message) => message.id == pending.message.id);
    if (index >= 0) {
      _messages[index] = _messages[index].copyWith(deliveryStatus: status);
    }
    _events.add(
      MessageSendStatusChanged(messageId: pending.message.id, status: status),
    );
  }

  void _markStored(_PendingSend pending) {
    if (pending.stored) return;
    pending.stored = true;
    pending.cancelTimeout();
    _setPendingStatus(pending, MessageDeliveryStatus.stored);
    _pendingSends.remove(pending.message.id);
    _pendingStoredOrder.remove(pending);
    _pendingByAprsMessageId.removeWhere((_, value) => identical(value, pending));
    pending.clearAttempt();
  }

  void _mergeSessionMessages(Iterable<InternetMessage> incoming) {
    for (final message in incoming) {
      if (_messages.every((existing) => existing.id != message.id)) {
        _messages.add(message);
      }
    }
  }

  @override
  Future<List<InternetMessage>> messages({
    required String callsign,
    required String token,
    String? withCallsign,
  }) async {
    final peer = withCallsign?.trim().toUpperCase();
    return List<InternetMessage>.unmodifiable(
      _messages.where(
        (message) => peer == null || message.peerFor(this.callsign) == peer,
      ),
    );
  }

  @override
  Future<SyncBatch> sync({required String token, String? cursor}) {
    final active = _syncInFlight;
    if (active != null) return active;

    final future = _syncOne(cursor);
    _syncInFlight = future;
    future.then(
      (_) {
        if (identical(_syncInFlight, future)) _syncInFlight = null;
      },
      onError: (Object _, StackTrace _) {
        if (identical(_syncInFlight, future)) _syncInFlight = null;
      },
    );
    return future;
  }

  Future<SyncBatch> _syncOne(String? cursor) async {
    if (_closed || !_serverReachable) {
      throw StateError('APRS OpenQSP session is not available');
    }
    final since = cursor == null ? 0 : int.tryParse(cursor);
    if (since == null || since < 0 || since > 0xffffffff) {
      throw ArgumentError.value(cursor, 'cursor', 'Invalid APRS message cursor');
    }
    final pending = _PendingSync(since);
    _pendingSync = pending;
    pending.touch(responseTimeout);
    session.setActivity(AprsActivityState.askingForNewMessages);
    try {
      await _enqueueTx(
        () => _sendObject(OpenQspGetNewMessages(since: since, max: 8)),
      );
      return await pending.completer.future;
    } finally {
      pending.cancelTimeout();
      if (identical(_pendingSync, pending)) _pendingSync = null;
      if (!pending.completer.isCompleted &&
          (session.activityState == AprsActivityState.askingForNewMessages ||
              session.activityState == AprsActivityState.gettingNewMessages)) {
        session.setActivity(AprsActivityState.idle);
      }
    }
  }

  @override
  Future<void> markConversationRead({
    required String remoteCallsign,
    required String token,
  }) async {}

  @override
  Future<InternetMessage> send({
    required String callsign,
    required String remoteCallsign,
    required String text,
    required String token,
  }) async {
    if (_closed || !_serverReachable) {
      throw StateError('APRS OpenQSP session is not available');
    }
    final recipient = remoteCallsign.trim().toUpperCase();
    final createdAt = DateTime.now().toUtc();
    final message = InternetMessage(
      id: 'aprs-local-${createdAt.microsecondsSinceEpoch}-${_localSequence++}',
      from: this.callsign,
      to: recipient,
      body: text,
      createdAt: createdAt,
      deliveryStatus: MessageDeliveryStatus.processing,
    );
    final pending = _PendingSend(
      message: message,
      request: OpenQspSendMessage(
        createdAt: createdAt.millisecondsSinceEpoch ~/ 1000,
        recipient: recipient,
        body: text,
      ),
      transactionId: _transactionIdFactory(),
    );
    _messages.add(message);
    _pendingSends[message.id] = pending;
    _pendingStoredOrder.add(pending);
    _enqueuePendingSend(pending);
    return message;
  }

  @override
  Future<void> retryMessage(InternetMessage message) async {
    if (_closed || !_serverReachable) {
      throw StateError('APRS OpenQSP session is not available');
    }
    var pending = _pendingSends[message.id];
    if (pending == null) {
      if (!message.id.startsWith('aprs-local-') ||
          message.from.toUpperCase() != callsign) {
        throw StateError('Message is not an APRS pending send');
      }
      pending = _PendingSend(
        message: message,
        request: OpenQspSendMessage(
          createdAt: message.createdAt.millisecondsSinceEpoch ~/ 1000,
          recipient: message.to.toUpperCase(),
          body: message.body,
        ),
        transactionId: _transactionIdFactory(),
      );
      _pendingSends[message.id] = pending;
      _pendingStoredOrder.add(pending);
      final index = _messages.indexWhere((value) => value.id == message.id);
      if (index < 0) {
        _messages.add(message);
      }
    }
    if (pending.stored) return;
    _setPendingStatus(pending, MessageDeliveryStatus.processing);
    _enqueuePendingSend(pending);
  }

  void _enqueuePendingSend(_PendingSend pending) {
    if (pending.queuedOrTransmitting || pending.stored) return;
    pending.queuedOrTransmitting = true;
    unawaited(
      _enqueueTx(() => _transmitPending(pending)).then(
        (_) => pending.queuedOrTransmitting = false,
        onError: (Object _, StackTrace __) {
          pending.queuedOrTransmitting = false;
          _setPendingStatus(pending, MessageDeliveryStatus.retry);
          pending.cancelTimeout();
        },
      ),
    );
  }

  Future<void> _transmitPending(_PendingSend pending) async {
    if (!_serverReachable) {
      throw StateError('APRS OpenQSP session is not available');
    }
    final call = _tnc.sourceCallsign;
    if (call == null || !_tnc.kissReady) {
      throw StateError('TNC is not connected');
    }
    _setPendingStatus(pending, MessageDeliveryStatus.processing);
    final core = _codec.encode(pending.request);
    final fragments = fragmentFrame(core, pending.transactionId);
    final commitAck = session.supportsAprsCommitAck;
    _pendingByAprsMessageId.removeWhere((_, value) => identical(value, pending));
    pending.beginAttempt(commitAck: commitAck);
    pending.hasBeenTransmitted = true;
    for (var index = 0; index < fragments.length; index++) {
      final fragment = fragments[index];
      final messageId = _allocateAprsMessageId(commitAck: commitAck);
      _pendingByAprsMessageId[messageId] = pending;
      pending.expectAck(
        messageId,
        commit: commitAck && index == fragments.length - 1,
      );
      final information = _messageEncoder.encode(
        addressee: openQspAprsAddressee,
        body: fragment.body,
        messageId: messageId,
      );
      final ax25 = _ax25Encoder.encodeUi(
        destination: const Ax25Address(
          callsign: openQspAprsTocall,
          ssid: 0,
          hasBeenRepeated: false,
          isLast: false,
        ),
        source: Ax25Address(
          callsign: call,
          ssid: _tnc.aprsSsid,
          hasBeenRepeated: false,
          isLast: true,
        ),
        information: information,
      );
      await _tnc.sendKiss(KissFrame(port: 0, command: 0, payload: ax25));
    }
    pending.touch(responseTimeout, () => _timeoutPending(pending));
  }

  Future<T> _enqueueTx<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _txTail = _txTail.then((_) async {
      try {
        result.complete(await operation());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  String _allocateAprsMessageId({required bool commitAck}) {
    for (var attempt = 0; attempt < 36 * 36; attempt++) {
      final value = _nextAprsMessageId++ % (36 * 36);
      final base = value.toRadixString(36).toUpperCase().padLeft(2, '0');
      final candidate = commitAck ? 'C$base' : base;
      if (!_pendingByAprsMessageId.containsKey(candidate)) return candidate;
    }
    throw StateError('APRS message ID space exhausted');
  }

  Future<void> _sendObject(OpenQspFrameObject object) async {
    final call = _tnc.sourceCallsign;
    if (call == null || !_tnc.kissReady) {
      throw StateError('TNC is not connected');
    }
    final core = _codec.encode(object);
    final transactionId = _transactionIdFactory();
    final fragments = fragmentFrame(core, transactionId);
    for (final fragment in fragments) {
      final information = _messageEncoder.encode(
        addressee: openQspAprsAddressee,
        body: fragment.body,
      );
      final ax25 = _ax25Encoder.encodeUi(
        destination: const Ax25Address(
          callsign: openQspAprsTocall,
          ssid: 0,
          hasBeenRepeated: false,
          isLast: false,
        ),
        source: Ax25Address(
          callsign: call,
          ssid: _tnc.aprsSsid,
          hasBeenRepeated: false,
          isLast: true,
        ),
        information: information,
      );
      await _tnc.sendKiss(KissFrame(port: 0, command: 0, payload: ax25));
    }
  }

  InternetMessage _fromOpenQspMessage(OpenQspMessage value) => InternetMessage(
    id: _serverMessageId(value.recipient, value.sequence),
    from: value.author.toUpperCase(),
    to: value.recipient.toUpperCase(),
    body: value.body,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      value.createdAt * 1000,
      isUtc: true,
    ),
  );

  static String _serverMessageId(String recipient, int sequence) =>
      base64Url.encode(utf8.encode('$recipient:$sequence')).replaceAll('=', '');

  static String _randomTransactionId() {
    final value = Random.secure().nextInt(36 * 36 * 36);
    return value.toRadixString(36).toUpperCase().padLeft(3, '0');
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_connected) {
      session.removeListener(_onSessionChanged);
      _tnc.removeListener(_onTncChanged);
    }
    for (final pending in _pendingSends.values) {
      pending.cancelTimeout();
    }
    _pendingSends.clear();
    _pendingByAprsMessageId.clear();
    _pendingStoredOrder.clear();
    final sync = _pendingSync;
    sync?.cancelTimeout();
    if (sync != null && !sync.completer.isCompleted) {
      sync.completer.completeError(StateError('APRS messages transport closed'));
    }
    await _events.close();
    await _connections.close();
  }
}

final class _PendingSend {
  _PendingSend({
    required this.message,
    required this.request,
    required this.transactionId,
  }) : status = message.deliveryStatus;

  final InternetMessage message;
  final OpenQspSendMessage request;
  final String transactionId;
  final Set<String> _awaitingAprsAcks = <String>{};
  MessageDeliveryStatus status;
  Timer? _timeout;
  String? _commitAckMessageId;
  bool hasBeenTransmitted = false;
  bool queuedOrTransmitting = false;
  bool stored = false;
  bool commitAckAttempt = false;

  void beginAttempt({required bool commitAck}) {
    _awaitingAprsAcks.clear();
    _commitAckMessageId = null;
    commitAckAttempt = commitAck;
  }

  void expectAck(String messageId, {bool commit = false}) {
    _awaitingAprsAcks.add(messageId);
    if (commit) _commitAckMessageId = messageId;
  }

  bool isCommitAck(String messageId) => _commitAckMessageId == messageId;

  bool acknowledge(String messageId) {
    final removed = _awaitingAprsAcks.remove(messageId);
    return removed && _awaitingAprsAcks.isEmpty;
  }

  void forgetAck(String messageId) => _awaitingAprsAcks.remove(messageId);

  void rejectAttempt() {
    _awaitingAprsAcks.clear();
    _commitAckMessageId = null;
  }

  void clearAttempt() {
    _awaitingAprsAcks.clear();
    _commitAckMessageId = null;
    commitAckAttempt = false;
  }

  void touch(Duration timeout, void Function() onTimeout) {
    if (stored) return;
    _timeout?.cancel();
    _timeout = Timer(timeout, onTimeout);
  }

  void cancelTimeout() {
    _timeout?.cancel();
    _timeout = null;
  }
}

final class _PendingSync {
  _PendingSync(this._cursor);

  final List<InternetMessage> messages = [];
  final Completer<SyncBatch> completer = Completer<SyncBatch>();
  int _cursor;
  Timer? _timeout;

  String? advance(int sequence) {
    if (sequence <= _cursor) return null;
    _cursor = sequence;
    return '$sequence';
  }

  void touch(Duration timeout) {
    if (completer.isCompleted) return;
    _timeout?.cancel();
    _timeout = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('APRS OpenQSP response timed out'));
      }
    });
  }

  void cancelTimeout() {
    _timeout?.cancel();
    _timeout = null;
  }
}
