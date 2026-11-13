import 'package:firebase_messaging/firebase_messaging.dart';

import 'notification_adapter_android.dart' if (dart.library.js_interop) 'notification_adapter_web.dart' as platform;

Future<String?> configureNotifications(void Function(String) onTaskTap) => platform.configureNotifications(onTaskTap);
Future<String?> currentNotificationToken() => platform.currentNotificationToken();
Future<void> showForegroundNotification(RemoteMessage message, String title, String body) =>
    platform.showForegroundNotification(message, title, body);
