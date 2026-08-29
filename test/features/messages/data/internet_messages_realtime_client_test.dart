import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/messages/data/internet_messages_realtime_client.dart';
import 'package:openqsp_app/features/messages/domain/message_models.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test('uses WSS query token and parses message lifecycle events', () async {
    final channel = FakeChannel();
    Uri? connectedUri;
    final client = InternetMessagesRealtimeClient(
      baseUri: Uri.parse('https://server.example:8443'),
      connector: (uri) {
        connectedUri = uri;
        return channel;
      },
    );
    final events = <MessagingEvent>[];
    final subscription = client.events.listen(events.add);
    await client.connect(callsign: 'EA3GNU', token: 'secret token');
    expect(connectedUri?.scheme, 'wss');
    expect(connectedUri?.path, '/api/v1/ws');
    expect(connectedUri?.queryParameters['token'], 'secret token');

    channel.add(
      jsonEncode({
        'type': 'message.created',
        'data': {
          'id': 'server-id',
          'from': 'EA3GNU',
          'to': 'N0CALL',
          'body': 'Hello',
          'created_at': '2026-08-28T12:00:00Z',
          'delivery_status': 'stored',
          'delivered_at': null,
        },
      }),
    );
    channel.add(
      jsonEncode({
        'type': 'message.delivered',
        'data': {
          'id': 'server-id',
          'delivered_at': '2026-08-28T12:00:02Z',
        },
      }),
    );
    channel.add(
      jsonEncode({
        'type': 'message.read',
        'data': {
          'peer': 'N0CALL',
          'last_read_message_id': 'server-id',
        },
      }),
    );
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(3));
    expect((events[0] as MessageReceived).message.deliveryStatus,
        MessageDeliveryStatus.stored);
    expect((events[1] as MessageDelivered).messageId, 'server-id');
    expect((events[2] as MessageRead).lastReadMessageId, 'server-id');

    await subscription.cancel();
    await client.close();
  });

  test('reconnects with bounded delay after ordinary close', () async {
    final channels = [FakeChannel(), FakeChannel()];
    var connections = 0;
    final client = InternetMessagesRealtimeClient(
      baseUri: Uri.parse('http://server.example'),
      reconnectDelays: const [Duration(milliseconds: 1)],
      connector: (_) => channels[connections++],
    );
    await client.connect(callsign: 'EA3GNU', token: 'token');
    await channels.first.serverClose(1006);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(connections, 2);
    await client.close();
  });

  test('close code 4401 reports auth required and never reconnects', () async {
    final channel = FakeChannel();
    var connections = 0;
    final client = InternetMessagesRealtimeClient(
      baseUri: Uri.parse('http://server.example'),
      reconnectDelays: const [Duration(milliseconds: 1)],
      connector: (_) {
        connections++;
        return channel;
      },
    );
    final authRequired = client.connectionStates.firstWhere(
      (state) => state == RealtimeConnectionState.authenticationRequired,
    );
    await client.connect(callsign: 'EA3GNU', token: 'invalid');
    await channel.serverClose(4401);
    expect(await authRequired, RealtimeConnectionState.authenticationRequired);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(connections, 1);
    await client.close();
  });
}

class FakeChannel implements WebSocketChannel {
  final _controller = StreamController<dynamic>();
  late final FakeSink _sink = FakeSink(_controller);
  int? _closeCode;

  void add(Object value) => _controller.add(value);

  Future<void> serverClose(int code) async {
    _closeCode = code;
    await _controller.close();
  }

  @override
  int? get closeCode => _closeCode;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;
  @override
  Future<void> get ready => Future.value();
  @override
  WebSocketSink get sink => _sink;
  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSink implements WebSocketSink {
  FakeSink(this.controller);
  final StreamController<dynamic> controller;

  @override
  void add(Object? data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<dynamic> stream) async {}
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!controller.isClosed) await controller.close();
  }
  @override
  Future<void> get done => controller.done;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
