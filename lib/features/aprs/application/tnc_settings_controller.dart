import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/openqsp_protocol/openqsp_codec.dart';
import '../../../core/openqsp_protocol/openqsp_models.dart';
import '../../../core/openqsp_protocol/openqsp_operation.dart';
import '../aprs/aprs_message_encoder.dart';
import '../ax25/ax25_decoder.dart';
import '../ax25/ax25_address.dart';
import '../ax25/ax25_encoder.dart';
import '../ax25/ax25_frame.dart';
import '../aprs/aprs_packet.dart';
import '../aprs/aprs_parser.dart';
import '../data/bluetooth_tnc_service.dart';
import '../data/bluetooth_tnc_storage.dart';
import '../domain/tnc_connection_state.dart';
import '../domain/tnc_device.dart';
import '../kiss/kiss_encoder.dart';
import '../kiss/kiss_frame.dart';
import '../kiss/kiss_transport.dart';
import '../openqsp_carriage/openqsp_aprs_carriage.dart';

enum OpenQspCheckState { notChecked, waiting, available, noResponse, error }

enum AprsConsoleDirection { tx, rx, other }

final class AprsConsoleEntry {
  const AprsConsoleEntry({
    required this.timestamp,
    required this.direction,
    required this.source,
    required this.destination,
    required this.via,
    required this.type,
    required this.content,
  });

  final DateTime timestamp;
  final AprsConsoleDirection direction;
  final String source;
  final String destination;
  final String via;
  final String type;
  final String content;
}

/// APRS application destination (tocall), distinct from the message addressee.
const openQspAprsTocall = 'APOQSP';

class TncSettingsController extends ChangeNotifier {
  TncSettingsController({
    required this.storage,
    required this.service,
    this.sourceCallsign,
    this.openQspTimeout = const Duration(seconds: 65),
    this.openQspRetryInterval = const Duration(seconds: 15),
  }) {
    _kissTransport = KissTransport(service);
    _byteSubscription = service.incomingBytes.listen((bytes) {
      rxBytes += bytes.length;
      _notify();
    });
    _frameSubscription = _kissTransport.frames.listen((frame) {
      rxKissFrames++;
      _activity.insert(0, 'RX  ${_hex(const KissEncoder().encode(frame))}');
      if (_activity.length > 10) _activity.removeLast();
      if (frame.port == 0 && frame.command == 0) _decodeAx25(frame.payload);
      _notify();
    });
    _connectionLossSubscription = service.unexpectedDisconnections.listen((id) {
      if (id != service.activeConnectionId ||
          state != TncConnectionState.connected) {
        return;
      }
      _setError(TncFailure.connectionFailed);
    });
  }

  static const _ansiBlue = '\x1B[34m';
  static const _ansiGreen = '\x1B[32m';
  static const _ansiRed = '\x1B[31m';
  static const _ansiReset = '\x1B[0m';
  static const _maximumConsoleEntries = 300;
  static const _transactionSequenceModulo = 36 * 36 * 36;

  final BluetoothTncStorage storage;
  final BluetoothTncService service;
  final String? sourceCallsign;
  final Duration openQspTimeout;
  @Deprecated('Capability retries are handled by the burst reliability layer.')
  final Duration openQspRetryInterval;
  TncConnectionState state = TncConnectionState.loading;
  TncDevice? device;
  TncFailure? failure;
  bool _disposed = false;
  late final KissTransport _kissTransport;
  late final StreamSubscription<List<int>> _byteSubscription;
  late final StreamSubscription<KissFrame> _frameSubscription;
  late final StreamSubscription<int> _connectionLossSubscription;
  int rxBytes = 0;
  int rxKissFrames = 0;
  int txKissFrames = 0;
  final List<String> _activity = [];
  final List<String> _ax25Activity = [];
  final List<String> _aprsActivity = [];
  final List<AprsConsoleEntry> _aprsConsoleEntries = [];
  static const Ax25Decoder _ax25Decoder = Ax25Decoder();
  static const AprsParser _aprsParser = AprsParser();
  int rxAx25Frames = 0;
  int ax25DecodeErrors = 0;
  int rxAprsPackets = 0;
  int aprsParseErrors = 0;
  int aprsMessages = 0;
  int aprsAcks = 0;
  int aprsRejects = 0;
  int openQspRxPackets = 0;
  int openQspFragmentsRx = 0;
  int openQspMessageFragmentsRx = 0;
  int? lastOpenQspMessageFragmentSequence;
  int openQspFramesRx = 0;
  int openQspErrors = 0;
  OpenQspFrameObject? lastOpenQspObject;
  DateTime? lastValidOpenQspRx;
  String? lastOpenQspIgate;
  OpenQspCheckState openQspCheckState = OpenQspCheckState.notChecked;
  int aprsSsid = 0;
  Timer? _openQspTimer;
  Timer? _openQspCountdownTimer;
  DateTime? _openQspCheckDeadline;
  final OpenQspAprsReassembler _reassembler = OpenQspAprsReassembler();
  final OpenQspAprsReassembler _trafficRxReassembler = OpenQspAprsReassembler();
  final OpenQspAprsReassembler _trafficTxReassembler = OpenQspAprsReassembler();
  final Map<String, _CompletedOpenQspTransaction>
  _completedOpenQspTransactions = {};
  final Map<String, int> _incomingMessageTransactions = {};
  static const OpenQspCodec _openQspCodec = OpenQspCodec();
  static const Ax25Encoder _ax25Encoder = Ax25Encoder();
  static const AprsMessageEncoder _messageEncoder = AprsMessageEncoder();
  int _transactionSequence = 0;

  List<String> get kissActivity => List.unmodifiable(_activity);
  List<String> get ax25Activity => List.unmodifiable(_ax25Activity);
  List<String> get aprsActivity => List.unmodifiable(_aprsActivity);
  List<AprsConsoleEntry> get aprsConsoleEntries =>
      List.unmodifiable(_aprsConsoleEntries);
  bool get kissReady => state == TncConnectionState.connected;

  void clearAprsConsole() {
    if (_aprsConsoleEntries.isEmpty) return;
    _aprsConsoleEntries.clear();
    _notify();
  }

  String? get _localAprsIdentity {
    final call = sourceCallsign;
    if (call == null) return null;
    return aprsSsid == 0 ? call : '$call-$aprsSsid';
  }

  Duration get openQspCheckRemaining {
    final deadline = _openQspCheckDeadline;
    if (openQspCheckState != OpenQspCheckState.waiting || deadline == null) {
      return Duration.zero;
    }
    final remaining = deadline.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  int get openQspCheckRemainingSeconds {
    final milliseconds = openQspCheckRemaining.inMilliseconds;
    if (milliseconds <= 0) return 0;
    return (milliseconds / Duration.millisecondsPerSecond).ceil();
  }

  static String _hex(Iterable<int> bytes) => bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');

  static String _trafficTimestamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final millis = now.millisecond.toString().padLeft(3, '0');
    return '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.$millis';
  }

  static void _debugColor(String message, String color) {
    if (kDebugMode) {
      debugPrint('$color${_trafficTimestamp()} $message$_ansiReset');
    }
  }

  bool _isLocalAprsPacket(AprsPacket packet) {
    final local = _localAprsIdentity;
    if (local == null) return false;
    return switch (packet) {
      AprsTextMessage(:final addressee) => addressee == local,
      AprsAck(:final addressee) => addressee == local,
      AprsReject(:final addressee) => addressee == local,
      AprsUnknown() || AprsInvalid() =>
        packet.frame.destination.toString() == local,
    };
  }

  static String _singleLine(String value) =>
      value.replaceAll('\r', ' ').replaceAll('\n', ' ').trim();

  static bool _isOpenQspWireText(String text) =>
      text.startsWith('Q1:') ||
      text.startsWith('Q2') ||
      text.startsWith('Q1A:') ||
      text.startsWith('Q1N:') ||
      text.startsWith('A2') ||
      text.startsWith('N2') ||
      text.startsWith('S2');

  static bool _isOpenQspControlText(String text) =>
      text.startsWith('Q1A:') ||
      text.startsWith('Q1N:') ||
      text.startsWith('A2') ||
      text.startsWith('N2') ||
      text.startsWith('S2');

  static String _trafficType(AprsPacket packet) => switch (packet) {
    AprsTextMessage(:final text) when _isOpenQspWireText(text) => 'OPENQSP',
    AprsTextMessage() => 'MESSAGE',
    AprsAck() => 'ACK',
    AprsReject() => 'REJECT',
    AprsUnknown(:final typeIdentifier) => switch (typeIdentifier) {
      '!' || '=' || '/' || '@' => 'POSITION',
      '_' => 'WEATHER',
      '>' => 'STATUS',
      'T' => 'TELEMETRY',
      ';' => 'OBJECT',
      _ => 'APRS/$typeIdentifier',
    },
    AprsInvalid() => 'INVALID',
  };

  String _trafficContent(AprsPacket packet, {required bool transmitted}) {
    return switch (packet) {
      AprsTextMessage(:final text)
          when text.startsWith('Q1:') || text.startsWith('Q2') =>
        _humanizeOpenQspAprs(packet, transmitted: transmitted),
      AprsTextMessage(:final text) when _isOpenQspControlText(text) =>
        _humanizeOpenQspControl(text),
      AprsTextMessage(:final text, :final messageId) =>
        messageId == null ? text : '$text [message id $messageId]',
      AprsAck(:final messageId) => 'message $messageId acknowledged',
      AprsReject(:final messageId) => 'message $messageId rejected',
      AprsUnknown() => _humanizeAprsUnknown(packet),
      AprsInvalid(:final reason) => 'invalid APRS packet: $reason',
    };
  }

  static String _humanizeOpenQspControl(String text) {
    if (text.startsWith('A2') || text.startsWith('S2')) {
      try {
        final payload = decodeOpenQspBase91(text.substring(2));
        if (payload.length == 1) {
          final transaction = encodeBase36(payload[0], 3);
          return '${text.startsWith('A2') ? 'ACK' : 'STORED'} | txn=$transaction';
        }
      } on Object {
        // Fall through to the generic control text below.
      }
    }
    if (text.startsWith('N2')) {
      try {
        final payload = decodeOpenQspBase91(text.substring(2));
        if (payload.length == 3) {
          final transaction = encodeBase36(payload[0], 3);
          final mask = (payload[1] << 8) | payload[2];
          if (mask != 0) {
            final missing = <String>[
              for (var index = 0; index < 16; index++)
                if ((mask & (1 << index)) != 0) '${index + 1}',
            ];
            return 'NACK | txn=$transaction | missing=${missing.join(',')} | '
                'mask=0x${mask.toRadixString(16).toUpperCase().padLeft(4, '0')}';
          }
        }
      } on Object {
        // Fall through to the generic control text below.
      }
    }
    if (text.startsWith('Q1A:')) {
      return 'ACK | txn=${text.substring(4)} | legacy=Q1';
    }
    final parts = text.split(':');
    if (parts.length == 3 && parts.first == 'Q1N') {
      final mask = int.tryParse(parts[2], radix: 16);
      if (mask != null) {
        final missing = <String>[];
        for (var index = 0; index < 16; index++) {
          if ((mask & (1 << index)) != 0) missing.add('${index + 1}');
        }
        return 'NACK | txn=${parts[1]} | missing=${missing.join(',')} | '
            'mask=0x${parts[2]} | legacy=Q1';
      }
    }
    return 'unrecognized OpenQSP control';
  }

  String _humanizeOpenQspAprs(
    AprsTextMessage packet, {
    required bool transmitted,
  }) {
    try {
      final fragment = parseFragment(packet.text);
      final profile = 'Q${fragment.version}';
      final reassembler = transmitted
          ? _trafficTxReassembler
          : _trafficRxReassembler;
      final bytes = reassembler.add(
        peer: packet.frame.source.toString(),
        fragment: fragment,
        now: DateTime.now().toUtc(),
      );
      final metadata =
          'txn=${fragment.transactionId} | fragment=${fragment.index + 1}/${fragment.total}';
      if (bytes == null) {
        return 'DATA | $metadata | profile=$profile';
      }
      final decoded = _openQspCodec.decode(bytes);
      return '${_describeOpenQspObject(decoded.object)} | $metadata | profile=$profile';
    } on Object {
      return 'unrecognized OpenQSP data';
    }
  }

  static String _describeOpenQspObject(OpenQspFrameObject object) => switch (object) {
    OpenQspSendMessage(:final recipient, :final body) =>
      'SEND_MESSAGE to=$recipient body="$body"',
    OpenQspGetNewMessages(:final since, :final max) =>
      'GET_NEW_MESSAGES since=$since max=$max',
    OpenQspGetNewBulletins(:final since, :final max) =>
      'GET_NEW_BULLETINS since=$since max=$max',
    OpenQspGetBulletin(:final sequence) => 'GET_BULLETIN sequence=$sequence',
    OpenQspGetCapabilities() => 'GET_CAPABILITIES',
    OpenQspMessage(:final author, :final recipient, :final body, :final sequence) =>
      'MESSAGE seq=$sequence from=$author to=$recipient body="$body"',
    OpenQspBulletinHeader(:final author, :final title, :final sequence) =>
      'BULLETIN_HEADER seq=$sequence from=$author title="$title"',
    OpenQspBulletin(:final author, :final title, :final body, :final sequence) =>
      'BULLETIN seq=$sequence from=$author title="$title" body="$body"',
    OpenQspEnd(:final returnedCount, :final hasMore, :final nextSince) =>
      'END returned=$returnedCount next=$nextSince more=${hasMore ? 'yes' : 'no'}',
    OpenQspStored() => 'STORED',
    OpenQspError(:final errorCode, :final detail) =>
      'ERROR code=$errorCode${detail.isEmpty ? '' : ' detail="$detail"'}',
    OpenQspCapabilities(:final protocolVersion, :final capabilities) =>
      'CAPABILITIES protocol=$protocolVersion mask=$capabilities',
  };

  static String _humanizeAprsUnknown(AprsUnknown packet) {
    final info = packet.frame.informationText;
    if (info.isEmpty) return '(empty APRS payload)';
    return switch (packet.typeIdentifier) {
      '!' || '=' => _humanizePosition(info.substring(1)),
      '/' || '@' => info.length > 8
          ? _humanizePosition(info.substring(8))
          : _singleLine(info),
      '_' => _humanizeWeather(info.substring(1)),
      '>' => 'status: ${_singleLine(info.substring(1))}',
      'T' => 'telemetry: ${_singleLine(info.substring(1))}',
      ';' => 'object: ${_singleLine(info.substring(1))}',
      _ => _singleLine(info),
    };
  }

  static String _humanizePosition(String payload) {
    final match = RegExp(
      r'^(\d{2})(\d{2}\.\d{2})([NS])(.)(\d{3})(\d{2}\.\d{2})([EW])(.)(.*)$',
    ).firstMatch(payload);
    if (match != null) {
      final latDegrees = int.parse(match.group(1)!);
      final latMinutes = double.parse(match.group(2)!);
      final lonDegrees = int.parse(match.group(5)!);
      final lonMinutes = double.parse(match.group(6)!);
      var latitude = latDegrees + latMinutes / 60;
      var longitude = lonDegrees + lonMinutes / 60;
      if (match.group(3) == 'S') latitude = -latitude;
      if (match.group(7) == 'W') longitude = -longitude;
      final comment = match.group(9) ?? '';
      final weather = _weatherFields(comment);
      final suffix = weather.isNotEmpty
          ? ' · $weather'
          : comment.isEmpty
          ? ''
          : ' · ${_singleLine(comment)}';
      return 'lat ${latitude.toStringAsFixed(5)}, '
          'lon ${longitude.toStringAsFixed(5)}$suffix';
    }

    final compressed = _humanizeCompressedPosition(payload);
    return compressed ?? 'position data: ${_singleLine(payload)}';
  }

  static String? _humanizeCompressedPosition(String payload) {
    if (payload.length < 10) return null;
    int? decode(String value) {
      var result = 0;
      for (final unit in value.codeUnits) {
        if (unit < 33 || unit > 123) return null;
        result = result * 91 + (unit - 33);
      }
      return result;
    }

    final y = decode(payload.substring(1, 5));
    final x = decode(payload.substring(5, 9));
    if (y == null || x == null) return null;
    final latitude = 90 - y / 380926.0;
    final longitude = -180 + x / 190463.0;
    if (latitude.abs() > 90 || longitude.abs() > 180) return null;
    final comment = payload.length > 10 ? _singleLine(payload.substring(10)) : '';
    final suffix = comment.isEmpty ? '' : ' · $comment';
    return 'lat ${latitude.toStringAsFixed(5)}, '
        'lon ${longitude.toStringAsFixed(5)}$suffix';
  }

  static String _humanizeWeather(String payload) {
    var data = payload;
    final timestamp = RegExp(r'^\d{6}[zZhH/]').firstMatch(data);
    if (timestamp != null) data = data.substring(timestamp.end);
    final fields = _weatherFields(data);
    return fields.isEmpty ? 'weather data: ${_singleLine(payload)}' : fields;
  }

  static String _weatherFields(String data) {
    final parts = <String>[];
    final temperature = RegExp(r't(-?\d{3})').firstMatch(data);
    if (temperature != null) {
      final fahrenheit = int.tryParse(temperature.group(1)!);
      if (fahrenheit != null) {
        final celsius = (fahrenheit - 32) * 5 / 9;
        parts.add('temperature ${celsius.toStringAsFixed(1)} °C (${fahrenheit} °F)');
      }
    }
    final humidity = RegExp(r'h(\d{2})').firstMatch(data);
    if (humidity != null) {
      final value = humidity.group(1) == '00' ? 100 : int.parse(humidity.group(1)!);
      parts.add('humidity $value%');
    }
    final pressure = RegExp(r'b(\d{5})').firstMatch(data);
    if (pressure != null) {
      parts.add('pressure ${(int.parse(pressure.group(1)!) / 10).toStringAsFixed(1)} hPa');
    }
    final wind = RegExp(r'c(\d{3})s(\d{3})').firstMatch(data);
    if (wind != null) {
      parts.add('wind ${int.parse(wind.group(1)!)}° at ${int.parse(wind.group(2)!)} kt');
    }
    final gust = RegExp(r'g(\d{3})').firstMatch(data);
    if (gust != null) parts.add('gust ${int.parse(gust.group(1)!)} kt');
    return parts.join(', ');
  }

  String _trafficVia(AprsPacket packet, {required bool transmitted}) {
    if (transmitted) return 'RF TX';

    final parts = <String>[];
    if (packet.igate case final igate?) {
      parts.add('IGATE $igate');
    }
    if (packet.thirdPartyRoute.isNotEmpty) {
      parts.add('APRS VIA ${packet.thirdPartyRoute.join(',')}');
    }

    final rfPath = packet.rfPath.isNotEmpty
        ? packet.rfPath
        : packet.frame.digipeaters.map((address) => address.pathText).toList();
    if (rfPath.isNotEmpty) {
      parts.add('RF VIA ${rfPath.join(',')}');
    }

    // A missing AX.25 path only means no repeated-via addresses were present
    // in the frame received by the TNC. Do not infer RF-direct reception.
    return parts.isEmpty ? 'RF' : parts.join(' | ');
  }

  void _addConsoleEntry(AprsConsoleEntry entry) {
    _aprsConsoleEntries.add(entry);
    if (_aprsConsoleEntries.length > _maximumConsoleEntries) {
      _aprsConsoleEntries.removeRange(
        0,
        _aprsConsoleEntries.length - _maximumConsoleEntries,
      );
    }
  }

  void _recordTraffic(AprsPacket packet, {required bool transmitted}) {
    final source = packet.frame.source.toString();
    final destination = switch (packet) {
      AprsTextMessage(:final addressee) => addressee,
      AprsAck(:final addressee) => addressee,
      AprsReject(:final addressee) => addressee,
      AprsUnknown() || AprsInvalid() => packet.frame.destination.toString(),
    };
    final content = _singleLine(
      _trafficContent(packet, transmitted: transmitted),
    );
    _addConsoleEntry(
      AprsConsoleEntry(
        timestamp: DateTime.now(),
        direction: transmitted
            ? AprsConsoleDirection.tx
            : AprsConsoleDirection.rx,
        source: source,
        destination: destination,
        via: _trafficVia(packet, transmitted: transmitted),
        type: _trafficType(packet),
        content: content,
      ),
    );
  }

  void _debugTraffic(AprsPacket packet, {required bool transmitted}) {
    final color = transmitted
        ? _ansiRed
        : _isLocalAprsPacket(packet)
        ? _ansiGreen
        : _ansiBlue;
    final source = packet.frame.source;
    final destination = switch (packet) {
      AprsTextMessage(:final addressee) => addressee,
      AprsAck(:final addressee) => addressee,
      AprsReject(:final addressee) => addressee,
      AprsUnknown() || AprsInvalid() => packet.frame.destination.toString(),
    };
    final content = _singleLine(
      _trafficContent(packet, transmitted: transmitted),
    );
    final ingress = transmitted ? '' : ' | ${_trafficVia(packet, transmitted: false)}';
    _debugColor(
      '${transmitted ? 'TX' : 'RX'} $source -> $destination$ingress | '
      '${_trafficType(packet)} | $content',
      color,
    );
  }

  void _recordOtherAx25(Ax25Frame frame, {required bool transmitted}) {
    final via = transmitted
        ? 'RF TX'
        : frame.digipeaters.isEmpty
        ? 'RF'
        : 'RF VIA ${frame.digipeaters.map((address) => address.pathText).join(',')}';
    _addConsoleEntry(
      AprsConsoleEntry(
        timestamp: DateTime.now(),
        direction: AprsConsoleDirection.other,
        source: frame.source.toString(),
        destination: frame.destination.toString(),
        via: via,
        type: 'AX25',
        content: _singleLine(frame.informationText),
      ),
    );
  }

  void _decodeAx25(List<int> payload) {
    try {
      final frame = _ax25Decoder.decode(payload);
      rxAx25Frames++;
      _ax25Activity.insert(0, _describeAx25(frame));
      if (_ax25Activity.length > 10) _ax25Activity.removeLast();
      _decodeAprs(frame);
    } on Ax25DecodeException catch (error) {
      ax25DecodeErrors++;
      _debugColor('AX.25 decode error: ${error.message}', _ansiRed);
    }
  }

  void _decodeAprs(Ax25Frame frame) {
    final packet = _aprsParser.parse(frame);
    if (packet == null) {
      _recordOtherAx25(frame, transmitted: false);
      _debugColor(
        'RX ${frame.source} -> ${frame.destination} | RF | AX25 | '
        '${_singleLine(frame.informationText)}',
        _ansiBlue,
      );
      return;
    }
    rxAprsPackets++;
    if (packet is AprsInvalid) {
      aprsParseErrors++;
      _recordTraffic(packet, transmitted: false);
      _debugTraffic(packet, transmitted: false);
      return;
    }
    switch (packet) {
      case AprsTextMessage():
        aprsMessages++;
        if (_isOpenQspResponse(packet)) {
          openQspRxPackets++;
          lastValidOpenQspRx = DateTime.now().toUtc();
          if (packet.igate case final igate?) {
            lastOpenQspIgate = igate.toString();
          }
          // OpenQSP transaction reliability is handled below the Core by the
          // burst-repair shim. Never emit native APRS ackNN for Q1/Q2 data.
          _decodeOpenQsp(packet);
        }
        break;
      case AprsAck():
        aprsAcks++;
        break;
      case AprsReject():
        aprsRejects++;
        break;
      case AprsUnknown():
        break;
      case AprsInvalid():
        break;
    }
    _aprsActivity.insert(0, _describeAprs(packet));
    if (_aprsActivity.length > 10) _aprsActivity.removeLast();
    _recordTraffic(packet, transmitted: false);
    _debugTraffic(packet, transmitted: false);
  }

  bool _isOpenQspResponse(AprsTextMessage message) {
    final call = sourceCallsign;
    if (call == null || message.frame.source.callsign != openQspAprsAddressee) {
      return false;
    }
    final localAddressee = aprsSsid == 0 ? call : '$call-$aprsSsid';
    return message.addressee == localAddressee;
  }

  static int? _messageSequenceFromFirstFragment(OpenQspAprsFragment fragment) {
    if (fragment.index != 0) return null;
    List<int> prefix;
    if (fragment.version == 2) {
      final raw = fragment.rawData;
      if (raw == null) return null;
      prefix = raw;
    } else {
      try {
        final padding = (4 - fragment.data.length % 4) % 4;
        prefix = base64Url.decode(
          fragment.data.padRight(fragment.data.length + padding, '='),
        );
      } on Object {
        return null;
      }
    }
    if (prefix.length < 8 || prefix[1] != OpenQspOperation.message.code) {
      return null;
    }
    final sequence = prefix[4] * 0x1000000 +
        prefix[5] * 0x10000 +
        prefix[6] * 0x100 +
        prefix[7];
    return sequence == 0 ? null : sequence;
  }

  void _decodeOpenQsp(AprsTextMessage message) {
    try {
      final fragment = parseFragment(message.text);
      openQspFragmentsRx++;
      final now = DateTime.now().toUtc();
      _completedOpenQspTransactions.removeWhere(
        (_, completed) =>
            now.difference(completed.completedAt) >= openQspAprsDefaultTtl,
      );
      final transactionKey =
          '${message.frame.source}|${fragment.transactionId}';
      final firstSequence = _messageSequenceFromFirstFragment(fragment);
      if (firstSequence != null) {
        _incomingMessageTransactions[transactionKey] = firstSequence;
      }
      final messageSequence = _incomingMessageTransactions[transactionKey];
      if (messageSequence != null) {
        openQspMessageFragmentsRx++;
        lastOpenQspMessageFragmentSequence = messageSequence;
      }
      final bytes = _reassembler.add(
        peer: message.frame.source.toString(),
        fragment: fragment,
        now: now,
      );
      if (bytes == null) return;

      final completed = _completedOpenQspTransactions[transactionKey];
      if (completed != null && listEquals(completed.bytes, bytes)) {
        _incomingMessageTransactions.remove(transactionKey);
        return;
      }

      final decoded = _openQspCodec.decode(bytes);
      _incomingMessageTransactions.remove(transactionKey);
      openQspFramesRx++;
      lastOpenQspObject = decoded.object;
      lastValidOpenQspRx = now;
      _completedOpenQspTransactions[transactionKey] =
          _CompletedOpenQspTransaction(
            completedAt: now,
            bytes: List<int>.unmodifiable(bytes),
          );
      if (decoded.object is OpenQspCapabilities &&
          openQspCheckState == OpenQspCheckState.waiting) {
        _finishOpenQspCheck(OpenQspCheckState.available);
      }
    } on Object catch (error) {
      openQspErrors++;
      _debugColor('OpenQSP APRS RX error: $error', _ansiRed);
    }
  }

  Future<void> setAprsSsid(int value) async {
    if (value < 0 || value > 15) return;
    aprsSsid = value;
    if (storage is AprsSsidStorage) {
      await (storage as AprsSsidStorage).writeSsid(value);
    }
    _notify();
  }

  void _cancelOpenQspCheckTimers() {
    _openQspTimer?.cancel();
    _openQspTimer = null;
    _openQspCountdownTimer?.cancel();
    _openQspCountdownTimer = null;
  }

  void _finishOpenQspCheck(OpenQspCheckState result) {
    _cancelOpenQspCheckTimers();
    _openQspCheckDeadline = null;
    openQspCheckState = result;
    _notify();
  }

  Future<String> _allocateOpenQspTransactionId() async {
    final current = _transactionSequence % _transactionSequenceModulo;
    final next = (current + 1) % _transactionSequenceModulo;
    if (storage is OpenQspTransactionSequenceStorage) {
      await (storage as OpenQspTransactionSequenceStorage)
          .writeTransactionSequence(next);
    }
    _transactionSequence = next;
    return current.toRadixString(36).toUpperCase().padLeft(3, '0');
  }

  Future<void> _sendCapabilitiesRequest(
    String call,
    List<OpenQspAprsFragment> fragments,
  ) async {
    for (final fragment in fragments) {
      final information = _messageEncoder.encode(
        addressee: openQspAprsAddressee,
        body: fragment.body,
      );
      final ax25 = _ax25Encoder.encodeUi(
        destination: const Ax25Address(
          callsign: openQspAprsTocall,
          ssid: 0,
          hasBeenRepeated: false,
          isLast: false,
        ),
        source: Ax25Address(
          callsign: call,
          ssid: aprsSsid,
          hasBeenRepeated: false,
          isLast: true,
        ),
        information: information,
      );
      await sendKiss(KissFrame(port: 0, command: 0, payload: ax25));
    }
  }

  Future<void> checkOpenQsp() async {
    if (!kissReady) return;
    final call = sourceCallsign;
    if (call == null || !RegExp(r'^[A-Z0-9]{1,6}$').hasMatch(call)) {
      _finishOpenQspCheck(OpenQspCheckState.error);
      return;
    }

    _cancelOpenQspCheckTimers();
    openQspCheckState = OpenQspCheckState.waiting;
    _openQspCheckDeadline = DateTime.now().add(openQspTimeout);
    lastValidOpenQspRx = null;
    lastOpenQspIgate = null;
    _notify();

    try {
      final core = _openQspCodec.encode(const OpenQspGetCapabilities());
      final transactionId = await _allocateOpenQspTransactionId();
      final fragments = fragmentFrame(core, transactionId);

      await _sendCapabilitiesRequest(call, fragments);
      if (openQspCheckState != OpenQspCheckState.waiting) return;

      // Retransmission cadence belongs exclusively to the burst-repair layer.
      // This controller only owns the overall grace period and UI countdown.
      _openQspCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (openQspCheckState == OpenQspCheckState.waiting) _notify();
      });
      _openQspTimer = Timer(openQspTimeout, () {
        if (openQspCheckState == OpenQspCheckState.waiting) {
          _finishOpenQspCheck(OpenQspCheckState.noResponse);
        }
      });
    } on Object catch (error) {
      _finishOpenQspCheck(OpenQspCheckState.error);
      _debugColor('OpenQsp APRS TX error: $error', _ansiRed);
    }
  }

  static String _describeAprs(AprsPacket packet) {
    final source = packet.frame.source;
    final oqsp = packet.isForOpenQsp ? '[OQSP] ' : '';
    return switch (packet) {
      AprsTextMessage(:final addressee, :final text, :final messageId) =>
        '${oqsp}MSG  $source → $addressee\n'
            'ID: ${messageId ?? '-'}\nTEXT: $text',
      AprsAck(:final addressee, :final messageId) =>
        '${oqsp}ACK  $source → $addressee\nID: $messageId',
      AprsReject(:final addressee, :final messageId) =>
        '${oqsp}REJ  $source → $addressee\nID: $messageId',
      AprsUnknown(:final typeIdentifier) =>
        'APRS  $source\nTYPE: $typeIdentifier\nINFO: ${packet.frame.informationText}',
      AprsInvalid() => '',
    };
  }

  static String _describeAx25(Ax25Frame frame) {
    final via = frame.digipeaters.isEmpty
        ? '-'
        : frame.digipeaters.map((address) => address.pathText).join(',');
    final pid = frame.pid == null
        ? '-'
        : frame.pid!.toRadixString(16).padLeft(2, '0').toUpperCase();
    final control = frame.control
        .toRadixString(16)
        .padLeft(2, '0')
        .toUpperCase();
    return 'SRC: ${frame.source}  DST: ${frame.destination}\n'
        'VIA: $via  CTRL: $control  PID: $pid\n'
        'INFO: ${frame.informationText}';
  }

  Future<void> sendKiss(KissFrame frame) async {
    await _kissTransport.send(frame);
    txKissFrames++;
    _activity.insert(0, 'TX  ${_hex(const KissEncoder().encode(frame))}');
    if (_activity.length > 10) _activity.removeLast();
    if (frame.port == 0 && frame.command == 0) {
      try {
        final ax25 = _ax25Decoder.decode(frame.payload);
        final aprs = _aprsParser.parse(ax25);
        if (aprs != null) {
          _recordTraffic(aprs, transmitted: true);
          if (kDebugMode) _debugTraffic(aprs, transmitted: true);
        } else {
          _recordOtherAx25(ax25, transmitted: true);
          if (kDebugMode) {
            _debugColor(
              'TX ${ax25.source} -> ${ax25.destination} | AX25 | '
              '${_singleLine(ax25.informationText)}',
              _ansiRed,
            );
          }
        }
      } on Object {
        // TX diagnostics must never affect transport behavior.
      }
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    if (state != TncConnectionState.loading) return;
    device = await storage.read();
    if (storage is AprsSsidStorage) {
      aprsSsid = await (storage as AprsSsidStorage).readSsid();
    }
    if (storage is OpenQspTransactionSequenceStorage) {
      _transactionSequence =
          await (storage as OpenQspTransactionSequenceStorage)
              .readTransactionSequence();
    }
    state = device == null
        ? TncConnectionState.notConfigured
        : TncConnectionState.configured;
    _notify();
  }

  Future<List<TncDevice>?> loadDevices() async {
    failure = null;
    try {
      return await service.bondedDevices();
    } on TncServiceException catch (error) {
      _setError(error.failure);
    } catch (_) {
      _setError(TncFailure.unknown);
    }
    return null;
  }

  Future<void> select(TncDevice selected) async {
    await disconnect();
    await storage.write(selected);
    device = selected;
    failure = null;
    state = TncConnectionState.configured;
    _notify();
  }

  Future<void> connect() async {
    final selected = device;
    if (selected == null) return;
    failure = null;
    state = TncConnectionState.connecting;
    _notify();
    try {
      await service.connect(selected);
      if (_disposed) return;
      state = TncConnectionState.connected;
      _notify();
    } on TncServiceException catch (error) {
      if (_disposed) return;
      _setError(error.failure);
    } catch (_) {
      if (_disposed) return;
      _setError(TncFailure.unknown);
    }
  }

  Future<void> disconnect() async {
    _cancelOpenQspCheckTimers();
    _openQspCheckDeadline = null;
    openQspCheckState = OpenQspCheckState.notChecked;
    await service.disconnect();
    if (_disposed) return;
    if (state == TncConnectionState.connected ||
        state == TncConnectionState.connecting) {
      state = device == null
          ? TncConnectionState.notConfigured
          : TncConnectionState.configured;
      failure = null;
      _notify();
    }
  }

  Future<void> forget() async {
    _cancelOpenQspCheckTimers();
    _openQspCheckDeadline = null;
    openQspCheckState = OpenQspCheckState.notChecked;
    await service.disconnect();
    await storage.clear();
    device = null;
    failure = null;
    state = TncConnectionState.notConfigured;
    _notify();
  }

  void _setError(TncFailure value) {
    _cancelOpenQspCheckTimers();
    _openQspCheckDeadline = null;
    openQspCheckState = OpenQspCheckState.error;
    failure = value;
    state = TncConnectionState.error;
    _notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelOpenQspCheckTimers();
    unawaited(_byteSubscription.cancel());
    unawaited(_frameSubscription.cancel());
    unawaited(_connectionLossSubscription.cancel());
    unawaited(_kissTransport.close());
    unawaited(service.disconnect());
    super.dispose();
  }
}

final class _CompletedOpenQspTransaction {
  const _CompletedOpenQspTransaction({
    required this.completedAt,
    required this.bytes,
  });

  final DateTime completedAt;
  final List<int> bytes;
}
