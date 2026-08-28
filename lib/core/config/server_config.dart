import 'package:flutter_dotenv/flutter_dotenv.dart';

class ServerConfig {
  const ServerConfig({
    required this.host,
    required this.port,
    required this.useSsl,
  });

  final String host;
  final int port;
  final bool useSsl;

  Uri get baseUri => Uri(
    scheme: useSsl ? 'https' : 'http',
    host: host,
    port: port,
  );

  factory ServerConfig.fromEnvironment() {
    final host = dotenv.env['OPENQSP_SERVER_HOST']?.trim();
    final port = int.tryParse(dotenv.env['OPENQSP_SERVER_PORT'] ?? '');
    final ssl = dotenv.env['OPENQSP_SERVER_SSL']?.trim().toLowerCase();

    if (host == null || host.isEmpty || port == null || port <= 0) {
      throw const FormatException('Invalid OpenQSP server configuration');
    }
    if (ssl != 'true' && ssl != 'false') {
      throw const FormatException('OPENQSP_SERVER_SSL must be true or false');
    }

    return ServerConfig(host: host, port: port, useSsl: ssl == 'true');
  }
}
