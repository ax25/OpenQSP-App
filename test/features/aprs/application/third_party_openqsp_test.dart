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

const _device = TncDevice(id: 'tnc', name: 'Test TNC');

final class _Storage implements BluetoothTncStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<TncDevice?> read() async => _device;

  @override
  Future<void> write(TncDevice device) async {}
}

final class _Service implements BluetoothTncService {
  final input = StreamController<List<int>>.broadcast();
  final losses = StreamController<int>.broadcast();
  final sent = <List<int>>[];
  int? _activeConnectionId;

  @override
  int? get activeConnectionId => _activeConnectionId;

  @override
  Stream<List<int>> get incomingBytes => input.stream;

  @override
  Stream<int> get unexpectedDisconnections => losses.stream;

  @override
  Future<List<TncDevice>> bondedDevices() async => const [_device];

  @override
  Future<void> connect(TncDevice device) async {
    _activeConnectionId = 1;
  }

  @override
  Future<void> disconnect() async {
    _activeConnectionId = null;
  }

  @override
  Future<void> sendBytes(List<int> data) async {
    sent.add(List<int>.of(data));
  }
}

void main() {
  test('IGate third-party CAPABILITIES is decoded without legacy APRS ACK', () async {
    final service = _Service();
    final controller = TncSettingsController(
      storage: _Storage(),
      service: service,
      sourceCallsign: 'EA3GNU',
    );
    addTearDown(controller.dispose);
    addTearDown(service.input.close);
    addTearDown(service.losses.close);

    await controller.initialize();
    await controller.setAprsSsid(5);
    await controller.connect();
    await controller.checkOpenQsp();
    expect(service.sent, hasLength(1));

    final outerAx25 = const Ax25Encoder().encodeUi(
      destination: const Ax25Address(
        callsign: 'APRS',
        ssid: 0,
        hasBeenRepeated: false,
        isLast: false,
      ),
      source: const Ax25Address(
        callsign: 'OQSPK',
        ssid: 1,
        hasBeenRepeated: false,
        isLast: true,
      ),
      information:
          '}OQSP>APOQSP,TCPIP*,qAC,OQSPK-1::EA3GNU-5 :Q1:ABC:00/01:AUYABQEAAAAP{00'
              .codeUnits,
    );
    service.input.add(
      const KissEncoder().encode(
        KissFrame(port: 0, command: 0, payload: outerAx25),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.openQspCheckState, OpenQspCheckState.available);
    final capabilities = controller.lastOpenQspObject as OpenQspCapabilities;
    expect(capabilities.protocolVersion, 1);
    expect(capabilities.capabilities, 0x0000000f);

    expect(service.sent, hasLength(1)); // probe only; burst shim owns Q1A/Q1N
  });
}
