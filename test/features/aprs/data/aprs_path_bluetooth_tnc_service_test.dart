import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/aprs/aprs/aprs_message_encoder.dart';
import 'package:openqsp_app/features/aprs/aprs/aprs_packet.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_address.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_decoder.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_encoder.dart';
import 'package:openqsp_app/features/aprs/data/aprs_path_bluetooth_tnc_service.dart';
import 'package:openqsp_app/features/aprs/data/aprs_path_storage.dart';
import 'package:openqsp_app/features/aprs/data/bluetooth_tnc_service.dart';
import 'package:openqsp_app/features/aprs/domain/aprs_path.dart';
import 'package:openqsp_app/features/aprs/domain/tnc_device.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_decoder.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_encoder.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_frame.dart';

void main() {
  for (final testCase in <(AprsPathMode, List<String>)>[
    (AprsPathMode.direct, const []),
    (AprsPathMode.oneHop, const ['WIDE1-1']),
    (AprsPathMode.twoHops, const ['WIDE1-1', 'WIDE2-1']),
  ]) {
    test('${testCase.$1.name} rewrites outbound OpenQSP path', () async {
      final delegate = _FakeBluetoothTncService();
      final service = AprsPathBluetoothTncService(
        delegate,
        storage: _FakeAprsPathStorage(testCase.$1),
      );

      await service.sendBytes(_openQspKissFrame());

      final ax25 = _decodeKissAx25(delegate.sent.single);
      expect(
        ax25.digipeaters.map((address) => address.toString()).toList(),
        testCase.$2,
      );
    });
  }

  test('non-OpenQSP KISS traffic is not rewritten', () async {
    final delegate = _FakeBluetoothTncService();
    final service = AprsPathBluetoothTncService(
      delegate,
      storage: _FakeAprsPathStorage(AprsPathMode.twoHops),
    );
    final original = const KissEncoder().encode(
      KissFrame(
        port: 0,
        command: 0,
        payload: const Ax25Encoder().encodeUi(
          destination: const Ax25Address(
            callsign: 'APRS',
            ssid: 0,
            hasBeenRepeated: false,
            isLast: false,
          ),
          source: const Ax25Address(
            callsign: 'EA3GNU',
            ssid: 0,
            hasBeenRepeated: false,
            isLast: true,
          ),
          information: '!test'.codeUnits,
        ),
      ),
    );

    await service.sendBytes(original);

    expect(delegate.sent.single, original);
  });
}

List<int> _openQspKissFrame() {
  final information = const AprsMessageEncoder().encode(
    addressee: openQspAprsAddressee,
    body: 'Q2test',
  );
  final ax25 = const Ax25Encoder().encodeUi(
    destination: const Ax25Address(
      callsign: 'APOQSP',
      ssid: 0,
      hasBeenRepeated: false,
      isLast: false,
    ),
    source: const Ax25Address(
      callsign: 'EA3GNU',
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

dynamic _decodeKissAx25(List<int> bytes) {
  final decoder = KissDecoder();
  KissFrame? frame;
  final subscription = decoder.frames.listen((value) => frame ??= value);
  decoder.add(bytes);
  unawaited(subscription.cancel());
  unawaited(decoder.close());
  return const Ax25Decoder().decode(frame!.payload);
}

final class _FakeAprsPathStorage implements AprsPathStorage {
  _FakeAprsPathStorage(this.mode);
  AprsPathMode mode;

  @override
  Future<AprsPathMode> read() async => mode;

  @override
  Future<void> write(AprsPathMode value) async => mode = value;
}

final class _FakeBluetoothTncService implements BluetoothTncService {
  final sent = <List<int>>[];

  @override
  Stream<List<int>> get incomingBytes => const Stream.empty();

  @override
  Stream<int> get unexpectedDisconnections => const Stream.empty();

  @override
  int? get activeConnectionId => null;

  @override
  Future<List<TncDevice>> bondedDevices() async => const [];

  @override
  Future<void> connect(TncDevice device) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> sendBytes(List<int> data) async => sent.add(List.of(data));
}
