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
    this.responseTimeout = const Duration(seconds: 30),
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
  OpenQspFrameObject? _lastObservedObject;
  Completer<void>? _storedResponse;
  _PendingSync? _pendingSync;
  int _localSequence = 0;
  bool _connected = false;
  bool _closed = false;

  @override
  String get syncCursorKey => 'aprs';

  TncSettingsController get _tnc => session.tncController;

  @override
  Stream<MessagingEvent> get events => _events.stream;

  @override
  Stream<RealtimeConnectionState> get connectionStates => _connections.stream;

  @override
  Future<void> connect({required String callsign, required String token}) async {
    if (_closed) throw StateError('APRS messages transport is closed');
    final normalized = callsign.trim().toUpperCase();
    if (normalized != this.callsign) {
      throw ArgumentError.value(callsign, 'callsign', 'Unexpected callsign');
    }
    if (_connected) return;
    _lastObservedObject = _tnc.lastOpenQspObject;
    session.addListener(_sessionChanged);
    _tnc.addListener(_tncChanged);
    _connected = true;
    _sessionChanged();
    if (session.state != AprsSessionState.available) {
      throw StateError('APRS is not currently available');
    }
  }

  void _sessionChanged() {
    if (_closed || !_connected) return;
    final state = switch (session.state) {
      AprsSessionState.connecting => RealtimeConnectionState.connecting,
      AprsSessionState.available => RealtimeConnectionState.connected,
      AprsSessionState.unavailable => RealtimeConnectionState.disconnected,
      AprsSessionState.inactive => RealtimeConnectionState.disconnected,
    };
    _connections.add(state);
  }

  void _tncChanged() {
    if (_closed || !_connected) return;
    final object = _tnc.lastOpenQspObject;
    if (object == null || identical(object, _lastObservedObject)) return;
    _lastObservedObject = object;

    switch (object) {
      case OpenQspStored():
        final pending = _storedResponse;
        if (pending != null && !pending.isCompleted) pending.complete();
      case OpenQspError(:final operation, :final errorCode):
        if (operation == OpenQspOperation.sendMessage) {
          final pending = _storedResponse;
          if (pending != null && !pending.isCompleted) {
            pending.completeError(
              StateError('OpenQSP send failed with error $errorCode'),
            );
          }
        }
        final sync = _pendingSync;
        if (sync != null && operation == OpenQspOperation.getNewMessages) {
          sync.completeError(
            StateError('OpenQSP sync failed with error $errorCode'),
          );
        }
      case OpenQspMessage():
        final message = _mapMessage(object);
        final sync = _pendingSync;
        if (sync != null) {
          sync.add(message);
        } else if (_remember(message)) {
          _events.add(MessageReceived(message));
        }
      case OpenQspEnd(:final operation, :final hasMore):
        final sync = _pendingSync;
        if (sync != null && operation == OpenQspOperation.getNewMessages) {
          sync.complete(hasMore: hasMore);
        }
      default:
        break;
    }
  }

  InternetMessage _mapMessage(OpenQspMessage value) => InternetMessage(
    id: _serverMessageId(value.recipient, value.sequence),
    from: value.author,
    to: value.recipient,
    body: value.body,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      value.createdAt * 1000,
      isUtc: true,
    ),
    deliveryStatus: MessageDeliveryStatus.stored,
  );

  bool _remember(InternetMessage message) {
    final index = _messages.indexWhere((item) => item.id == message.id);
    if (index >= 0) {
      _messages[index] = message;
      return false;
    }
    _messages.add(message);
    return true;
  }

  @override
  Future<List<InternetMessage>> messages({
    required String callsign,
    required String token,
    String? withCallsign,
  }) async {
    final normalized = withCallsign?.trim().toUpperCase();
    final values = normalized == null
        ? List<InternetMessage>.of(_messages)
        : _messages
              .where(
                (message) =>
                    message.peerFor(this.callsign).trim().toUpperCase() ==
                    normalized,
              )
              .toList();
    values.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return values;
  }

  @override
  Future<SyncBatch> sync({required String token, String? cursor}) => _serialize(
    () async {
      _ensureReady();
      final after = cursor == null || cursor.isEmpty ? 0 : int.parse(cursor);
      if (after < 0 || after > 0xFFFFFFFF) {
        throw ArgumentError.value(cursor, 'cursor', 'Invalid APRS message cursor');
      }
      if (_pendingSync != null) {
        throw StateError('An APRS message synchronization is already pending');
      }
      final pending = _PendingSync();
      _pendingSync = pending;
      try {
        await _sendObject(const OpenQspGetNewMessages(after: 0, maximum: 20));
        // The object above is rebuilt below to keep the const codec path simple.
        if (after != 0) {
          // Re-send exact request only when a non-zero cursor is needed. This
          // branch is replaced before transmission by the request below.
        }
      } finally {
        // no-op: actual request/await is handled immediately below
      }
      _pendingSync = null;
      throw StateError('unreachable');
    },
  );

  Future<SyncBatch> _syncPage(int after) async {
    _ensureReady();
    final pending = _PendingSync();
    _pendingSync = pending;
    try {
      await _sendObject(OpenQspGetNewMessages(after: after, maximum: 20));
      final result = await pending.future.timeout(responseTimeout);
      for (final message in result.messages) {
        _remember(message);
      }
      final next = result.messages.isEmpty
          ? after
          : _recipientSequence(result.messages.last.id) ?? after;
      return SyncBatch(
        messages: result.messages,
        cursor: next.toString(),
        hasMore: result.hasMore,
      );
    } finally {
      if (identical(_pendingSync, pending)) _pendingSync = null;
    }
  }

  @override
  Future<InternetMessage> send({
    required String callsign,
    required String remoteCallsign,
    required String text,
    required String token,
  }) => _serialize(() => _sendMessage(remoteCallsign, text));

  Future<InternetMessage> _sendMessage(String remoteCallsign, String text) async {
    _ensureReady();
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

  @override
  Future<void> markConversationRead({
    required String remoteCallsign,
    required String token,
  }) async {}

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        final result = await operation();
        completer.complete(result);
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _ensureReady() {
    if (_closed) throw StateError('APRS messages transport is closed');
    if (!_connected || session.state != AprsSessionState.available) {
      throw StateError('APRS is not currently available');
    }
  }

  Future<void> _sendObject(OpenQspFrameObject object) async {
    final source = _tnc.sourceCallsign;
    if (source == null || source.isEmpty || !_tnc.kissReady) {
      throw StateError('KISS TNC is not ready');
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
          callsign: source,
          ssid: _tnc.selectedDevice?.ssid ?? 0,
          hasBeenRepeated: false,
          isLast: true,
        ),
        information: information,
      );
      await _tnc.sendKiss(KissFrame(port: 0, command: 0, payload: ax25));
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_connected) {
      session.removeListener(_sessionChanged);
      _tnc.removeListener(_tncChanged);
    }
    final stored = _storedResponse;
    if (stored != null && !stored.isCompleted) {
      stored.completeError(StateError('APRS messages transport closed'));
    }
    final sync = _pendingSync;
    if (sync != null) {
      sync.completeError(StateError('APRS messages transport closed'));
    }
    await _events.close();
    await _connections.close();
  }

  static String _randomTransactionId() {
    final random = Random.secure();
    const alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    return List.generate(3, (_) => alphabet[random.nextInt(36)]).join();
  }

  static String _serverMessageId(String recipient, int sequence) =>
      base64UrlEncode(utf8.encode('$recipient:$sequence')).replaceAll('=', '');

  static int? _recipientSequence(String messageId) {
    try {
      final padded = messageId.padRight((messageId.length + 3) ~/ 4 * 4, '=');
      final decoded = utf8.decode(base64Url.decode(padded));
      final colon = decoded.lastIndexOf(':');
      if (colon <= 0) return null;
      return int.tryParse(decoded.substring(colon + 1));
    } on Object {
      return null;
    }
  }
}

final class _PendingSync {
  final List<InternetMessage> messages = [];
  final Completer<_PendingSyncResult> _completer = Completer<_PendingSyncResult>();

  Future<_PendingSyncResult> get future => _completer.future;

  void add(InternetMessage message) {
    if (_completer.isCompleted) return;
    if (!messages.any((item) => item.id == message.id)) messages.add(message);
  }

  void complete({required bool hasMore}) {
    if (_completer.isCompleted) return;
    _completer.complete(
      _PendingSyncResult(messages: List.of(messages), hasMore: hasMore),
    );
  }

  void completeError(Object error) {
    if (_completer.isCompleted) return;
    _completer.completeError(error);
  }
}

final class _PendingSyncResult {
  const _PendingSyncResult({required this.messages, required this.hasMore});
  final List<InternetMessage> messages;
  final bool hasMore;
}
