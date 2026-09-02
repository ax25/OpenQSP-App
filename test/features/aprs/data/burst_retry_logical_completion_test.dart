import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/aprs/aprs/aprs_message_encoder.dart';
import 'package:openqsp_app/features/aprs/aprs/aprs_packet.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_address.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_encoder.dart';
import 'package:openqsp_app/features/aprs/data/bluetooth_tnc_service.dart';
import 'package:openqsp_app/features/aprs/data/burst_repair_bluetooth_tnc_service.dart';
import 'package:openqsp_app/features/aprs/domain/tnc_device.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_encoder.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_frame.dart';
import 'package:openqsp_app/features/aprs/openqsp_carriage/openqsp_aprs_carriage.dart';

void main() {
  test('logical response completion cancels silent request retry', () async {
    final delegate = _FakeBluetoothTncService();
    final link = BurstRepairBluetoothTncService(
      delegate,
      repairRetryInterval: const Duration(milliseconds: 15),
      silentRetryTtl: const Duration(milliseconds: 100),
    );

    await link.sendBytes(
      _kissMessage(
        source: 'EA3GNU',
        addressee: openQspAprsAddressee,
        body: _q2('04X', [1, 3, 0, 0, 0, 54, 8]).body,
      ),
    );
    expect(delegate.sent, hasLength(1));

    // A server response can use another Q2 transaction ID. The logical layer
    // therefore retires the original request explicitly instead of waiting for
    // A2 on 04X.
    link.completeOutboundTransaction('04X');

    await Future<void>.delayed(const Duration(milliseconds: 35));
    expect(delegate.sent, hasLength(1));

    await link.close();
  });
}

OpenQspAprsFragment _q2(String transactionId, List<int> raw) =>
    OpenQspAprsFragment(
      transactionId: transactionId,
      index: 0,
      total: 1,
      data: '',
      version: 2,
      rawData: Uint8List.fromList(raw),
    );

List<int> _kissMessage({
  required String source,
  required String addressee,
  required String body,
}) {
  final information = const AprsMessageEncoder().encode(
    addressee: addressee,
    body: body,
  );
  final ax25 = const Ax25Encoder().encodeUi(
    destination: const Ax25Address(
      callsign: 'APOQSP',
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

final class _FakeBluetoothTncService implements BluetoothTncService {
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast(sync: true);
  final StreamController<int> _disconnects =
      StreamController<int>.broadcast(sync: true);
  final List<List<int>> sent = [];

  @override
  Stream<List<int>> get incomingBytes => _incoming.stream;

  @override
  Stream<int> get unexpectedDisconnections => _disconnects.stream;

  @override
  int? get activeConnectionId => 1;

  @override
  Future<List<TncDevice>> bondedDevices() async => const [];

  @override
  Future<void> connect(TncDevice device) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> sendBytes(List<int> data) async {
    sent.add(List<int>.from(data));
  }
}
