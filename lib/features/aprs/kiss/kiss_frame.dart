import 'dart:typed_data';

/// A KISS command byte and its uninterpreted payload.
final class KissFrame {
  KissFrame({required this.port, required this.command, required List<int> payload})
    : assert(port >= 0 && port <= 0x0f),
      assert(command >= 0 && command <= 0x0f),
      payload = Uint8List.fromList(payload);

  factory KissFrame.fromCommandByte(int commandByte, List<int> payload) =>
      KissFrame(
        port: (commandByte >> 4) & 0x0f,
        command: commandByte & 0x0f,
        payload: payload,
      );

  final int port;
  final int command;
  final Uint8List payload;

  int get commandByte => (port << 4) | command;
}
