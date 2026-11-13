import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpulse_android/app.dart';
import 'package:taskpulse_android/models.dart';
import 'package:taskpulse_android/screens/team_screens.dart';
import 'package:taskpulse_android/state.dart';
import 'package:taskpulse_android/theme.dart';

class _TestActiveTeamController extends ActiveTeamController {
  @override
  Team? build() => const Team(id: 'team-1', name: 'فريق Taskaty');
}

void main() {
  const team = Team(id: 'team-1', name: 'فريق Taskaty');
  const dashboard = <String, dynamic>{
    'summary': {
      'totalTasks': 23,
      'activeTasks': 8,
      'completedTasks': 12,
      'overdueTasks': 3,
      'averageCompletionSeconds': 5400,
      'onTimeCompletionPercent': 86,
    },
    'members': [
      {
        'displayName': 'عضو فريق طويل الاسم لاختبار التفاف النص',
        'completedCount': 8,
        'overdueCount': 1,
        'onTimeCompletionPercent': 82,
      },
    ],
    'approaching': <Map<String, dynamic>>[],
  };

  testWidgets('dashboard statistics fit phone and tablet viewports', (
    tester,
  ) async {
    const sizes = [Size(320, 568), Size(393, 852), Size(800, 1024)];
    for (final size in sizes) {
      for (final locale in const [Locale('ar'), Locale('en')]) {
        for (final textScale in const [1.0, 1.6]) {
          for (final brightness in Brightness.values) {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = size;
            final container = ProviderContainer(
              overrides: [
                activeTeamProvider.overrideWith(_TestActiveTeamController.new),
                teamsProvider.overrideWith((ref) async => const [team]),
                dashboardProvider(
                  team.id,
                ).overrideWith((ref) async => dashboard),
                signedInUserProvider.overrideWithValue(null),
              ],
            );

            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: container,
                child: MaterialApp(
                  locale: locale,
                  supportedLocales: const [Locale('ar'), Locale('en')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: buildTaskatyTheme(),
                  darkTheme: buildTaskatyTheme(brightness: Brightness.dark),
                  themeMode: brightness == Brightness.dark
                      ? ThemeMode.dark
                      : ThemeMode.light,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(textScale)),
                    child: child!,
                  ),
                  home: const AppShell(
                    location: '/home',
                    child: DashboardScreen(),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(
              tester.takeException(),
              isNull,
              reason:
                  'dashboard at $size, ${locale.languageCode}, scale $textScale, $brightness',
            );

            await tester.pumpWidget(const SizedBox.shrink());
            container.dispose();
          }
        }
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
