import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/core/openqsp_protocol/openqsp_codec.dart';
import 'package:openqsp_app/core/openqsp_protocol/openqsp_models.dart';
import 'package:openqsp_app/features/aprs/aprs/aprs_message_encoder.dart';
import 'package:openqsp_app/features/aprs/application/tnc_settings_controller.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_address.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_encoder.dart';
import 'package:openqsp_app/features/aprs/data/bluetooth_tnc_service.dart';
import 'package:openqsp_app/features/aprs/data/bluetooth_tnc_storage.dart';
import 'package:openqsp_app/features/aprs/domain/tnc_device.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_encoder.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_frame.dart';
import 'package:openqsp_app/features/aprs/openqsp_carriage/openqsp_aprs_carriage.dart';

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
  test('ACKs an older OpenQSP fragment after receiving a later one', () async {
    const device = TncDevice(id: '00:11:22:33:44:55', name: 'TNC');
    final service = _FakeTncService();
    final controller = TncSettingsController(
      storage: _MemoryStorage(device),
      service: service,
      sourceCallsign: 'EA3GNU',
    );

    await controller.initialize();
    await controller.connect();
    service.sentBytes.clear();

    addTearDown(() async {
      controller.dispose();
      await service.bytes.close();
      await service.losses.close();
    });

    const codec = OpenQspCodec();
    final core = codec.encode(
      const OpenQspMessage(
        sequence: 13,
        createdAt: 1788210000,
        author: 'EA3SIL',
        recipient: 'EA3GNU',
        body:
            'Long enough OpenQSP message to ensure that this response spans '
            'multiple APRS fragments for burst ACK testing.',
      ),
    );
    final fragments = fragmentFrame(core, 'ACK');
    expect(fragments.length, greaterThanOrEqualTo(2));

    _injectFragment(service, fragments[0], messageId: '10');
    await _settle();
    expect(service.sentBytes, hasLength(1));

    _injectFragment(service, fragments[1], messageId: '11');
    await _settle();
    expect(service.sentBytes, hasLength(2));

    // Burst/out-of-order delivery means seeing fragment 2 does not prove the
    // server received ACK 10. A delayed copy of fragment 1 must still be ACKed.
    _injectFragment(service, fragments[0], messageId: '10');
    await _settle();
    expect(service.sentBytes, hasLength(3));

    // Repetitions of the latest fragment must also continue to be ACKed.
    _injectFragment(service, fragments[1], messageId: '11');
    await _settle();
    expect(service.sentBytes, hasLength(4));
  });
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void _injectFragment(
  _FakeTncService service,
  OpenQspAprsFragment fragment, {
  required String messageId,
}) {
  const messageEncoder = AprsMessageEncoder();
  const ax25Encoder = Ax25Encoder();
  const kissEncoder = KissEncoder();

  final information = messageEncoder.encode(
    addressee: 'EA3GNU',
    body: fragment.body,
    messageId: messageId,
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
