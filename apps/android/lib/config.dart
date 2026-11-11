import 'package:firebase_core/firebase_core.dart';

class AppConfig {
  const AppConfig._();

  static const apiBaseUrl = String.fromEnvironment('TASKPULSE_API_URL');
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static bool get firebaseOptionsPresent => firebaseApiKey.isNotEmpty && firebaseAppId.isNotEmpty && firebaseProjectId.isNotEmpty && firebaseSenderId.isNotEmpty;
  static String? firebaseInitError;
  static bool get firebaseConfigured => firebaseOptionsPresent && firebaseInitError == null;
  static bool get apiConfigured => apiBaseUrl.startsWith('https://');

  static FirebaseOptions get firebaseOptions => FirebaseOptions(
    apiKey: firebaseApiKey,
    appId: firebaseAppId,
    messagingSenderId: firebaseSenderId,
    projectId: firebaseProjectId,
  );
}
