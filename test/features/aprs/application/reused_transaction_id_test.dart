import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/core/openqsp_protocol/openqsp_models.dart';
import 'package:openqsp_app/features/aprs/application/tnc_settings_controller.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_address.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_encoder.dart';
import 'package:openqsp_app/features/aprs/data/bluetooth_tnc_service.dart';
import 'package:openqsp_app/features/aprs/data/bluetooth_tnc_storage.dart';
import 'package:openqsp_app/features/aprs/domain/tnc_device.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_encoder.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_frame.dart';

void main() {
  test('same Q1 transaction ID accepts a different completed Core payload', () async {
    const device = TncDevice(id: 'tnc', name: 'TNC');
    final storage = _Storage()..value = device;
    final service = _Service();
    final controller = TncSettingsController(
      storage: storage,
      service: service,
      sourceCallsign: 'EA3GNU',
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.setAprsSsid(5);
    await controller.connect();

    service.bytes.add(_response('Q1:DUP:00/01:AUYABQEAAAAP'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.lastOpenQspObject, isA<OpenQspCapabilities>());
    expect(controller.openQspFramesRx, 1);

    // The server's bounded transaction-ID space can reuse DUP after the first
    // response has completed. This is a new STORED frame, not a retransmission.
    service.bytes.add(_response('Q1:DUP:00/01:AUQAAA'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.lastOpenQspObject, isA<OpenQspStored>());
    expect(controller.openQspFramesRx, 2);

    // An exact retry of that completed STORED response is still deduplicated.
    service.bytes.add(_response('Q1:DUP:00/01:AUQAAA'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.lastOpenQspObject, isA<OpenQspStored>());
    expect(controller.openQspFramesRx, 2);
  });
}

List<int> _response(String body) {
  final ax25 = const Ax25Encoder().encodeUi(
    destination: const Ax25Address(
      callsign: openQspAprsTocall,
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
    information: ':EA3GNU-5 :$body'.codeUnits,
  );
  return const KissEncoder().encode(
    KissFrame(port: 0, command: 0, payload: ax25),
  );
}

class _Storage implements BluetoothTncStorage {
  TncDevice? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<TncDevice?> read() async => value;

  @override
  Future<void> write(TncDevice device) async => value = device;
}

class _Service implements BluetoothTncService {
  final bytes = StreamController<List<int>>.broadcast();
  final losses = StreamController<int>.broadcast();
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
  Future<void> connect(TncDevice device) async {
    _activeConnectionId = 1;
  }

  @override
  Future<void> disconnect() async {
    _activeConnectionId = null;
  }

  @override
  Future<void> sendBytes(List<int> data) async {}
}
