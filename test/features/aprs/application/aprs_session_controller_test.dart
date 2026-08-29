import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/aprs/application/aprs_session_controller.dart';
import 'package:openqsp_app/features/aprs/application/tnc_settings_controller.dart';
import 'package:openqsp_app/features/aprs/data/bluetooth_tnc_service.dart';
import 'package:openqsp_app/features/aprs/data/bluetooth_tnc_storage.dart';
import 'package:openqsp_app/features/aprs/domain/tnc_device.dart';

const _device = TncDevice(id: '00:11:22:33:44:55', name: 'TNC');

final class _Storage implements BluetoothTncStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<TncDevice?> read() async => _device;

  @override
  Future<void> write(TncDevice device) async {}
}

final class _Service implements BluetoothTncService {
  final _incoming = StreamController<List<int>>.broadcast();
  final _losses = StreamController<int>.broadcast();
  int connectCalls = 0;
  int disconnectCalls = 0;
  int? _activeConnectionId;
  final List<List<int>> sentBytes = [];

  @override
  int? get activeConnectionId => _activeConnectionId;

  @override
  Stream<List<int>> get incomingBytes => _incoming.stream;

  @override
  Stream<int> get unexpectedDisconnections => _losses.stream;

  @override
  Future<List<TncDevice>> bondedDevices() async => const [_device];

  @override
  Future<void> connect(TncDevice device) async {
    connectCalls++;
    _activeConnectionId = connectCalls;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    _activeConnectionId = null;
  }

  @override
  Future<void> sendBytes(List<int> data) async {
    sentBytes.add(List<int>.from(data));
  }
}

void main() {
  late _Service service;
  late TncSettingsController tnc;
  late AprsSessionController session;

  setUp(() {
    service = _Service();
    tnc = TncSettingsController(
      storage: _Storage(),
      service: service,
      sourceCallsign: 'EA3GNU',
    );
    session = AprsSessionController(tncController: tnc);
  });

  tearDown(() {
    session.dispose();
    tnc.dispose();
  });

  test('activating APRS connects stored TNC and sends OpenQSP probe', () async {
    expect(session.active, isFalse);

    await session.activate();

    expect(session.active, isTrue);
    expect(service.connectCalls, 1);
    expect(tnc.kissReady, isTrue);
    expect(tnc.openQspCheckState, OpenQspCheckState.waiting);
    expect(service.sentBytes, hasLength(1));
    expect(session.state, AprsSessionState.connecting);
  });

  test('deactivating APRS disconnects the persistent TNC session', () async {
    await session.activate();
    expect(tnc.kissReady, isTrue);

    await session.deactivate();

    expect(session.active, isFalse);
    expect(service.disconnectCalls, 1);
    expect(tnc.kissReady, isFalse);
    expect(session.state, AprsSessionState.inactive);
  });

  test('activating without a configured TNC stays unavailable', () async {
    final emptyTnc = TncSettingsController(
      storage: _EmptyStorage(),
      service: service,
      sourceCallsign: 'EA3GNU',
    );
    final emptySession = AprsSessionController(tncController: emptyTnc);
    addTearDown(() {
      emptySession.dispose();
      emptyTnc.dispose();
    });

    await emptySession.activate();

    expect(emptySession.active, isTrue);
    expect(service.connectCalls, 0);
    expect(emptySession.state, AprsSessionState.unavailable);
  });
}

final class _EmptyStorage implements BluetoothTncStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<TncDevice?> read() async => null;

  @override
  Future<void> write(TncDevice device) async {}
}
