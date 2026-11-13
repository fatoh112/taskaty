import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final _notifications = FlutterLocalNotificationsPlugin();

Future<String?> configureNotifications(void Function(String) onTaskTap) async {
  await _notifications.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings('ic_notification')),
    onDidReceiveNotificationResponse: (response) {
      final taskId = response.payload;
      if (taskId != null && taskId.isNotEmpty) onTaskTap(taskId);
    },
  );
  await _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(
    const AndroidNotificationChannel('taskaty_alerts', 'تنبيهات Taskaty', description: 'تحديثات مهام الفريق ومواعيدها', importance: Importance.high),
  );
  final launch = await _notifications.getNotificationAppLaunchDetails();
  final taskId = launch?.didNotificationLaunchApp == true ? launch?.notificationResponse?.payload : null;
  if (taskId != null && taskId.isNotEmpty) onTaskTap(taskId);
  await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
  return FirebaseMessaging.instance.getToken();
}

Future<String?> currentNotificationToken() => FirebaseMessaging.instance.getToken();

Future<void> showForegroundNotification(RemoteMessage message, String title, String body) async {
  await _notifications.show(
    id: message.data['notificationId']?.hashCode ?? message.hashCode,
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(android: AndroidNotificationDetails('taskaty_alerts', 'تنبيهات Taskaty', channelDescription: 'تحديثات مهام الفريق ومواعيدها', importance: Importance.high, priority: Priority.high)),
    payload: message.data['taskId'] as String?,
  );
}
