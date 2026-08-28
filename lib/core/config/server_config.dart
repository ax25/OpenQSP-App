import 'package:flutter_dotenv/flutter_dotenv.dart';

class ServerConfig {
  const ServerConfig({
    required this.host,
    required this.port,
    required this.useSsl,
  });

  factory ServerConfig.fromEnvironment(DotEnv environment) {
    final port = int.tryParse(environment.env['OPENQSP_SERVER_PORT'] ?? '');
    final host = environment.env['OPENQSP_SERVER_HOST'];
    if (host == null || host.isEmpty || port == null) {
      throw const FormatException('Invalid OpenQSP server configuration');
    }

    return ServerConfig(
      host: host,
      port: port,
      useSsl:
          (environment.env['OPENQSP_SERVER_SSL'] ?? '').toLowerCase() == 'true',
    );
  }

  final String host;
  final int port;
  final bool useSsl;

  Uri get baseUri => Uri(
    scheme: useSsl ? 'https' : 'http',
    host: host,
    port: port,
  );
}
