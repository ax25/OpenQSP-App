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
  test('A2 and N2 use compact Base91 transaction controls', () {
    final ack = encodeOpenQspBurstAck('005');
    final nack = encodeOpenQspBurstMissing('005', {1, 4, 15});
    expect(ack, startsWith('A2'));
    expect(ack.length, lessThanOrEqualTo(4));
    expect(nack, startsWith('N2'));
    expect(nack.length, lessThanOrEqualTo(6));

    final parsedAck = parseOpenQspBurstControl(ack)! as OpenQspBurstAck;
    expect(parsedAck.transactionId, '005');
    final parsedNack = parseOpenQspBurstControl(nack)! as OpenQspBurstMissing;
    expect(parsedNack.transactionId, '005');
    expect(parsedNack.missing, {1, 4, 15});
  });

  test('legacy Q1A/Q1N remain parseable during migration', () {
    expect(parseOpenQspBurstControl('Q1A:0A7'), isA<OpenQspBurstAck>());
    final control = parseOpenQspBurstControl('Q1N:0A7:8012');
    expect(control, isA<OpenQspBurstMissing>());
    expect((control! as OpenQspBurstMissing).missing, {1, 4, 15});
  });

  test('N2 retransmits only requested cached client Q2 fragment', () async {
    final delegate = _FakeBluetoothTncService();
    final link = BurstRepairBluetoothTncService(delegate);
    final subscription = link.incomingBytes.listen((_) {});

    final first = _kissMessage(
      source: 'EA3GNU',
      addressee: openQspAprsAddressee,
      body: _q2('005', 0, 2, [1]).body,
    );
    final second = _kissMessage(
      source: 'EA3GNU',
      addressee: openQspAprsAddressee,
      body: _q2('005', 1, 2, [2]).body,
    );
    await link.sendBytes(first);
    await link.sendBytes(second);

    delegate.emit(
      _kissMessage(
        source: openQspAprsAddressee,
        addressee: 'EA3GNU',
        body: encodeOpenQspBurstMissing('005', {1}),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(delegate.sent, hasLength(3));
    expect(delegate.sent.last, second);
    await subscription.cancel();
  });

  test('silent outbound Q2 burst retries then stops when A2 arrives', () async {
    final delegate = _FakeBluetoothTncService();
    final link = BurstRepairBluetoothTncService(
      delegate,
      repairRetryInterval: const Duration(milliseconds: 10),
      silentRetryTtl: const Duration(milliseconds: 50),
    );
    final subscription = link.incomingBytes.listen((_) {});
    final packet = _kissMessage(
      source: 'EA3GNU',
      addressee: openQspAprsAddressee,
      body: _q2('009', 0, 1, [1]).body,
    );

    await link.sendBytes(packet);
    expect(delegate.sent, hasLength(1));

    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(delegate.sent, hasLength(2));

    delegate.emit(
      _kissMessage(
        source: openQspAprsAddressee,
        addressee: 'EA3GNU',
        body: encodeOpenQspBurstAck('009'),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(delegate.sent, hasLength(2));
    await subscription.cancel();
    await link.close();
  });

  test('incomplete server Q2 burst emits N2 after quiet period', () async {
    final delegate = _FakeBluetoothTncService();
    final link = BurstRepairBluetoothTncService(
      delegate,
      repairDelay: const Duration(milliseconds: 10),
      finalFragmentRepairDelay: const Duration(milliseconds: 10),
    );
    final subscription = link.incomingBytes.listen((_) {});

    delegate.emit(
      _kissMessage(
        source: openQspAprsAddressee,
        addressee: 'EA3GNU-5',
        body: _q2('006', 0, 2, [1]).body,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final parsed = parseOpenQspBurstControl(_body(delegate.sent.last))!
        as OpenQspBurstMissing;
    expect(parsed.transactionId, '006');
    expect(parsed.missing, {1});
    await subscription.cancel();
  });

  test('complete server Q2 burst emits one delayed A2', () async {
    final delegate = _FakeBluetoothTncService();
    final link = BurstRepairBluetoothTncService(
      delegate,
      repairDelay: const Duration(milliseconds: 20),
      finalFragmentRepairDelay: const Duration(milliseconds: 10),
    );
    final forwarded = <List<int>>[];
    final subscription = link.incomingBytes.listen(forwarded.add);

    delegate.emit(
      _kissMessage(
        source: openQspAprsAddressee,
        addressee: 'EA3GNU',
        body: _q2('007', 0, 1, [1, 5, 0, 0]).body,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(forwarded, hasLength(1));
    final control = parseOpenQspBurstControl(_body(delegate.sent.single));
    expect(control, isA<OpenQspBurstAck>());
    expect((control! as OpenQspBurstAck).transactionId, '007');
    await subscription.cancel();
  });

  test('duplicate completed Q2 remains visible and emits recovery A2', () async {
    final delegate = _FakeBluetoothTncService();
    final link = BurstRepairBluetoothTncService(
      delegate,
      finalFragmentRepairDelay: const Duration(milliseconds: 10),
    );
    final forwarded = <List<int>>[];
    final subscription = link.incomingBytes.listen(forwarded.add);
    final packet = _kissMessage(
      source: openQspAprsAddressee,
      addressee: 'EA3GNU',
      body: _q2('00D', 0, 1, [1, 5, 0, 0]).body,
    );

    delegate.emit(packet);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(forwarded, hasLength(1));
    expect(delegate.sent, hasLength(1));

    delegate.emit(packet);
    await Future<void>.delayed(Duration.zero);

    expect(forwarded, hasLength(2));
    expect(forwarded.last, packet);
    expect(delegate.sent, hasLength(2));
    final recoveryAck = parseOpenQspBurstControl(_body(delegate.sent.last));
    expect(recoveryAck, isA<OpenQspBurstAck>());
    expect((recoveryAck! as OpenQspBurstAck).transactionId, '00D');
    await subscription.cancel();
  });

  test('S2 is translated to a downstream one-fragment Core STORED', () async {
    final delegate = _FakeBluetoothTncService();
    final link = BurstRepairBluetoothTncService(delegate);
    final forwarded = <List<int>>[];
    final subscription = link.incomingBytes.listen(forwarded.add);
    final s2 = 'S2${encodeOpenQspBase91([8])}';

    delegate.emit(
      _kissMessage(
        source: openQspAprsAddressee,
        addressee: 'EA3GNU',
        body: s2,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(forwarded, hasLength(1));
    final body = _body(forwarded.single);
    final fragment = parseFragment(body);
    expect(fragment.transactionId, '008');
    expect(fragment.total, 1);
    expect(fragment.rawData, Uint8List.fromList([1, 0x44, 0, 0]));
    expect(delegate.sent, isEmpty, reason: 'S2 itself does not require A2');
    await subscription.cancel();
  });

  test('third-party S2 keeps OQSP as logical source downstream', () async {
    final delegate = _FakeBluetoothTncService();
    final link = BurstRepairBluetoothTncService(delegate);
    final forwarded = <List<int>>[];
    final subscription = link.incomingBytes.listen(forwarded.add);
    final s2 = 'S2${encodeOpenQspBase91([165])}';

    delegate.emit(
      _kissThirdPartyMessage(
        igate: 'EA3IK-1',
        source: openQspAprsAddressee,
        addressee: 'EA3GNU',
        body: s2,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(forwarded, hasLength(1));
    final packet = _packet(forwarded.single);
    expect(packet.frame.source.toString(), openQspAprsAddressee);
    expect(packet.addressee, 'EA3GNU');
    final fragment = parseFragment(packet.text);
    expect(fragment.transactionId, '04L');
    expect(fragment.rawData, Uint8List.fromList([1, 0x44, 0, 0]));
    await subscription.cancel();
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
  return const KissEncoder().encode(
    KissFrame(port: 0, command: 0, payload: ax25),
  );
}

List<int> _kissThirdPartyMessage({
  required String igate,
  required String source,
  required String addressee,
  required String body,
}) {
  final igateParts = igate.split('-');
  final igateSsid = igateParts.length == 2 ? int.parse(igateParts[1]) : 0;
  final paddedAddressee = addressee.padRight(9);
  final information =
      '}$source>APOQSP,TCPIP*,qAC,$igate::$paddedAddressee:$body'.codeUnits;
  final ax25 = const Ax25Encoder().encodeUi(
    destination: const Ax25Address(
      callsign: 'APRS',
      ssid: 0,
      hasBeenRepeated: false,
      isLast: false,
    ),
    source: Ax25Address(
      callsign: igateParts.first,
      ssid: igateSsid,
      hasBeenRepeated: false,
      isLast: true,
    ),
    information: information,
  );
  return const KissEncoder().encode(
    KissFrame(port: 0, command: 0, payload: ax25),
  );
}

AprsTextMessage _packet(List<int> kiss) {
  final decoder = KissDecoder();
  KissFrame? frame;
  final subscription = decoder.frames.listen((value) => frame = value);
  decoder.add(kiss);
  unawaited(subscription.cancel());
  unawaited(decoder.close());
  final ax25 = const Ax25Decoder().decode(frame!.payload);
  return const AprsParser().parse(ax25)! as AprsTextMessage;
}

String _body(List<int> kiss) => _packet(kiss).text;

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
