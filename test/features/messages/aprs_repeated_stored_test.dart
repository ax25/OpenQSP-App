import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/core/openqsp_protocol/openqsp_codec.dart';
import 'package:openqsp_app/core/openqsp_protocol/openqsp_models.dart';
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

  test('two consecutive STORED frames complete two consecutive sends', () async {
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

    var tx = 0;
    final transport = AprsMessagesTransport(
      session: session,
      callsign: 'EA3GNU',
      responseTimeout: const Duration(seconds: 1),
      transactionIdFactory: () => 'C${tx++}'.padLeft(3, '0'),
    );
    await transport.connect(callsign: 'EA3GNU', token: '');
    service.sentBytes.clear();

    final first = transport.send(
      callsign: 'EA3GNU',
      remoteCallsign: 'EA3EFG',
      text: 'first',
      token: '',
    );
    await Future<void>.delayed(Duration.zero);
    _injectStored(service, transactionId: '101');
    expect((await first).body, 'first');

    final firstFrameCount = tnc.openQspFramesRx;
    final second = transport.send(
      callsign: 'EA3GNU',
      remoteCallsign: 'EA3EFG',
      text: 'second',
      token: '',
    );
    await Future<void>.delayed(Duration.zero);
    _injectStored(service, transactionId: '102');
    expect((await second).body, 'second');
    expect(tnc.openQspFramesRx, firstFrameCount + 1);

    await transport.close();
    session.dispose();
    tnc.dispose();
    await service.bytes.close();
    await service.losses.close();
  });
}

void _injectStored(_FakeTncService service, {required String transactionId}) {
  const codec = OpenQspCodec();
  const messageEncoder = AprsMessageEncoder();
  const ax25Encoder = Ax25Encoder();
  const kissEncoder = KissEncoder();

  final core = codec.encode(const OpenQspStored());
  final fragment = fragmentFrame(core, transactionId).single;
  final information = messageEncoder.encode(
    addressee: 'EA3GNU',
    body: fragment.body,
    messageId: transactionId.substring(1),
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
