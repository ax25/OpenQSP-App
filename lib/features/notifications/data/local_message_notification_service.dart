import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalMessageNotificationService {
  LocalMessageNotificationService._();

  static final LocalMessageNotificationService instance =
      LocalMessageNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> Function(String peer)? _tapHandler;
  String? _pendingPeer;
  bool _initialized = false;
  bool _supported = true;
  int _nextId = 1;

  Future<void> initialize() async {
    if (_initialized) return;

    _supported = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    if (!_supported) {
      _initialized = true;
      return;
    }

    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
      );

      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (response) {
          final peer = response.payload?.trim().toUpperCase();
          if (peer == null || peer.isEmpty) return;
          _dispatchTap(peer);
        },
      );

      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();

      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);

      final launch = await _plugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload?.trim().toUpperCase();
      if (launch?.didNotificationLaunchApp == true &&
          payload != null &&
          payload.isNotEmpty) {
        _pendingPeer = payload;
      }
    } on Object catch (error) {
      debugPrint('Local notification initialization failed: $error');
      _supported = false;
    } finally {
      _initialized = true;
    }
  }

  void setTapHandler(Future<void> Function(String peer)? handler) {
    _tapHandler = handler;
    final peer = _pendingPeer;
    if (handler != null && peer != null) {
      _pendingPeer = null;
      unawaited(handler(peer));
    }
  }

  Future<void> showIncomingMessage({
    required String peer,
    required String body,
  }) async {
    await initialize();
    if (!_supported) return;

    final normalizedPeer = peer.trim().toUpperCase();
    if (normalizedPeer.isEmpty) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'openqsp_messages',
        'OpenQSP messages',
        channelDescription: 'Notifications for new OpenQSP messages',
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_notification',
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );

    try {
      await _plugin.show(
        id: _nextId++,
        title: 'Message from $normalizedPeer',
        body: body,
        notificationDetails: details,
        payload: normalizedPeer,
      );
    } on Object catch (error) {
      debugPrint('Unable to show local notification: $error');
    }
  }

  void _dispatchTap(String peer) {
    final handler = _tapHandler;
    if (handler == null) {
      _pendingPeer = peer;
      return;
    }
    unawaited(handler(peer));
  }
}
