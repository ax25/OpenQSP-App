enum OpenQspErrorCode {
  invalidFrame(0x01), unsupportedVersion(0x02), unknownOperation(0x03),
  invalidField(0x04), invalidCursor(0x05), unauthorized(0x06),
  notFound(0x07), tooLarge(0x08), busy(0x09), internalError(0x0a),
  rejected(0x0b);

  const OpenQspErrorCode(this.code);
  final int code;
  static OpenQspErrorCode? fromCode(int code) {
    for (final value in values) { if (value.code == code) return value; }
    return null;
  }
}
