import 'dart:async';

import '../../../core/openqsp_protocol/openqsp_codec.dart';
import '../../../core/openqsp_protocol/openqsp_models.dart';
import '../aprs/aprs_message_encoder.dart';
import '../ax25/ax25_address.dart';
import '../ax25/ax25_encoder.dart';
import '../data/bluetooth_tnc_service.dart';
import '../data/bluetooth_tnc_storage.dart';
import '../kiss/kiss_frame.dart';
import '../openqsp_carriage/openqsp_aprs_carriage.dart';
import 'tnc_settings_controller.dart';

/// Keeps GET_CAPABILITIES retries tied to the controller's configured retry
/// interval while the normal OpenQSP availability grace period is still open.
///
/// The base controller remains the owner of the 65-second availability timeout
/// and of CAPABILITIES decoding. This class only repeats the exact same Q2
/// transaction until that base state leaves [OpenQspCheckState.waiting].
final class RetryingTncSettingsController extends TncSettingsController {
  RetryingTncSettingsController({
    required super.storage,
    required super.service,
    super.sourceCallsign,
    super.openQspTimeout,
    super.openQspRetryInterval,
  }) {
    addListener(_onControllerChanged);
  }

  static const OpenQspCodec _codec = OpenQspCodec();
  static const AprsMessageEncoder _messageEncoder = AprsMessageEncoder();
  static const Ax25Encoder _ax25Encoder = Ax25Encoder();

  Timer? _capabilitiesRetryTimer;
  bool _disposed = false;

  @override
  Future<void> checkOpenQsp() async {
    _cancelCapabilitiesRetry();
    await super.checkOpenQsp();
    if (_disposed || openQspCheckState != OpenQspCheckState.waiting) return;

    final call = sourceCallsign;
    final transactionId = _latestCapabilitiesTransactionId();
    if (call == null || transactionId == null) return;

    final core = _codec.encode(const OpenQspGetCapabilities());
    final fragments = fragmentFrame(core, transactionId);
    _capabilitiesRetryTimer = Timer.periodic(openQspRetryInterval, (_) {
      if (_disposed || openQspCheckState != OpenQspCheckState.waiting) {
        _cancelCapabilitiesRetry();
        return;
      }
      unawaited(_retryCapabilities(call, fragments));
    });
  }

  String? _latestCapabilitiesTransactionId() {
    final pattern = RegExp(r'GET_CAPABILITIES\s+\|\s+txn=([0-9A-Z]{3})');
    for (final entry in aprsConsoleEntries.reversed) {
      if (entry.direction != AprsConsoleDirection.tx ||
          entry.type != 'OPENQSP') {
        continue;
      }
      final match = pattern.firstMatch(entry.content);
      if (match != null) return match.group(1);
    }
    return null;
  }

  Future<void> _retryCapabilities(
    String call,
    List<OpenQspAprsFragment> fragments,
  ) async {
    if (_disposed || openQspCheckState != OpenQspCheckState.waiting) return;
    try {
      for (final fragment in fragments) {
        if (_disposed || openQspCheckState != OpenQspCheckState.waiting) return;
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
    } on Object {
      // The base controller owns connection/error state. A failed retry is
      // allowed to be followed by the remaining grace-period retries unless
      // the underlying connection reports a real loss.
    }
  }

  void _onControllerChanged() {
    if (openQspCheckState != OpenQspCheckState.waiting) {
      _cancelCapabilitiesRetry();
    }
  }

  void _cancelCapabilitiesRetry() {
    _capabilitiesRetryTimer?.cancel();
    _capabilitiesRetryTimer = null;
  }

  @override
  Future<void> disconnect() async {
    _cancelCapabilitiesRetry();
    await super.disconnect();
  }

  @override
  Future<void> forget() async {
    _cancelCapabilitiesRetry();
    await super.forget();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelCapabilitiesRetry();
    removeListener(_onControllerChanged);
    super.dispose();
  }
}
