import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/core/openqsp_protocol/openqsp_models.dart';
import 'package:openqsp_app/features/aprs/application/tnc_settings_controller.dart';
import 'package:openqsp_app/features/aprs/aprs/aprs_packet.dart';
import 'package:openqsp_app/features/aprs/aprs/aprs_parser.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_address.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_decoder.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_encoder.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_decoder.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_encoder.dart';
import 'package:openqsp_app/features/aprs/data/bluetooth_tnc_service.dart';
import 'package:openqsp_app/features/aprs/data/bluetooth_tnc_storage.dart';
import 'package:openqsp_app/features/aprs/domain/tnc_connection_state.dart';
import 'package:openqsp_app/features/aprs/domain/tnc_device.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_frame.dart';

class MemoryTncStorage implements BluetoothTncStorage {
  TncDevice? value;
  @override
  Future<void> clear() async => value = null;
  @override
  Future<TncDevice?> read() async => value;
  @override
  Future<void> write(TncDevice device) async => value = device;
}

class FakeTncService implements BluetoothTncService {
  final bytes = StreamController<List<int>>.broadcast();
  final losses = StreamController<int>.broadcast();
  Object? error;
  bool connected = false;
  List<TncDevice> devices = const [];
  Future<void>? disconnectPending;
  int disconnectCalls = 0;
  int? _activeConnectionId;
  int nextConnectionId = 1;
  Object? sendError;
  final List<List<int>> sentBytes = [];

  @override
  int? get activeConnectionId => _activeConnectionId;

  @override
  Stream<List<int>> get incomingBytes => bytes.stream;

  @override
  Stream<int> get unexpectedDisconnections => losses.stream;

  @override
  Future<List<TncDevice>> bondedDevices() async {
    if (error case final Object value) throw value;
    return devices;
  }

  @override
  Future<void> connect(TncDevice device) async {
    if (error case final Object value) throw value;
    connected = true;
    _activeConnectionId = nextConnectionId++;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    connected = false;
    _activeConnectionId = null;
    final pending = disconnectPending;
    if (pending != null) await pending;
  }

  @override
  Future<void> sendBytes(List<int> data) async {
    if (sendError case final Object value) throw value;
    sentBytes.add(List.of(data));
  }
}

void main() {
  const device = TncDevice(id: '00:11:22:33:44:55', name: 'Mobilinkd TNC4');
  late MemoryTncStorage storage;
  late FakeTncService service;
  late TncSettingsController controller;

  setUp(() {
    storage = MemoryTncStorage();
    service = FakeTncService();
    controller = TncSettingsController(
      storage: storage,
      service: service,
      sourceCallsign: 'EA3GNU',
    );
  });

  test('without a stored TNC initializes as not configured', () async {
    await controller.initialize();
    expect(controller.state, TncConnectionState.notConfigured);
    expect(controller.device, isNull);
  });

  test('selecting a TNC persists it', () async {
    await controller.initialize();
    await controller.select(device);
    expect(storage.value, device);
    expect(controller.state, TncConnectionState.configured);
  });

  test('a new controller restores the persisted TNC as configured', () async {
    storage.value = device;
    final restored = TncSettingsController(storage: storage, service: service);
    await restored.initialize();
    expect(restored.device, device);
    expect(restored.state, TncConnectionState.configured);
  });

  test('forgetting clears persistence and configuration', () async {
    storage.value = device;
    await controller.initialize();
    await controller.forget();
    expect(storage.value, isNull);
    expect(controller.device, isNull);
    expect(controller.state, TncConnectionState.notConfigured);
  });

  test('a successful fake connection is reflected and can disconnect', () async {
    storage.value = device;
    await controller.initialize();
    await controller.connect();
    expect(controller.state, TncConnectionState.connected);
    expect(service.connected, isTrue);
    await controller.disconnect();
    expect(controller.state, TncConnectionState.configured);
  });

  test('a connection failure becomes controlled error state', () async {
    storage.value = device;
    service.error = const TncServiceException(TncFailure.connectionFailed);
    await controller.initialize();
    await controller.connect();
    expect(controller.state, TncConnectionState.error);
    expect(controller.failure, TncFailure.connectionFailed);
  });

  test('unexpected loss of the active connection becomes an error', () async {
    storage.value = device;
    await controller.initialize();
    await controller.connect();

    service.losses.add(service.activeConnectionId!);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state, TncConnectionState.error);
    expect(controller.failure, TncFailure.connectionFailed);
  });

  test('voluntary disconnect does not report a connection error', () async {
    storage.value = device;
    await controller.initialize();
    await controller.connect();
    final oldConnection = service.activeConnectionId!;

    await controller.disconnect();
    service.losses.add(oldConnection);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state, TncConnectionState.configured);
    expect(controller.failure, isNull);
  });

  test('late loss from an old connection cannot affect a reconnection', () async {
    storage.value = device;
    await controller.initialize();
    await controller.connect();
    final oldConnection = service.activeConnectionId!;
    await controller.disconnect();
    await controller.connect();

    service.losses.add(oldConnection);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state, TncConnectionState.connected);
    expect(controller.failure, isNull);
    expect(service.activeConnectionId, isNot(oldConnection));
  });

  test('active write failure is propagated and its loss updates state', () async {
    storage.value = device;
    await controller.initialize();
    await controller.connect();
    final connectionId = service.activeConnectionId!;
    service.sendError = const TncServiceException(TncFailure.connectionFailed);

    await expectLater(
      controller.sendKiss(KissFrame(port: 0, command: 0, payload: [1])),
      throwsA(isA<TncServiceException>()),
    );
    service.losses.add(connectionId);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state, TncConnectionState.error);
    expect(controller.failure, TncFailure.connectionFailed);
  });

  test('late write loss from an old connection is ignored after reconnect', () async {
    storage.value = device;
    await controller.initialize();
    await controller.connect();
    final oldConnection = service.activeConnectionId!;
    await controller.disconnect();
    await controller.connect();

    service.losses.add(oldConnection);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state, TncConnectionState.connected);
    expect(controller.failure, isNull);
  });

  test('permission denial while listing is controlled and retryable', () async {
    service.error = const TncServiceException(TncFailure.permissionDenied);
    await controller.initialize();
    expect(await controller.loadDevices(), isNull);
    expect(controller.state, TncConnectionState.error);
    expect(controller.failure, TncFailure.permissionDenied);
  });

  test('only KISS port-zero data frames are decoded as AX.25', () async {
    final ax25 = [
      ...'APN382'.codeUnits.map((value) => value << 1),
      0x60,
      ...'EA3GNU'.codeUnits.map((value) => value << 1),
      0x61,
      0x03,
      0xf0,
      0x41,
    ];
    service.bytes.add([0xc0, 0x00, ...ax25, 0xc0]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.rxKissFrames, 1);
    expect(controller.rxAx25Frames, 1);
    expect(controller.ax25DecodeErrors, 0);
    expect(controller.ax25Activity.single, contains('SRC: EA3GNU'));

    service.bytes.add([0xc0, 0x01, 1, 2, 3, 0xc0]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.rxKissFrames, 2);
    expect(controller.rxAx25Frames, 1);
    expect(controller.ax25DecodeErrors, 0);
  });

  test('bad AX.25 data is counted and later frames continue', () async {
    service.bytes.add([0xc0, 0x00, 1, 2, 3, 0xc0]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.ax25DecodeErrors, 1);
    expect(controller.state, isNot(TncConnectionState.error));
  });

  test('malformed APRS is isolated and a following message is decoded', () async {
    List<int> kissData(String information) {
      final ax25 = [
        ...'APN382'.codeUnits.map((value) => value << 1),
        0x60,
        ...'EA3GNU'.codeUnits.map((value) => value << 1),
        0x61,
        0x03,
        0xf0,
        ...information.codeUnits,
      ];
      return [0xc0, 0x00, ...ax25, 0xc0];
    }

    service.bytes.add(kissData(':OQSP     :ack'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.rxAx25Frames, 1);
    expect(controller.ax25DecodeErrors, 0);
    expect(controller.rxAprsPackets, 1);
    expect(controller.aprsParseErrors, 1);

    service.bytes.add(kissData(':OQSP     :HELLO{12'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.rxAx25Frames, 2);
    expect(controller.aprsMessages, 1);
    expect(controller.openQspRxPackets, 0);
    expect(controller.aprsActivity.single, contains('TEXT: HELLO'));
  });

  List<int> response({
    required String source,
    String body = 'Q1:ABC:00/01:A U',
  }) {
    final information = ':EA3GNU-5 :$body'.codeUnits;
    final ax25 = const Ax25Encoder().encodeUi(
      destination: const Ax25Address(
        callsign: openQspAprsTocall,
        ssid: 0,
        hasBeenRepeated: false,
        isLast: false,
      ),
      source: Ax25Address(
        callsign: source,
        ssid: 0,
        hasBeenRepeated: false,
        isLast: true,
      ),
      information: information,
    );
    return const KissEncoder().encode(
      KissFrame(port: 0, command: 0, payload: ax25),
    );
  }

  test('CAPABILITIES response from OQSP to the local APRS identity is decoded',
      () async {
    storage.value = device;
    await controller.initialize();
    await controller.setAprsSsid(5);
    await controller.connect();
    await controller.checkOpenQsp();

    service.bytes.add(response(source: 'OQSP', body: 'Q1:ABC:00/01:AUYABQEAAAAP'));
    await Future<void>.delayed(Duration.zero);

    final object = controller.lastOpenQspObject as OpenQspCapabilities;
    expect(object.protocolVersion, 1);
    expect(object.capabilities, 0x0000000f);
    expect(controller.openQspCheckState, OpenQspCheckState.available);
  });

  test('valid Q1 from another station cannot satisfy the capability check',
      () async {
    storage.value = device;
    await controller.initialize();
    await controller.setAprsSsid(5);
    await controller.connect();
    await controller.checkOpenQsp();

    service.bytes.add(response(source: 'OTHER', body: 'Q1:ABC:00/01:AUYABQEAAAAP'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.lastOpenQspObject, isNull);
    expect(controller.openQspCheckState, OpenQspCheckState.waiting);
  });

  test('checkOpenQsp emits Core through Q1, APRS, AX.25 and KISS', () async {
    storage.value = device;
    await controller.initialize();
    await controller.setAprsSsid(5);
    await controller.connect();

    await controller.checkOpenQsp();

    expect(service.sentBytes, hasLength(1));
    final kiss = KissDecoder();
    final frameFuture = kiss.frames.first;
    kiss.add(service.sentBytes.single);
    final kissFrame = await frameFuture;
    final ax25 = const Ax25Decoder().decode(kissFrame.payload);
    final aprs = const AprsParser().parse(ax25)! as AprsTextMessage;
    expect(kissFrame.port, 0);
    expect(kissFrame.command, 0);
    expect(ax25.destination.callsign, openQspAprsTocall);
    expect(ax25.source.toString(), 'EA3GNU-5');
    expect(aprs.addressee, 'OQSP');
    expect(aprs.text, 'Q1:000:00/01:AQUAAA');
    await kiss.close();
  });

  test('dispose closes an active connection without later notifications', () async {
    storage.value = device;
    await controller.initialize();
    await controller.connect();
    var notifications = 0;
    controller.addListener(() => notifications++);
    final pendingDisconnect = Completer<void>();
    service.disconnectPending = pendingDisconnect.future;

    controller.dispose();

    expect(service.disconnectCalls, 1);
    expect(service.connected, isFalse);
    pendingDisconnect.complete();
    await pendingDisconnect.future;
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 0);
  });
}
