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
///
/// This first APRS messaging slice intentionally keeps only session-local
/// history. Durable history/reconciliation and read receipts remain Internet
/// features until their Core operations are wired over APRS.
final class AprsMessagesTransport
    implements MessagesRepository, MessagesRealtimeClient {
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
  Future<void> _sendTail = Future<void>.value();
  OpenQspFrameObject? _lastObservedObject;
  Completer<void>? _storedResponse;
  int _localSequence = 0;
  bool _connected = false;
  bool _closed = false;

  TncSettingsController get _tnc => session.tncController;

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
    _connections.add(state);
  }

  void _onTncChanged() {
    if (_closed) return;
    final object = _tnc.lastOpenQspObject;
    if (object == null || identical(object, _lastObservedObject)) return;
    _lastObservedObject = object;

    switch (object) {
      case OpenQspStored():
        final pending = _storedResponse;
        if (pending != null && !pending.isCompleted) pending.complete();
      case OpenQspError(:final requestOperation, :final detail):
        if (requestOperation == OpenQspOperation.sendMessage.code) {
          final pending = _storedResponse;
          if (pending != null && !pending.isCompleted) {
            pending.completeError(
              StateError(
                detail.isEmpty ? 'Server rejected APRS message' : detail,
              ),
            );
          }
        }
      case OpenQspMessage():
        final message = _fromOpenQspMessage(object);
        if (_messages.every((existing) => existing.id != message.id)) {
          _messages.add(message);
          _events.add(MessageReceived(message));
        }
      default:
        break;
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
  Future<SyncBatch> sync({required String token, String? cursor}) async =>
      SyncBatch(messages: List.unmodifiable(_messages), cursor: '${_messages.length}');

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
    _sendTail = _sendTail.then((_) async {
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
      from: this.callsign,
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
    final pending = _storedResponse;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('APRS messages transport closed'));
    }
    await _events.close();
    await _connections.close();
  }
}
