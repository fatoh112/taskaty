import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpulse_android/app.dart';
import 'package:taskpulse_android/models.dart';
import 'package:taskpulse_android/screens/task_screens.dart';
import 'package:taskpulse_android/state.dart';
import 'package:taskpulse_android/theme.dart';

class _TestActiveTeamController extends ActiveTeamController {
  @override
  Team? build() => const Team(id: 'team-1', name: 'الفريق الرئيسي');
}

void main() {
  const team = Team(id: 'team-1', name: 'فريق Taskaty للاختبار الطويل');
  const query = TaskQuery('team-1');
  final task = TaskItem(
    id: 'task-1',
    teamId: 'team-1',
    title:
        'مراجعة تصميم الصفحة الرئيسية والتأكد من وضوح كل التفاصيل قبل التسليم',
    description:
        'وصف طويل للتأكد من التفاف النص داخل البطاقة بدون قص أو تجاوز حدود الشاشة.',
    createdBy: 'creator-1',
    assignedTo: 'member-1',
    createdAt: DateTime.utc(2026, 11, 13),
    updatedAt: DateTime.utc(2026, 11, 13),
    durationMinutes: 240,
    dueAt: DateTime.now().add(const Duration(hours: 4)),
    priority: 'high',
    status: 'in_progress',
    version: 1,
  );

  testWidgets(
    'task list shell stays within phone, landscape, and tablet viewports',
    (tester) async {
      const sizes = [
        Size(320, 568),
        Size(360, 640),
        Size(393, 852),
        Size(412, 915),
        Size(915, 412),
        Size(800, 1024),
      ];
      for (final size in sizes) {
        for (final locale in const [Locale('ar'), Locale('en')]) {
          for (final scale in const [1.0, 1.3, 1.6]) {
            for (final brightness in Brightness.values) {
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = size;
              final container = ProviderContainer(
                overrides: [
                  activeTeamProvider.overrideWith(
                    _TestActiveTeamController.new,
                  ),
                  teamsProvider.overrideWith((ref) async => [team]),
                  taskListProvider(query).overrideWith((ref) async => [task]),
                  membersProvider(team.id).overrideWith(
                    (ref) async => const [
                      Member(
                        id: 'member-1',
                        name: 'محمد عبد الرحمن طويل الاسم للاختبار',
                        email: 'member@example.com',
                        role: 'member',
                      ),
                    ],
                  ),
                ],
              );

              await tester.pumpWidget(
                UncontrolledProviderScope(
                  container: container,
                  child: MaterialApp(
                    locale: locale,
                    supportedLocales: const [Locale('ar'), Locale('en')],
                    localizationsDelegates:
                        GlobalMaterialLocalizations.delegates,
                    theme: buildTaskatyTheme(),
                    darkTheme: buildTaskatyTheme(brightness: Brightness.dark),
                    themeMode: brightness == Brightness.dark
                        ? ThemeMode.dark
                        : ThemeMode.light,
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                    home: const AppShell(
                      location: '/tasks',
                      child: TaskListScreen(),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();

              expect(
                tester.takeException(),
                isNull,
                reason:
                    'layout exception at $size, ${locale.languageCode}, text scale $scale, $brightness',
              );

              await tester.pumpWidget(const SizedBox.shrink());
              container.dispose();
            }
          }
        }
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets('switching teams refreshes the visible task collection', (
    tester,
  ) async {
    const secondTeam = Team(id: 'team-2', name: 'الفريق الثاني');
    const firstTask = TaskQuery('team-1');
    const secondTask = TaskQuery('team-2');
    final container = ProviderContainer(
      overrides: [
        activeTeamProvider.overrideWith(_TestActiveTeamController.new),
        teamsProvider.overrideWith((ref) async => [team, secondTeam]),
        taskListProvider(firstTask).overrideWith((ref) async => [task]),
        taskListProvider(secondTask).overrideWith(
          (ref) async => [
            TaskItem(
              id: 'task-2',
              teamId: 'team-2',
              title: 'Second team task',
              description: '',
              createdBy: 'creator-2',
              createdAt: DateTime.utc(2026, 11, 13),
              updatedAt: DateTime.utc(2026, 11, 13),
              durationMinutes: 60,
              dueAt: DateTime.now().add(const Duration(hours: 1)),
              priority: 'normal',
              status: 'pending',
              version: 1,
            ),
          ],
        ),
        membersProvider(team.id).overrideWith((ref) async => const []),
        membersProvider(secondTeam.id).overrideWith((ref) async => const []),
      ],
    );
    addTearDown(container.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildTaskatyTheme(),
          home: const AppShell(location: '/tasks', child: TaskListScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('مراجعة تصميم الصفحة'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('active-team-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الفريق الثاني').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(container.read(activeTeamProvider)?.id, 'team-2');
    expect(find.text('Second team task'), findsOneWidget);
    expect(find.textContaining('مراجعة تصميم الصفحة'), findsNothing);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
