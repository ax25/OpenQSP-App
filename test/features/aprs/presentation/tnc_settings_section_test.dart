import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/aprs/application/tnc_settings_controller.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_address.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_encoder.dart';
import 'package:openqsp_app/features/aprs/data/bluetooth_tnc_service.dart';
import 'package:openqsp_app/features/aprs/data/bluetooth_tnc_storage.dart';
import 'package:openqsp_app/features/aprs/domain/tnc_device.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_encoder.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_frame.dart';
import 'package:openqsp_app/features/aprs/presentation/tnc_settings_section.dart';

const device = TncDevice(id: 'id', name: 'TNC');

final class _Storage implements BluetoothTncStorage {
  @override
  Future<void> clear() async {}
  @override
  Future<TncDevice?> read() async => device;
  @override
  Future<void> write(TncDevice device) async {}
}

final class _Service implements BluetoothTncService {
  final input = StreamController<List<int>>.broadcast();
  final losses = StreamController<int>.broadcast();
  @override
  int? get activeConnectionId => 1;
  @override
  Stream<List<int>> get incomingBytes => input.stream;
  @override
  Stream<int> get unexpectedDisconnections => losses.stream;
  @override
  Future<List<TncDevice>> bondedDevices() async => [device];
  @override
  Future<void> connect(TncDevice device) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> sendBytes(List<int> data) async {}
}

Future<TncSettingsController> connectedController({
  Duration timeout = const Duration(seconds: 20),
}) async {
  final controller = TncSettingsController(
    storage: _Storage(),
    service: _Service(),
    sourceCallsign: 'EA3GNU',
    openQspTimeout: timeout,
  );
  await controller.initialize();
  await controller.connect();
  await controller.setAprsSsid(5);
  return controller;
}

Widget subject(TncSettingsController controller) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: TncSettingsSection(controller: controller),
    ),
  ),
);

void main() {
  testWidgets('normal APRS settings hide diagnostics and disable check offline',
      (tester) async {
    final controller = TncSettingsController(
      storage: _Storage(),
      service: _Service(),
      sourceCallsign: 'EA3GNU',
    );
    await tester.pumpWidget(subject(controller));
    await tester.pump();
    expect(find.text('Diagnóstico KISS'), findsNothing);
    expect(find.text('Diagnóstico AX.25'), findsNothing);
    expect(find.text('Diagnóstico APRS'), findsNothing);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Comprobar OpenQSP'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('check displays waiting and then timeout', (tester) async {
    final controller = await connectedController(timeout: const Duration(milliseconds: 10));
    await tester.pumpWidget(subject(controller));
    await tester.pump();
    await tester.tap(find.text('Comprobar OpenQSP'));
    await tester.pump();
    expect(find.text('Esperando respuesta…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Sin respuesta'), findsOneWidget);
  });

  testWidgets('valid CAPABILITIES displays available', (tester) async {
    final controller = await connectedController();
    final service = controller.service as _Service;
    await tester.pumpWidget(subject(controller));
    await tester.pump();
    await tester.tap(find.text('Comprobar OpenQSP'));
    await tester.pump();
    final ax25 = const Ax25Encoder().encodeUi(
      destination: const Ax25Address(callsign: openQspAprsTocall, ssid: 0, hasBeenRepeated: false, isLast: false),
      source: const Ax25Address(callsign: 'OQSP', ssid: 0, hasBeenRepeated: false, isLast: true),
      information: ':EA3GNU-5 :Q1:ABC:00/01:AUYABQEAAAAP'.codeUnits,
    );
    service.input.add(const KissEncoder().encode(KissFrame(port: 0, command: 0, payload: ax25)));
    await tester.pump();
    expect(find.text('Disponible'), findsOneWidget);
    expect(find.text('0x0000000F'), findsOneWidget);
  });
}
