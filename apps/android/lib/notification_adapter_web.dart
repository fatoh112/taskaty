import 'package:firebase_messaging/firebase_messaging.dart';

import 'config.dart';

Future<String?> configureNotifications(void Function(String) onTaskTap) async {
  if (AppConfig.webVapidKey.isEmpty) return null;
  final settings = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
  if (settings.authorizationStatus != AuthorizationStatus.authorized) return null;
  return FirebaseMessaging.instance.getToken(
    vapidKey: AppConfig.webVapidKey,
    serviceWorkerScriptPath: '/firebase-messaging-sw.js',
  );
}

Future<String?> currentNotificationToken() => AppConfig.webVapidKey.isEmpty
    ? Future.value(null)
    : FirebaseMessaging.instance.getToken(
        vapidKey: AppConfig.webVapidKey,
        serviceWorkerScriptPath: '/firebase-messaging-sw.js',
      );

Future<void> showForegroundNotification(RemoteMessage message, String title, String body) async {}
