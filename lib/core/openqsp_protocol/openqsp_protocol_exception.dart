sealed class OpenQspProtocolException implements Exception {
  const OpenQspProtocolException(this.message);
  final String message;
  @override String toString() => '$runtimeType: $message';
}
final class OpenQspUnsupportedVersionException extends OpenQspProtocolException { const OpenQspUnsupportedVersionException(super.message); }
final class OpenQspUnknownOperationException extends OpenQspProtocolException { const OpenQspUnknownOperationException(super.message); }
final class OpenQspPayloadLengthException extends OpenQspProtocolException { const OpenQspPayloadLengthException(super.message); }
final class OpenQspInvalidFieldException extends OpenQspProtocolException { const OpenQspInvalidFieldException(super.message); }
final class OpenQspFrameTooLargeException extends OpenQspProtocolException { const OpenQspFrameTooLargeException(super.message); }
