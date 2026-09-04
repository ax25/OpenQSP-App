import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app/app.dart';
import 'core/config/server_config.dart';
import 'core/network/server_status_client.dart';
import 'features/auth/data/auth_client.dart';
import 'features/messages/data/internet_messages_realtime_client.dart';
import 'features/messages/data/internet_messages_repository.dart';
import 'features/notifications/data/local_message_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await LocalMessageNotificationService.instance.initialize();
  final config = ServerConfig.fromEnvironment();
  runApp(
    OpenQspApp(
      serverStatusClient: InternetServerStatusClient(baseUri: config.baseUri),
      authClient: InternetAuthClient(baseUri: config.baseUri),
      messagesRepository: InternetMessagesRepository(baseUri: config.baseUri),
      messagesRealtimeFactory: () =>
          InternetMessagesRealtimeClient(baseUri: config.baseUri),
    ),
  );
}
