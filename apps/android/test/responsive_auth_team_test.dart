import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpulse_android/screens/auth_screens.dart';
import 'package:taskpulse_android/screens/team_screens.dart';
import 'package:taskpulse_android/theme.dart';

void main() {
  testWidgets('login and team onboarding remain scrollable at narrow sizes', (
    tester,
  ) async {
    const viewports = [Size(320, 568), Size(393, 852), Size(800, 1024)];
    for (final viewport in viewports) {
      for (final locale in const [Locale('ar'), Locale('en')]) {
        for (final scale in const [1.0, 1.6]) {
          for (final keyboardVisible in const [false, true]) {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = viewport;
            for (final screen in const ['login', 'onboarding']) {
              await tester.pumpWidget(
                ProviderScope(
                  child: MaterialApp(
                    locale: locale,
                    supportedLocales: const [Locale('ar'), Locale('en')],
                    localizationsDelegates:
                        GlobalMaterialLocalizations.delegates,
                    theme: buildTaskatyTheme(),
                    darkTheme: buildTaskatyTheme(brightness: Brightness.dark),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(scale),
                        viewInsets: keyboardVisible
                            ? const EdgeInsets.only(bottom: 300)
                            : EdgeInsets.zero,
                      ),
                      child: child!,
                    ),
                    home: screen == 'login'
                        ? const LoginScreen()
                        : const TeamOnboardingScreen(),
                  ),
                ),
              );
              await tester.pumpAndSettle();

              expect(
                tester.takeException(),
                isNull,
                reason:
                    '$screen layout at $viewport, ${locale.languageCode}, scale $scale, keyboard $keyboardVisible',
              );
            }
          }
        }
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
