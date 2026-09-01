import 'dart:async';

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

void main() {
  test('burst control encoding uses one 16-bit missing mask', () {
    expect(encodeOpenQspBurstAck('0A7'), 'Q1A:0A7');
    expect(encodeOpenQspBurstMissing('0A7', {1, 4, 15}), 'Q1N:0A7:8012');

    final control = parseOpenQspBurstControl('Q1N:0A7:8012');
    expect(control, isA<OpenQspBurstMissing>());
    expect((control! as OpenQspBurstMissing).missing, {1, 4, 15});
  });

  test('Q1N retransmits only requested cached client fragments', () async {
    final delegate = _FakeBluetoothTncService();
    final link = BurstRepairBluetoothTncService(
      delegate,
      repairDelay: const Duration(milliseconds: 20),
    );
    final forwarded = <List<int>>[];
    final subscription = link.incomingBytes.listen(forwarded.add);

    final first = _kissMessage(
      source: 'EA3GNU',
      addressee: openQspAprsAddressee,
      body: 'Q1:ABC:00/02:A',
      messageId: '10',
    );
    final second = _kissMessage(
      source: 'EA3GNU',
      addressee: openQspAprsAddressee,
      body: 'Q1:ABC:01/02:B',
      messageId: '11',
    );
    await link.sendBytes(first);
    await link.sendBytes(second);
    expect(delegate.sent, hasLength(2));

    delegate.emit(
      _kissMessage(
        source: openQspAprsAddressee,
        addressee: 'EA3GNU',
        body: 'Q1N:ABC:0002',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(delegate.sent, hasLength(3));
    expect(delegate.sent.last, second);
    expect(forwarded, isEmpty, reason: 'link controls are consumed below Core');
    await subscription.cancel();
  });

  test('server burst gets one Q1A when complete and one Q1N when incomplete', () async {
    final delegate = _FakeBluetoothTncService();
    final link = BurstRepairBluetoothTncService(
      delegate,
      repairDelay: const Duration(milliseconds: 10),
    );
    final subscription = link.incomingBytes.listen((_) {});

    delegate.emit(
      _kissMessage(
        source: openQspAprsAddressee,
        addressee: 'EA3GNU-5',
        body: 'Q1:XYZ:00/02:A',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(_body(delegate.sent.last), 'Q1N:XYZ:0002');
    final controlsAfterMissing = delegate.sent.length;

    delegate.emit(
      _kissMessage(
        source: openQspAprsAddressee,
        addressee: 'EA3GNU-5',
        body: 'Q1:XYZ:01/02:B',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(delegate.sent.length, controlsAfterMissing + 1);
    expect(_body(delegate.sent.last), 'Q1A:XYZ');
    await subscription.cancel();
  });

  test('incomplete burst retries Q1N only after the slow silence interval', () async {
    final delegate = _FakeBluetoothTncService();
    final link = BurstRepairBluetoothTncService(
      delegate,
      repairDelay: const Duration(milliseconds: 10),
      repairRetryInterval: const Duration(milliseconds: 80),
    );
    final subscription = link.incomingBytes.listen((_) {});

    delegate.emit(
      _kissMessage(
        source: openQspAprsAddressee,
        addressee: 'EA3GNU',
        body: 'Q1:SLW:00/02:A',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(delegate.sent, hasLength(1));
    expect(_body(delegate.sent.single), 'Q1N:SLW:0002');

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(
      delegate.sent,
      hasLength(1),
      reason: 'Q1N must not repeat at the short repair grace cadence',
    );

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(delegate.sent, hasLength(2));
    expect(_body(delegate.sent.last), 'Q1N:SLW:0002');
    await subscription.cancel();
  });
}

List<int> _kissMessage({
  required String source,
  required String addressee,
  required String body,
  String? messageId,
}) {
  final sourceParts = source.split('-');
  final sourceSsid = sourceParts.length == 2 ? int.parse(sourceParts[1]) : 0;
  final information = const AprsMessageEncoder().encode(
    addressee: addressee,
    body: body,
    messageId: messageId,
  );
  final ax25 = const Ax25Encoder().encodeUi(
    destination: const Ax25Address(
      callsign: 'APOQSP',
      ssid: 0,
      hasBeenRepeated: false,
      isLast: false,
    ),
    source: Ax25Address(
      callsign: sourceParts.first,
      ssid: sourceSsid,
      hasBeenRepeated: false,
      isLast: true,
    ),
    information: information,
  );
  return const KissEncoder().encode(KissFrame(port: 0, command: 0, payload: ax25));
}

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
