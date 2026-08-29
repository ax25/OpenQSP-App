import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/aprs/data/bluetooth_tnc_service.dart';
import 'package:openqsp_app/features/aprs/domain/tnc_device.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_frame.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_transport.dart';

final class FakeBluetooth implements BluetoothTncService {
  final input = StreamController<List<int>>.broadcast();
  List<int>? written;
  @override
  Stream<List<int>> get incomingBytes => input.stream;
  @override
  Future<List<TncDevice>> bondedDevices() async => [];
  @override
  Future<void> connect(TncDevice device) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> sendBytes(List<int> data) async => written = List.of(data);
}

void main() {
  test('bridges incoming chunks to frames and frames to outgoing bytes', () async {
    final bluetooth = FakeBluetooth();
    final transport = KissTransport(bluetooth);
    final received = <KissFrame>[];
    transport.frames.listen(received.add);

    bluetooth.input.add([0xc0, 0, 1]);
    bluetooth.input.add([2, 0xc0]);
    expect(received.single.payload, [1, 2]);

    await transport.send(KissFrame(port: 0, command: 0, payload: [0xc0]));
    expect(bluetooth.written, [0xc0, 0, 0xdb, 0xdc, 0xc0]);

    await transport.close();
    await bluetooth.input.close();
  });
}
