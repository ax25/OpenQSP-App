import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openqsp_app/features/aprs/application/tnc_settings_controller.dart';
import 'package:openqsp_app/features/aprs/aprs/aprs_packet.dart';
import 'package:openqsp_app/features/aprs/aprs/aprs_parser.dart';
import 'package:openqsp_app/features/aprs/ax25/ax25_decoder.dart';
import 'package:openqsp_app/features/aprs/data/bluetooth_tnc_service.dart';
import 'package:openqsp_app/features/aprs/data/bluetooth_tnc_storage.dart';
import 'package:openqsp_app/features/aprs/domain/tnc_device.dart';
import 'package:openqsp_app/features/aprs/kiss/kiss_decoder.dart';
import 'package:openqsp_app/features/aprs/openqsp_carriage/openqsp_aprs_carriage.dart';

final class _PersistentMemoryStorage
    implements BluetoothTncStorage, OpenQspTransactionSequenceStorage {
  _PersistentMemoryStorage(this.device);

  TncDevice? device;
  int transactionSequence = 0;

  @override
  Future<void> clear() async => device = null;

  @override
  Future<TncDevice?> read() async => device;

  @override
  Future<void> write(TncDevice device) async => this.device = device;

  @override
  Future<int> readTransactionSequence() async => transactionSequence;

  @override
  Future<void> writeTransactionSequence(int sequence) async {
    transactionSequence = sequence;
  }
}

final class _FakeTncService implements BluetoothTncService {
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  final StreamController<int> _losses = StreamController<int>.broadcast();
  final List<List<int>> sentBytes = [];
  int? _activeConnectionId;

  @override
  int? get activeConnectionId => _activeConnectionId;

  @override
  Stream<List<int>> get incomingBytes => _incoming.stream;

  @override
  Stream<int> get unexpectedDisconnections => _losses.stream;

  @override
  Future<List<TncDevice>> bondedDevices() async => const [];

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
    sentBytes.add(List<int>.of(data));
  }
}

Future<String> _transactionIdFromProbe(List<int> encodedKiss) async {
  final kiss = KissDecoder();
  final frameFuture = kiss.frames.first;
  kiss.add(encodedKiss);
  final frame = await frameFuture;
  final ax25 = const Ax25Decoder().decode(frame.payload);
  final aprs = const AprsParser().parse(ax25)! as AprsTextMessage;
  final transactionId = parseFragment(aprs.text).transactionId;
  await kiss.close();
  return transactionId;
}

void main() {
  const device = TncDevice(id: '00:11:22:33:44:55', name: 'TNC');

  test('GET_CAPABILITIES continues transaction sequence after app restart',
      () async {
    final storage = _PersistentMemoryStorage(device);

    final firstService = _FakeTncService();
    final first = TncSettingsController(
      storage: storage,
      service: firstService,
      sourceCallsign: 'EA3GNU',
    );
    await first.initialize();
    await first.connect();
    await first.checkOpenQsp();

    expect(firstService.sentBytes, hasLength(1));
    expect(await _transactionIdFromProbe(firstService.sentBytes.single), '000');
    expect(storage.transactionSequence, 1);
    first.dispose();

    final secondService = _FakeTncService();
    final second = TncSettingsController(
      storage: storage,
      service: secondService,
      sourceCallsign: 'EA3GNU',
    );
    await second.initialize();
    await second.connect();
    await second.checkOpenQsp();

    expect(secondService.sentBytes, hasLength(1));
    expect(await _transactionIdFromProbe(secondService.sentBytes.single), '001');
    expect(storage.transactionSequence, 2);
    second.dispose();
  });

  test('transaction sequence wraps from ZZZ to 000', () async {
    final storage = _PersistentMemoryStorage(device)
      ..transactionSequence = 36 * 36 * 36 - 1;
    final service = _FakeTncService();
    final controller = TncSettingsController(
      storage: storage,
      service: service,
      sourceCallsign: 'EA3GNU',
    );
    await controller.initialize();
    await controller.connect();
    await controller.checkOpenQsp();

    expect(await _transactionIdFromProbe(service.sentBytes.single), 'ZZZ');
    expect(storage.transactionSequence, 0);
    controller.dispose();
  });
}
