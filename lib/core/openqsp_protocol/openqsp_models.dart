import 'openqsp_constants.dart';
import 'openqsp_error_code.dart';
import 'openqsp_operation.dart';

sealed class OpenQspFrameObject { const OpenQspFrameObject(); }
final class OpenQspSendMessage extends OpenQspFrameObject { const OpenQspSendMessage({required this.createdAt, required this.recipient, required this.body}); final int createdAt; final String recipient, body; }
final class OpenQspGetNewMessages extends OpenQspFrameObject { const OpenQspGetNewMessages({required this.since, required this.max}); final int since, max; }
final class OpenQspGetNewBulletins extends OpenQspFrameObject { const OpenQspGetNewBulletins({required this.since, required this.max}); final int since, max; }
final class OpenQspGetBulletin extends OpenQspFrameObject { const OpenQspGetBulletin(this.sequence); final int sequence; }
final class OpenQspGetCapabilities extends OpenQspFrameObject { const OpenQspGetCapabilities(); }
final class OpenQspMessage extends OpenQspFrameObject {
  const OpenQspMessage({
    required this.sequence,
    this.conversationSequence = 1,
    required this.createdAt,
    required this.author,
    required this.recipient,
    required this.body,
  });
  final int sequence, conversationSequence, createdAt;
  final String author, recipient, body;
}
final class OpenQspBulletinHeader extends OpenQspFrameObject { const OpenQspBulletinHeader({required this.sequence, required this.createdAt, required this.author, required this.title}); final int sequence, createdAt; final String author, title; }
final class OpenQspBulletin extends OpenQspFrameObject { const OpenQspBulletin({required this.sequence, required this.createdAt, required this.author, required this.title, required this.body}); final int sequence, createdAt; final String author, title, body; }
final class OpenQspEnd extends OpenQspFrameObject { const OpenQspEnd({required this.requestOperation, required this.returnedCount, required this.nextSince, required this.hasMore}); final OpenQspOperation requestOperation; final int returnedCount, nextSince; final bool hasMore; }
final class OpenQspStored extends OpenQspFrameObject { const OpenQspStored(); }
final class OpenQspError extends OpenQspFrameObject { const OpenQspError({required this.requestOperation, required this.errorCode, this.detail = ''}); final int requestOperation; final OpenQspErrorCode errorCode; final String detail; }
final class OpenQspCapabilities extends OpenQspFrameObject {
  const OpenQspCapabilities({required this.protocolVersion, required this.capabilities});
  final int protocolVersion, capabilities;
  bool supports(int capability) => capabilities & capability != 0;
  bool get supportsPrivateMessaging => supports(OpenQspCapability.privateMessaging);
}

final class OpenQspDecodedFrame {
  const OpenQspDecodedFrame({required this.version, required this.operation, required this.flags, required this.object});
  final int version, flags; final OpenQspOperation operation; final OpenQspFrameObject object;
  bool get unsolicited => flags & openQspFlagUnsolicited != 0;
}
