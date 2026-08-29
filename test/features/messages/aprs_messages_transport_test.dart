import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/core/openqsp_protocol/openqsp_codec.dart';
import 'package:openqsp_app/core/openqsp_protocol/openqsp_models.dart';
import 'package:openqsp_app/core/openqsp_protocol/openqsp_operation.dart';
import 'package:openqsp_app/features/aprs/aprs/aprs_message_encoder.dart';
import 'package:openqsp_app/features/aprs/application/aprs_session_controller.dart';
import 'package:openqsp_app/features/aprs/application/tnc_settings_controller.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_address.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_encoder.dart';
import 'package:openqsp_app/features/aprs/data/bluetooth_tnc_service.dart';
import 'package:openqsp_app/features/aprs/data/bluetooth_tnc_storage.dart';
import 'package:openqsp_app/features/aprs/domain/tnc_device.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_encoder.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_frame.dart';
import 'package:openqsp_app/features/aprs/openqsp_carriage/openqsp_aprs_carriage.dart';
import 'package:openqsp_app/features/messages/data/aprs_messages_transport.dart';
import 'package:openqsp_app/features/messages/domain/message_models.dart';

class _MemoryStorage implements BluetoothTncStorage {
  _MemoryStorage(this.value);
  TncDevice? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<TncDevice?> read() async => value;

  @override
  Future<void> write(TncDevice device) async => value = device;
}

class _FakeTncService implements BluetoothTncService {
  final bytes = StreamController<List<int>>.broadcast();
  final losses = StreamController<int>.broadcast();
  final List<List<int>> sentBytes = [];
  int? _activeConnectionId;

  @override
  int? get activeConnectionId => _activeConnectionId;

  @override
  Stream<List<int>> get incomingBytes => bytes.stream;

  @override
  Stream<int> get unexpectedDisconnections => losses.stream;

  @override
  Future<List<TncDevice>> bondedDevices() async => const [];

  @override
  Future<void> connect(TncDevice device) async => _activeConnectionId = 1;

  @override
  Future<void> disconnect() async => _activeConnectionId = null;

  @override
  Future<void> sendBytes(List<int> data) async => sentBytes.add(List.of(data));
}

void main() {
  const device = TncDevice(id: '00:11:22:33:44:55', name: 'TNC');
  late _FakeTncService service;
  late TncSettingsController tnc;
  late AprsSessionController session;
  late AprsMessagesTransport transport;

  setUp(() async {
    service = _FakeTncService();
    tnc = TncSettingsController(
      storage: _MemoryStorage(device),
      service: service,
      sourceCallsign: 'EA3GNU',
    );
    await tnc.initialize();
    await tnc.connect();
    tnc.openQspCheckState = OpenQspCheckState.available;
    session = AprsSessionController(tncController: tnc);
    await session.activate();
    // activate() starts a capabilities probe; tests only need the operational
    // state and inject their own logical responses below.
    tnc.openQspCheckState = OpenQspCheckState.available;
    transport = AprsMessagesTransport(
      session: session,
      callsign: 'EA3GNU',
      responseTimeout: const Duration(seconds: 1),
      transactionIdFactory: () => 'ABC',
    );
    await transport.connect(callsign: 'EA3GNU', token: '');
    service.sentBytes.clear();
  });

  tearDown(() async {
    await transport.close();
    session.dispose();
    tnc.dispose();
    await service.bytes.close();
    await service.losses.close();
  });

  test('send waits for STORED and writes an OpenQSP APRS request', () async {
    final pending = transport.send(
      callsign: 'EA3GNU',
      remoteCallsign: 'EA3ABC',
      text: 'hola por radio',
      token: '',
    );
    await Future<void>.delayed(Duration.zero);

    expect(service.sentBytes, isNotEmpty);
    _injectObject(service, const OpenQspStored(), transactionId: '001');

    final message = await pending;
    expect(message.from, 'EA3GNU');
    expect(message.to, 'EA3ABC');
    expect(message.body, 'hola por radio');
    expect(message.deliveryStatus, MessageDeliveryStatus.stored);
  });

  test('unsolicited MESSAGE becomes a realtime received event', () async {
    final event = transport.events
        .where((value) => value is MessageReceived)
        .cast<MessageReceived>()
        .first;
    _injectObject(
      service,
      const OpenQspMessage(
        sequence: 7,
        createdAt: 1700000000,
        author: 'EA3ABC',
        recipient: 'EA3GNU',
        body: 'mensaje recibido',
      ),
      transactionId: '002',
      unsolicited: true,
    );

    final received = await event;
    expect(received.message.from, 'EA3ABC');
    expect(received.message.to, 'EA3GNU');
    expect(received.message.body, 'mensaje recibido');
    expect(received.syncCursor, isNull);
  });

  test('sync collects GET_NEW_MESSAGES page until END', () async {
    final event = transport.events
        .where((value) => value is MessageReceived)
        .cast<MessageReceived>()
        .first;
    final pending = transport.sync(token: '', cursor: '6');
    await Future<void>.delayed(Duration.zero);
    expect(service.sentBytes, isNotEmpty);

    _injectObject(
      service,
      const OpenQspMessage(
        sequence: 7,
        createdAt: 1700000000,
        author: 'EA3ABC',
        recipient: 'EA3GNU',
        body: 'new seven',
      ),
      transactionId: '010',
    );
    _injectObject(
      service,
      const OpenQspEnd(
        requestOperation: OpenQspOperation.getNewMessages,
        returnedCount: 1,
        nextSince: 7,
        hasMore: false,
      ),
      transactionId: '011',
    );

    final received = await event;
    expect(received.syncCursor, '7');
    final batch = await pending;
    expect(batch.cursor, '7');
    expect(batch.hasMore, isFalse);
    expect(batch.messages.single.body, 'new seven');
  });

  test('complete messages advance cursor even if sync times out before END', () async {
    final received = transport.events
        .where((value) => value is MessageReceived)
        .cast<MessageReceived>()
        .take(2)
        .toList();
    final pending = transport.sync(token: '', cursor: '0');
    await Future<void>.delayed(Duration.zero);

    _injectObject(
      service,
      const OpenQspMessage(
        sequence: 1,
        createdAt: 1700000000,
        author: 'EA3ABC',
        recipient: 'EA3GNU',
        body: 'first complete message',
      ),
      transactionId: '020',
    );
    _injectObject(
      service,
      const OpenQspMessage(
        sequence: 2,
        createdAt: 1700000001,
        author: 'EA3ABC',
        recipient: 'EA3GNU',
        body: 'second complete message',
      ),
      transactionId: '021',
    );

    final events = await received;
    expect(events.map((event) => event.message.body), [
      'first complete message',
      'second complete message',
    ]);
    expect(events.map((event) => event.syncCursor), ['1', '2']);

    final history = await transport.messages(callsign: 'EA3GNU', token: '');
    expect(history.map((message) => message.body), [
      'first complete message',
      'second complete message',
    ]);
    await expectLater(pending, throwsA(isA<TimeoutException>()));
  });

  test('sync inactivity timeout is refreshed by incoming Q1 traffic', () async {
    final slowTransport = AprsMessagesTransport(
      session: session,
      callsign: 'EA3GNU',
      responseTimeout: const Duration(milliseconds: 80),
      transactionIdFactory: () => 'DEF',
    );
    await slowTransport.connect(callsign: 'EA3GNU', token: '');
    addTearDown(slowTransport.close);

    final pending = slowTransport.sync(token: '', cursor: '0');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _injectObject(
      service,
      const OpenQspMessage(
        sequence: 1,
        createdAt: 1700000000,
        author: 'EA3ABC',
        recipient: 'EA3GNU',
        body: 'keeps sync alive',
      ),
      transactionId: '030',
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _injectObject(
      service,
      const OpenQspEnd(
        requestOperation: OpenQspOperation.getNewMessages,
        returnedCount: 1,
        nextSince: 1,
        hasMore: false,
      ),
      transactionId: '031',
    );

    final batch = await pending;
    expect(batch.cursor, '1');
  });

  test('simultaneous sync calls share one APRS request', () async {
    final first = transport.sync(token: '', cursor: '6');
    final second = transport.sync(token: '', cursor: '6');
    await Future<void>.delayed(Duration.zero);

    expect(identical(first, second), isTrue);
    expect(service.sentBytes, hasLength(1));

    _injectObject(
      service,
      const OpenQspEnd(
        requestOperation: OpenQspOperation.getNewMessages,
        returnedCount: 0,
        nextSince: 6,
        hasMore: false,
      ),
      transactionId: '040',
    );

    await first;
    await second;
  });

  test('connection state is emitted only when APRS state changes', () async {
    final extraTransport = AprsMessagesTransport(
      session: session,
      callsign: 'EA3GNU',
      responseTimeout: const Duration(seconds: 1),
      transactionIdFactory: () => 'GHI',
    );
    final states = <RealtimeConnectionState>[];
    final subscription = extraTransport.connectionStates.listen(states.add);
    addTearDown(subscription.cancel);
    addTearDown(extraTransport.close);

    await extraTransport.connect(callsign: 'EA3GNU', token: '');
    await Future<void>.delayed(Duration.zero);
    expect(states, [RealtimeConnectionState.connected]);

    await tnc.setAprsSsid(0);
    await tnc.setAprsSsid(0);
    await tnc.setAprsSsid(0);
    await Future<void>.delayed(Duration.zero);

    expect(states, [RealtimeConnectionState.connected]);
  });
}

void _injectObject(
  _FakeTncService service,
  OpenQspFrameObject object, {
  required String transactionId,
  bool unsolicited = false,
}) {
  const codec = OpenQspCodec();
  const messageEncoder = AprsMessageEncoder();
  const ax25Encoder = Ax25Encoder();
  const kissEncoder = KissEncoder();
  final core = codec.encode(object, unsolicited: unsolicited);
  final fragments = fragmentFrame(core, transactionId);

  for (var index = 0; index < fragments.length; index++) {
    final fragment = fragments[index];
    final information = messageEncoder.encode(
      addressee: 'EA3GNU',
      body: fragment.body,
      messageId: index.toRadixString(36).toUpperCase().padLeft(2, '0'),
    );
    final ax25 = ax25Encoder.encodeUi(
      destination: const Ax25Address(
        callsign: 'APOQSP',
        ssid: 0,
        hasBeenRepeated: false,
        isLast: false,
      ),
      source: const Ax25Address(
        callsign: 'OQSP',
        ssid: 0,
        hasBeenRepeated: false,
        isLast: true,
      ),
      information: information,
    );
    service.bytes.add(
      kissEncoder.encode(KissFrame(port: 0, command: 0, payload: ax25)),
    );
  }
}
