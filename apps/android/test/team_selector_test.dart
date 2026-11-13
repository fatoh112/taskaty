import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:taskpulse_android/api.dart';
import 'package:taskpulse_android/models.dart';
import 'package:taskpulse_android/screens/common.dart';
import 'package:taskpulse_android/state.dart';

class _TestActiveTeamController extends ActiveTeamController {
  _TestActiveTeamController(this.initial);

  final Team? initial;

  @override
  Team? build() => initial;
}

class _TestTaskApi extends TaskApi {
  _TestTaskApi(this.teams) : super(http.Client());

  final List<Team> teams;

  @override
  Future<List<Team>> listTeams() async => teams;
}

void main() {
  Future<void> pumpSelector(
    WidgetTester tester,
    ProviderContainer container,
    List<Team> teams, {
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(width: 320, child: SelectTeamCard(teams: teams)),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a refreshed Team instance with the same ID does not assert', (
    tester,
  ) async {
    final oldTeam = Team(id: 'team-1', name: 'Old team name');
    final container = ProviderContainer(
      overrides: [
        activeTeamProvider.overrideWith(
          () => _TestActiveTeamController(oldTeam),
        ),
      ],
    );
    addTearDown(container.dispose);

    await pumpSelector(tester, container, [
      Team(id: 'team-1', name: 'Updated team name'),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.text('Updated team name'), findsOneWidget);
  });

  testWidgets('stale and deleted selections fall back to a live team', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        activeTeamProvider.overrideWith(
          () => _TestActiveTeamController(
            const Team(id: 'deleted-team', name: 'Deleted team'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await pumpSelector(tester, container, const [
      Team(id: 'live-team', name: 'Live team'),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.text('Live team'), findsOneWidget);
    final dropdown = tester.widget<DropdownButton<String>>(
      find.byKey(const ValueKey('active-team-selector')),
    );
    expect(dropdown.value, 'live-team');
  });

  testWidgets('duplicate IDs render only one option', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await pumpSelector(tester, container, const [
      Team(id: 'team-1', name: 'First copy'),
      Team(id: 'team-1', name: 'Duplicate copy'),
      Team(id: '', name: 'Invalid ID'),
    ]);

    expect(tester.takeException(), isNull);
    final dropdown = tester.widget<DropdownButton<String>>(
      find.byKey(const ValueKey('active-team-selector')),
    );
    expect(dropdown.items, hasLength(1));
    expect(dropdown.items!.single.value, 'team-1');
  });

  testWidgets('empty teams show a safe empty state', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await pumpSelector(tester, container, const []);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('active-team-selector')), findsNothing);
    expect(find.text('لا توجد فرق متاحة'), findsOneWidget);
  });

  testWidgets('choosing an option updates active team by stable ID', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await pumpSelector(tester, container, const [
      Team(id: 'team-1', name: 'Team one'),
      Team(id: 'team-2', name: 'Team two'),
    ], textScale: 1.6);

    await tester.tap(find.byKey(const ValueKey('active-team-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Team two').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(container.read(activeTeamProvider)?.id, 'team-2');
  });

  test(
    'team refresh synchronizes active state to the current server object',
    () async {
      final oldTeam = Team(id: 'team-1', name: 'Before refresh');
      final refreshedTeam = Team(id: 'team-1', name: 'After refresh');
      final container = ProviderContainer(
        overrides: [
          activeTeamProvider.overrideWith(
            () => _TestActiveTeamController(oldTeam),
          ),
          apiProvider.overrideWithValue(_TestTaskApi([refreshedTeam])),
        ],
      );
      addTearDown(container.dispose);

      final teams = await container.read(teamsProvider.future);

      expect(teams.single.name, 'After refresh');
      expect(
        identical(container.read(activeTeamProvider), refreshedTeam),
        isTrue,
      );
    },
  );
}
