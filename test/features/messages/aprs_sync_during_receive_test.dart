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

class _MemoryStorage implements BluetoothTncStorage {
  _MemoryStorage(this.device);
  TncDevice? device;

  @override
  Future<void> clear() async => device = null;

  @override
  Future<TncDevice?> read() async => device;

  @override
  Future<void> write(TncDevice value) async => device = value;
}

class _FakeTncService implements BluetoothTncService {
  final bytes = StreamController<List<int>>.broadcast();
  final losses = StreamController<int>.broadcast();
  final List<List<int>> sentBytes = [];
  int? _connectionId;

  @override
  int? get activeConnectionId => _connectionId;

  @override
  Stream<List<int>> get incomingBytes => bytes.stream;

  @override
  Stream<int> get unexpectedDisconnections => losses.stream;

  @override
  Future<List<TncDevice>> bondedDevices() async => const [];

  @override
  Future<void> connect(TncDevice device) async => _connectionId = 1;

  @override
  Future<void> disconnect() async => _connectionId = null;

  @override
  Future<void> sendBytes(List<int> data) async => sentBytes.add(List.of(data));
}

void main() {
  test('GET_NEW_MESSAGES is allowed while APRS receive indicator is active', () async {
    const device = TncDevice(id: '00:11:22:33:44:55', name: 'TNC');
    final service = _FakeTncService();
    final tnc = TncSettingsController(
      storage: _MemoryStorage(device),
      service: service,
      sourceCallsign: 'EA3GNU',
    );
    await tnc.initialize();
    await tnc.connect();
    tnc.openQspCheckState = OpenQspCheckState.available;

    final session = AprsSessionController(
      tncController: tnc,
      receiveIndicatorDelay: const Duration(milliseconds: 1),
    );
    await session.activate();
    tnc.openQspCheckState = OpenQspCheckState.available;
    service.sentBytes.clear();

    const codec = OpenQspCodec();
    const messageEncoder = AprsMessageEncoder();
    const ax25Encoder = Ax25Encoder();
    const kissEncoder = KissEncoder();
    final core = codec.encode(
      OpenQspMessage(
        sequence: 13,
        createdAt: 1788300000,
        author: 'EA3ABC',
        recipient: 'EA3GNU',
        body: List.filled(180, 'x').join(),
      ),
    );
    final fragments = fragmentFrame(core, 'RX1');
    expect(fragments.length, greaterThan(1));

    void receive(OpenQspAprsFragment fragment) {
      final information = messageEncoder.encode(
        addressee: 'EA3GNU',
        body: fragment.body,
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

    receive(fragments.first);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    expect(session.messageReceiveState, AprsMessageReceiveState.receiving);

    final transport = AprsMessagesTransport(
      session: session,
      callsign: 'EA3GNU',
      transactionIdFactory: () => 'GET',
    );
    await transport.connect(callsign: 'EA3GNU', token: '');
    service.sentBytes.clear();

    final sync = transport.sync(token: '', cursor: '12');
    await Future<void>.delayed(Duration.zero);
    expect(service.sentBytes, isNotEmpty);

    final end = codec.encode(
      const OpenQspEnd(
        requestOperation: OpenQspOperation.getNewMessages,
        returnedCount: 0,
        nextSince: 12,
        hasMore: false,
      ),
    );
    for (final fragment in fragmentFrame(end, 'END')) {
      receive(fragment);
    }
    final batch = await sync;

    expect(batch.messages, isEmpty);
    expect(batch.cursor, '12');
    expect(batch.hasMore, isFalse);
    expect(session.messageReceiveState, AprsMessageReceiveState.hidden);

    await transport.close();
    session.dispose();
    tnc.dispose();
    await service.bytes.close();
    await service.losses.close();
  });
}
