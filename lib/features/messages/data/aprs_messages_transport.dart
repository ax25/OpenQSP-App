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
        MessagesSyncCursorNamespace {
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

  final StreamController<MessagingEvent> _events =
      StreamController<MessagingEvent>.broadcast();
  final StreamController<RealtimeConnectionState> _connections =
      StreamController<RealtimeConnectionState>.broadcast();
  final List<InternetMessage> _messages = [];
  Future<void> _operationTail = Future<void>.value();
  Future<SyncBatch>? _syncInFlight;
  OpenQspFrameObject? _lastObservedObject;
  int _lastObservedOpenQspFragments = 0;
  RealtimeConnectionState? _lastEmittedConnectionState;
  Completer<void>? _storedResponse;
  _PendingSync? _pendingSync;
  int _localSequence = 0;
  bool _connected = false;
  bool _closed = false;

  TncSettingsController get _tnc => session.tncController;

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
      _lastObservedObject = _tnc.lastOpenQspObject;
      _lastObservedOpenQspFragments = _tnc.openQspFragmentsRx;
      session.addListener(_onSessionChanged);
      _tnc.addListener(_onTncChanged);
    }
    _emitConnectionState();
    if (session.state != AprsSessionState.available) {
      throw StateError('APRS OpenQSP session is not available');
    }
  }

  void _onSessionChanged() => _emitConnectionState();

  void _emitConnectionState() {
    if (_closed) return;
    final state = switch (session.state) {
      AprsSessionState.available => RealtimeConnectionState.connected,
      AprsSessionState.connecting => RealtimeConnectionState.reconnecting,
      AprsSessionState.inactive || AprsSessionState.unavailable =>
        RealtimeConnectionState.disconnected,
    };
    if (_lastEmittedConnectionState == state) return;
    _lastEmittedConnectionState = state;
    _connections.add(state);
  }

  void _onTncChanged() {
    if (_closed) return;

    // GET_NEW_MESSAGES can legitimately take minutes over RF. Treat the
    // response timeout as an inactivity timeout and refresh it whenever a
    // valid OpenQSP Q1 fragment arrives, even before a complete Core frame can
    // be reassembled.
    final fragmentCount = _tnc.openQspFragmentsRx;
    if (fragmentCount != _lastObservedOpenQspFragments) {
      _lastObservedOpenQspFragments = fragmentCount;
      _pendingSync?.touch(responseTimeout);
    }

    final object = _tnc.lastOpenQspObject;
    if (object == null || identical(object, _lastObservedObject)) return;
    _lastObservedObject = object;

    switch (object) {
      case OpenQspStored():
        final pending = _storedResponse;
        if (pending != null && !pending.isCompleted) pending.complete();
      case OpenQspError(:final requestOperation, :final detail):
        final message = detail.isEmpty ? 'Server rejected APRS request' : detail;
        if (requestOperation == OpenQspOperation.sendMessage.code) {
          final pending = _storedResponse;
          if (pending != null && !pending.isCompleted) {
            pending.completeError(StateError(message));
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

        // During an ordered GET_NEW_MESSAGES response, emit the message even if
        // it was already known to this transport whenever it advances the sync
        // cursor. The controller persists the message first and only then the
        // cursor, making an interrupted APRS page resumable without re-sending
        // already-complete messages.
        if (isNew || progressiveCursor != null) {
          _events.add(
            MessageReceived(message, syncCursor: progressiveCursor),
          );
        }
      case OpenQspEnd(
        :final requestOperation,
        :final nextSince,
        :final hasMore,
      ):
        if (requestOperation == OpenQspOperation.getNewMessages) {
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

    final result = Completer<SyncBatch>();
    final future = result.future;
    _syncInFlight = future;
    _operationTail = _operationTail.then((_) async {
      try {
        result.complete(await _syncOne(cursor));
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
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
    if (_closed || session.state != AprsSessionState.available) {
      throw StateError('APRS OpenQSP session is not available');
    }
    final since = cursor == null ? 0 : int.tryParse(cursor);
    if (since == null || since < 0 || since > 0xffffffff) {
      throw ArgumentError.value(cursor, 'cursor', 'Invalid APRS message cursor');
    }
    final pending = _PendingSync(since);
    _pendingSync = pending;
    pending.touch(responseTimeout);
    try {
      await _sendObject(OpenQspGetNewMessages(since: since, max: 20));
      return await pending.completer.future;
    } finally {
      pending.cancelTimeout();
      if (identical(_pendingSync, pending)) _pendingSync = null;
    }
  }

  @override
  Future<void> markConversationRead({
    required String remoteCallsign,
    required String token,
  }) async {
    // Read receipts do not have an APRS Core operation yet. The controller still
    // clears its local unread badge when the conversation is opened.
  }

  @override
  Future<InternetMessage> send({
    required String callsign,
    required String remoteCallsign,
    required String text,
    required String token,
  }) {
    final result = Completer<InternetMessage>();
    _operationTail = _operationTail.then((_) async {
      try {
        result.complete(await _sendOne(remoteCallsign, text));
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<InternetMessage> _sendOne(String remoteCallsign, String text) async {
    if (_closed || session.state != AprsSessionState.available) {
      throw StateError('APRS OpenQSP session is not available');
    }
    final recipient = remoteCallsign.trim().toUpperCase();
    final createdAt = DateTime.now().toUtc();
    final request = OpenQspSendMessage(
      createdAt: createdAt.millisecondsSinceEpoch ~/ 1000,
      recipient: recipient,
      body: text,
    );

    final stored = Completer<void>();
    _storedResponse = stored;
    try {
      await _sendObject(request);
      await stored.future.timeout(responseTimeout);
    } finally {
      if (identical(_storedResponse, stored)) _storedResponse = null;
    }

    final message = InternetMessage(
      id: 'aprs-local-${createdAt.microsecondsSinceEpoch}-${_localSequence++}',
      from: callsign,
      to: recipient,
      body: text,
      createdAt: createdAt,
      deliveryStatus: MessageDeliveryStatus.stored,
    );
    _messages.add(message);
    return message;
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
    final stored = _storedResponse;
    if (stored != null && !stored.isCompleted) {
      stored.completeError(StateError('APRS messages transport closed'));
    }
    final sync = _pendingSync;
    sync?.cancelTimeout();
    if (sync != null && !sync.completer.isCompleted) {
      sync.completer.completeError(StateError('APRS messages transport closed'));
    }
    await _events.close();
    await _connections.close();
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
        completer.completeError(
          TimeoutException('APRS message sync inactive', timeout),
        );
      }
    });
  }

  void cancelTimeout() {
    _timeout?.cancel();
    _timeout = null;
  }
}
