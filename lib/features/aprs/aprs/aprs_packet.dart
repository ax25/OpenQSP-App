import '../ax25/ax25_address.dart';
import '../ax25/ax25_frame.dart';

const openQspAprsAddressee = 'OQSP';

sealed class AprsPacket {
  const AprsPacket(this.frame, {this.igate});

  final Ax25Frame frame;
  final Ax25Address? igate;
  String? get addressee => null;
  bool get isForOpenQsp => addressee == openQspAprsAddressee;
}

final class AprsTextMessage extends AprsPacket {
  const AprsTextMessage(
    super.frame, {
    super.igate,
    required this.messageAddressee,
    required this.text,
    this.messageId,
  });

  final String messageAddressee;
  final String text;
  final String? messageId;

  @override
  String get addressee => messageAddressee;
}

final class AprsAck extends AprsPacket {
  const AprsAck(
    super.frame, {
    super.igate,
    required this.messageAddressee,
    required this.messageId,
  });

  final String messageAddressee;
  final String messageId;

  @override
  String get addressee => messageAddressee;
}

final class AprsReject extends AprsPacket {
  const AprsReject(
    super.frame, {
    super.igate,
    required this.messageAddressee,
    required this.messageId,
  });

  final String messageAddressee;
  final String messageId;

  @override
  String get addressee => messageAddressee;
}

/// An APRS data type intentionally not interpreted by this RX-only phase.
final class AprsUnknown extends AprsPacket {
  const AprsUnknown(
    super.frame, {
    super.igate,
    required this.typeIdentifier,
  });

  final String typeIdentifier;
}

/// A UI/F0 frame which looks like APRS but is not safe to interpret.
final class AprsInvalid extends AprsPacket {
  const AprsInvalid(
    super.frame, {
    super.igate,
    required this.reason,
  });

  final String reason;
}
