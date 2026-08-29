const int openQspVersion = 0x01;
const int openQspHeaderLength = 4;
const int openQspMaxPayloadLength = 255;
const int openQspMaxFrameLength = 259;
const int openQspFlagUnsolicited = 0x01;

abstract final class OpenQspCapability {
  static const int privateMessaging = 0x00000001;
  static const int bulletinListing = 0x00000002;
  static const int bulletinRetrieval = 0x00000004;
  static const int proactivePrivateMessageDelivery = 0x00000008;
}
