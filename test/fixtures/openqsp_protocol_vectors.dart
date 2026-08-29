import 'package:openqsp_app/core/openqsp_protocol/openqsp_protocol.dart';

final List<({OpenQspFrameObject object, List<int> bytes})> openQspProtocolVectors = [
  (object: const OpenQspGetCapabilities(), bytes: [0x01, 0x05, 0x00, 0x00]),
  (object: const OpenQspCapabilities(protocolVersion: 1, capabilities: 0x0f), bytes: [0x01, 0x46, 0x00, 0x05, 0x01, 0, 0, 0, 0x0f]),
  (object: const OpenQspStored(), bytes: [0x01, 0x44, 0x00, 0x00]),
  (object: const OpenQspGetNewMessages(since: 0, max: 20), bytes: [0x01, 0x02, 0x00, 0x05, 0, 0, 0, 0, 20]),
  (object: const OpenQspSendMessage(createdAt: 1, recipient: 'EA3GNU', body: 'HI'), bytes: [0x01, 0x01, 0x00, 0x0e, 0, 0, 0, 1, 6, 0x45, 0x41, 0x33, 0x47, 0x4e, 0x55, 2, 0x48, 0x49]),
];
