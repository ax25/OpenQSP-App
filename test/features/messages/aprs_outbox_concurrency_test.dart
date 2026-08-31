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

  Future<AprsMessagesTransport> buildTransport({
    required String Function() transactionIdFactory,
    Duration responseTimeout = const Duration(seconds: 1),
  }) async {
    final transport = AprsMessagesTransport(
      session: session,
      callsign: 'EA3GNU',
      responseTimeout: responseTimeout,
      transactionIdFactory: transactionIdFactory,
    );
    await transport.connect(callsign: 'EA3GNU', token: '');
    return transport;
  }

  Future<void> enableCommitAck() async {
    _injectObject(
      service,
      const OpenQspCapabilities(protocolVersion: 1, capabilities: 0x1f),
      transactionId: 'CAP',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(session.supportsAprsCommitAck, isTrue);
  }

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
    tnc.openQspCheckState = OpenQspCheckState.available;
    service.sentBytes.clear();
  });

  tearDown(() async {
    session.dispose();
    tnc.dispose();
    await service.bytes.close();
    await service.losses.close();
  });

  test('sync response wait does not block a following SEND_MESSAGE TX', () async {
    var sequence = 0;
    final transport = await buildTransport(
      transactionIdFactory: () => ['SYN', 'MSG'][sequence++],
    );
    addTearDown(transport.close);

    final sync = transport.sync(token: '', cursor: '0');
    await Future<void>.delayed(Duration.zero);
    expect(service.sentBytes, hasLength(1));

    final message = await transport.send(
      callsign: 'EA3GNU',
      remoteCallsign: 'EA3ABC',
      text: 'must not wait for sync',
      token: '',
    );
    expect(message.deliveryStatus, MessageDeliveryStatus.processing);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      service.sentBytes.length,
      greaterThanOrEqualTo(2),
      reason: 'SEND_MESSAGE must transmit while sync is still awaiting END',
    );

    _injectObject(
      service,
      const OpenQspEnd(
        requestOperation: OpenQspOperation.getNewMessages,
        returnedCount: 0,
        nextSince: 0,
        hasMore: false,
      ),
      transactionId: '901',
    );
    await sync;
  });

  test('two queued sends are stored only by their own commit ACK', () async {
    await enableCommitAck();
    var sequence = 0;
    final ids = ['A01', 'B01'];
    final transport = await buildTransport(
      transactionIdFactory: () => ids[sequence++],
    );
    addTearDown(transport.close);

    final statuses = <MessageSendStatusChanged>[];
    final subscription = transport.events
        .where((event) => event is MessageSendStatusChanged)
        .cast<MessageSendStatusChanged>()
        .listen(statuses.add);
    addTearDown(subscription.cancel);

    final first = await transport.send(
      callsign: 'EA3GNU',
      remoteCallsign: 'EA3ABC',
      text: 'first',
      token: '',
    );
    final second = await transport.send(
      callsign: 'EA3GNU',
      remoteCallsign: 'EA3ABC',
      text: 'second',
      token: '',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    _injectAck(service, messageId: 'C00');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final storedAfterFirst = statuses
        .where((event) => event.status == MessageDeliveryStatus.stored)
        .toList();
    expect(storedAfterFirst, hasLength(1));
    expect(storedAfterFirst.single.messageId, first.id);

    _injectAck(service, messageId: 'C00');
    await Future<void>.delayed(Duration.zero);
    final midway = await transport.messages(callsign: 'EA3GNU', token: '');
    expect(
      midway.firstWhere((message) => message.id == second.id).deliveryStatus,
      MessageDeliveryStatus.processing,
    );

    _injectAck(service, messageId: 'C01');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final stored = statuses
        .where((event) => event.status == MessageDeliveryStatus.stored)
        .map((event) => event.messageId)
        .toList();
    expect(stored, [first.id, second.id]);
  });

  test('late commit ACK after timeout still proves the message is stored', () async {
    await enableCommitAck();
    final transport = await buildTransport(
      responseTimeout: const Duration(milliseconds: 40),
      transactionIdFactory: () => 'LATE',
    );
    addTearDown(transport.close);

    final message = await transport.send(
      callsign: 'EA3GNU',
      remoteCallsign: 'EA3ABC',
      text: 'late durable ack',
      token: '',
    );
    await Future<void>.delayed(const Duration(milliseconds: 70));

    var history = await transport.messages(callsign: 'EA3GNU', token: '');
    expect(
      history.singleWhere((value) => value.id == message.id).deliveryStatus,
      MessageDeliveryStatus.retry,
    );

    // This payload is large enough to produce two Q1 fragments. A commit-mode
    // send is stored only after every fragment in the attempt has been ACKed.
    _injectAck(service, messageId: 'C00');
    _injectAck(service, messageId: 'C01');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    history = await transport.messages(callsign: 'EA3GNU', token: '');
    expect(
      history.singleWhere((value) => value.id == message.id).deliveryStatus,
      MessageDeliveryStatus.stored,
    );
  });

  test('retry reuses the same OpenQSP transaction id', () async {
    var factoryCalls = 0;
    final transport = await buildTransport(
      responseTimeout: const Duration(milliseconds: 40),
      transactionIdFactory: () {
        factoryCalls++;
        return 'FIX';
      },
    );
    addTearDown(transport.close);

    final message = await transport.send(
      callsign: 'EA3GNU',
      remoteCallsign: 'EA3ABC',
      text: 'retry same transaction',
      token: '',
    );
    await Future<void>.delayed(const Duration(milliseconds: 70));

    await transport.retryMessage(
      message.copyWith(deliveryStatus: MessageDeliveryStatus.retry),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(factoryCalls, 1);
  });

  test('a restored APRS retry can rebuild its pending send', () async {
    final transport = await buildTransport(transactionIdFactory: () => 'RST');
    addTearDown(transport.close);

    final restored = InternetMessage(
      id: 'aprs-local-restored-1',
      from: 'EA3GNU',
      to: 'EA3ABC',
      body: 'restored pending body',
      createdAt: DateTime.utc(2026, 8, 31, 12),
      deliveryStatus: MessageDeliveryStatus.retry,
    );

    await transport.retryMessage(restored);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(service.sentBytes, isNotEmpty);
    final history = await transport.messages(callsign: 'EA3GNU', token: '');
    expect(history.single.id, restored.id);
  });
}

void _injectAck(_FakeTncService service, {required String messageId}) {
  const messageEncoder = AprsMessageEncoder();
  const ax25Encoder = Ax25Encoder();
  const kissEncoder = KissEncoder();
  final information = messageEncoder.encode(
    addressee: 'EA3GNU',
    body: 'ack$messageId',
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

void _injectObject(
  _FakeTncService service,
  OpenQspFrameObject object, {
  required String transactionId,
}) {
  const codec = OpenQspCodec();
  const messageEncoder = AprsMessageEncoder();
  const ax25Encoder = Ax25Encoder();
  const kissEncoder = KissEncoder();
  final core = codec.encode(object);
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
