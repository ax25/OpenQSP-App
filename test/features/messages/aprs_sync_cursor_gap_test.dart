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
  test('APRS sync does not advance cursor across a missing whole message', () async {
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

    final session = AprsSessionController(tncController: tnc);
    await session.activate();
    tnc.openQspCheckState = OpenQspCheckState.available;

    const codec = OpenQspCodec();
    const messageEncoder = AprsMessageEncoder();
    const ax25Encoder = Ax25Encoder();
    const kissEncoder = KissEncoder();

    void receiveObject(OpenQspFrameObject object, String transactionId) {
      final core = codec.encode(object);
      for (final fragment in fragmentFrame(core, transactionId)) {
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
    }

    OpenQspMessage message(int sequence) => OpenQspMessage(
      sequence: sequence,
      createdAt: 1788400000 + sequence,
      author: 'EA3ABC',
      recipient: 'EA3GNU',
      body: 'message $sequence',
    );

    final transport = AprsMessagesTransport(
      session: session,
      callsign: 'EA3GNU',
      transactionIdFactory: () => 'GET',
    );
    await transport.connect(callsign: 'EA3GNU', token: '');
    service.sentBytes.clear();

    final firstSync = transport.sync(token: '', cursor: '10');
    await Future<void>.delayed(Duration.zero);

    // Sequence 11 is completely lost over RF. Later messages still arrive.
    receiveObject(message(12), 'M12');
    receiveObject(message(13), 'M13');
    receiveObject(message(14), 'M14');
    receiveObject(
      const OpenQspEnd(
        requestOperation: OpenQspOperation.getNewMessages,
        returnedCount: 4,
        nextSince: 14,
        hasMore: false,
      ),
      'END1',
    );

    final firstBatch = await firstSync;
    expect(firstBatch.messages, hasLength(3));
    expect(firstBatch.cursor, '10');
    expect(firstBatch.hasMore, isTrue);

    // A retry from the preserved cursor can now recover the missing message.
    await Future<void>.delayed(Duration.zero);
    final secondSync = transport.sync(token: '', cursor: firstBatch.cursor);
    await Future<void>.delayed(Duration.zero);

    receiveObject(message(11), 'M11');
    receiveObject(message(12), 'R12');
    receiveObject(message(13), 'R13');
    receiveObject(message(14), 'R14');
    receiveObject(
      const OpenQspEnd(
        requestOperation: OpenQspOperation.getNewMessages,
        returnedCount: 4,
        nextSince: 14,
        hasMore: false,
      ),
      'END2',
    );

    final secondBatch = await secondSync;
    expect(secondBatch.cursor, '14');
    expect(secondBatch.hasMore, isFalse);

    await transport.close();
    session.dispose();
    tnc.dispose();
    await service.bytes.close();
    await service.losses.close();
  });
}
