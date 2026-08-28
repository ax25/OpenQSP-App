import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app/app.dart';
import 'core/config/server_config.dart';
import 'core/network/server_status_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  final config = ServerConfig.fromEnvironment();
  runApp(
    OpenQspApp(
      serverStatusClient: InternetServerStatusClient(baseUri: config.baseUri),
    ),
  );
}
