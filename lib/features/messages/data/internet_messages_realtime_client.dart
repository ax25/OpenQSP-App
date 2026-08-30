import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../domain/message_models.dart';
import 'messages_transport.dart';

typedef WebSocketConnector = WebSocketChannel Function(Uri uri);

class InternetMessagesRealtimeClient implements MessagesRealtimeClient {
  InternetMessagesRealtimeClient({
    required Uri baseUri,
    WebSocketConnector? connector,
    this.reconnectDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
    ],
  }) : assert(reconnectDelays.isNotEmpty),
       _wsUri = baseUri.replace(
         scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
         path: '/api/v1/ws',
         query: null,
       ),
       _connector = connector ?? WebSocketChannel.connect;

  final Uri _wsUri;
  final WebSocketConnector _connector;
  final List<Duration> reconnectDelays;
  final _events = StreamController<MessagingEvent>.broadcast();
  final _states = StreamController<RealtimeConnectionState>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  Timer? _reconnectTimer;
  String? _token;
  int _attempt = 0;
  bool _closed = false;

  @override
  Stream<MessagingEvent> get events => _events.stream;

  @override
  Stream<RealtimeConnectionState> get connectionStates => _states.stream;

  @override
  Future<void> connect({required String callsign, required String token}) async {
    _token = token;
    _closed = false;
    _attempt = 0;
    await _open(reconnecting: false);
  }

  Future<void> _open({required bool reconnecting}) async {
    if (_closed || _token == null) return;
    _states.add(
      reconnecting
          ? RealtimeConnectionState.reconnecting
          : RealtimeConnectionState.connecting,
    );
    final uri = _wsUri.replace(queryParameters: {'token': _token!});
    try {
      final channel = _connector(uri);
      _channel = channel;
      await channel.ready;
      if (_closed) {
        await channel.sink.close();
        return;
      }
      _attempt = 0;
      _states.add(RealtimeConnectionState.connected);
      _subscription = channel.stream.listen(
        _onData,
        onError: (_) => _onDisconnected(),
        onDone: () => _onDone(channel),
        cancelOnError: true,
      );
    } on Object catch (error) {
      if (_isAuthenticationHandshakeFailure(error)) {
        _requireAuthentication();
      } else {
        _scheduleReconnect();
      }
    }
  }

  bool _isAuthenticationHandshakeFailure(Object error) {
    final description = error.toString().toLowerCase();
    final mentions403 = description.contains('403');
    final mentionsHandshakeStatus =
        description.contains('forbidden') ||
        description.contains('status code') ||
        description.contains('http status');
    return mentions403 && mentionsHandshakeStatus;
  }

  void _requireAuthentication() {
    if (_closed || _token == null) return;
    _token = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _states.add(RealtimeConnectionState.authenticationRequired);
  }

  void _onData(Object? raw) {
    if (raw is! String) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded case {
        'type': 'message.created',
        'data': final Map<String, dynamic> data,
      }) {
        _events.add(MessageReceived(InternetMessage.fromJson(data)));
        return;
      }
      if (decoded case {
        'type': 'message.delivered',
        'data': {
          'id': final String id,
          'delivered_at': final String deliveredAt,
        },
      }) {
        _events.add(
          MessageDelivered(
            messageId: id,
            deliveredAt: DateTime.parse(deliveredAt).toUtc(),
          ),
        );
        return;
      }
      if (decoded case {
        'type': 'message.read',
        'data': {
          'peer': final String peer,
          'last_read_message_id': final String lastReadMessageId,
        },
      }) {
        _events.add(
          MessageRead(
            peer: peer.toUpperCase(),
            lastReadMessageId: lastReadMessageId,
          ),
        );
      }
    } on FormatException catch (error, stackTrace) {
      _events.addError(error, stackTrace);
    }
  }

  void _onDone(WebSocketChannel channel) {
    if (channel.closeCode == 4401) {
      _requireAuthentication();
      return;
    }
    _onDisconnected();
  }

  void _onDisconnected() {
    if (_closed || _token == null) return;
    _states.add(RealtimeConnectionState.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closed || _token == null || _reconnectTimer != null) return;
    final index = _attempt < reconnectDelays.length
        ? _attempt
        : reconnectDelays.length - 1;
    final delay = reconnectDelays[index];
    _attempt++;
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      unawaited(_open(reconnecting: true));
    });
  }

  @override
  Future<void> close() async {
    _closed = true;
    _token = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _subscription?.cancel();
    await _channel?.sink.close();
    await _events.close();
    await _states.close();
  }
}
