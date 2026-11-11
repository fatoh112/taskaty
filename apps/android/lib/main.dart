import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.firebaseOptionsPresent) {
    try {
      await Firebase.initializeApp(options: AppConfig.firebaseOptions);
    } catch (_) {
      AppConfig.firebaseInitError = 'Firebase initialization failed. Check the application configuration.';
    }
  }
  runApp(const ProviderScope(child: TaskatyApp()));
}
