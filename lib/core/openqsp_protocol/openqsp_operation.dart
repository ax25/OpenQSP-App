enum OpenQspOperation {
  sendMessage(0x01),
  getNewMessages(0x02),
  getNewBulletins(0x03),
  getBulletin(0x04),
  getCapabilities(0x05),
  message(0x40),
  bulletinHeader(0x41),
  bulletin(0x42),
  end(0x43),
  stored(0x44),
  error(0x45),
  capabilities(0x46);

  const OpenQspOperation(this.code);
  final int code;

  static OpenQspOperation? fromCode(int code) {
    for (final operation in values) {
      if (operation.code == code) return operation;
    }
    return null;
  }
}
