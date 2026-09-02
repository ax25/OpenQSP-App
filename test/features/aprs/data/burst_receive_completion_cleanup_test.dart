import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/aprs/aprs/aprs_message_encoder.dart';
import 'package:openqsp_app/features/aprs/aprs/aprs_packet.dart';
import 'package:openqsp_app/features/aprs/aprs/aprs_parser.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_address.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_decoder.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_encoder.dart';
import 'package:openqsp_app/features/aprs/data/bluetooth_tnc_service.dart';
import 'package:openqsp_app/features/aprs/data/burst_repair_bluetooth_tnc_service.dart';
import 'package:openqsp_app/features/aprs/domain/tnc_device.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_decoder.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_encoder.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_frame.dart';
import 'package:openqsp_app/features/aprs/openqsp_carriage/openqsp_carriage.dart';

void main() {
  test('completing one RX transaction cancels all stale NACK timers', () async {
    final delegate = _FakeBluetoothTncService();
    final link = BurstRepairBluetoothTncService(
      delegate,
      repairDelay: const Duration(milliseconds: 10),
      finalFragmentRepairDelay: const Duration(milliseconds: 5),
      repairRetryInterval: const Duration(milliseconds: 15),
    );
    final subscription = link.incomingBytes.listen((_) {});

    // Leave 005 incomplete so it starts requesting its missing fragment.
    delegate.emit(
      _kissMessage(
        source: openQspAprsAddressee,
        addressee: 'EA3GNU',
        body: _q2('005', 0, 2, [1]).body,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 13));
    expect(_controls(delegate.sent, '005').whereType<OpenQspBurstMissing>(), hasLength(1));

    // A later response transaction completes successfully. From this point no
    // stale 005 NACK timer may survive.
    delegate.emit(
      _kissMessage(
        source: openQspAprsAddressee,
        addressee: 'EA3GNU',
        body: _q2('006', 0, 1, [1, 5, 0, 0]).body,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 35));

    expect(
      _controls(delegate.sent, '005').whereType<OpenQspBurstMissing>(),
      hasLength(1),
      reason: 'completion of 006 must cancel the repeating NACK timer for 005',
    );

    await subscription.cancel();
    await link.close();
  });

  test('extra fragment after completion sends recovery ACK immediately', () async {
    final delegate = _FakeBluetoothTncService();
    final link = BurstRepairBluetoothTncService(
      delegate,
      finalFragmentRepairDelay: const Duration(milliseconds: 10),
    );
    final subscription = link.incomingBytes.listen((_) {});
    final packet = _kissMessage(
      source: openQspAprsAddressee,
      addressee: 'EA3GNU',
      body: _q2('006', 0, 1, [1, 5, 0, 0]).body,
    );

    delegate.emit(packet);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(_acks(delegate.sent, '006'), hasLength(1));

    delegate.emit(packet);
    await Future<void>.delayed(Duration.zero);

    expect(
      _acks(delegate.sent, '006'),
      hasLength(2),
      reason: 'any later fragment of an already-complete transaction must ACK again',
    );

    await subscription.cancel();
    await link.close();
  });
}

OpenQspAprsFragment _q2(String tx, int index, int total, List<int> raw) =>
    OpenQspAprsFragment(
      transactionId: tx,
      index: index,
      total: total,
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

Iterable<OpenQspBurstControl> _controls(List<List<int>> packets, String transactionId) sync* {
  for (final packet in packets) {
    final control = parseOpenQspBurstControl(_body(packet));
    if (control == null) continue;
    final id = switch (control) {
      OpenQspBurstAck(:final transactionId) => transactionId,
      OpenQspBurstMissing(:final transactionId) => transactionId,
    };
    if (id == transactionId) yield control;
  }
}

List<OpenQspBurstAck> _acks(List<List<int>> packets, String transactionId) =>
    _controls(packets, transactionId).whereType<OpenQspBurstAck>().toList();

String _body(List<int> kiss) {
  final decoder = KissDecoder();
  KissFrame? frame;
  final subscription = decoder.frames.listen((value) => frame = value);
  decoder.add(kiss);
  unawaited(subscription.cancel());
  unawaited(decoder.close());
  final ax25 = const Ax25Decoder().decode(frame!.payload);
  final packet = const AprsParser().parse(ax25)! as AprsTextMessage;
  return packet.text;
}

final class _FakeBluetoothTncService implements BluetoothTncService {
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast(sync: true);
  final StreamController<int> _disconnects =
      StreamController<int>.broadcast(sync: true);
  final List<List<int>> sent = [];

  void emit(List<int> bytes) => _incoming.add(bytes);

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
