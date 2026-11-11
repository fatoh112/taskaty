import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

import 'api.dart';
import 'config.dart';
import 'models.dart';

final firebaseReadyProvider = Provider<bool>((ref) => AppConfig.firebaseConfigured);
final authStateProvider = StreamProvider<User?>((ref) {
  if (!AppConfig.firebaseConfigured) return const Stream<User?>.empty();
  return FirebaseAuth.instance.authStateChanges();
});
final activeTeamProvider = NotifierProvider<ActiveTeamController, Team?>(ActiveTeamController.new);
class ActiveTeamController extends Notifier<Team?> {
  @override Team? build() => null;
  void select(Team? team) => state = team;
}

final teamsProvider = FutureProvider.autoDispose<List<Team>>((ref) async {
  final teams = await ref.watch(apiProvider).listTeams();
  final active = ref.read(activeTeamProvider);
  if (!teams.any((team) => team.id == active?.id)) {
    ref.read(activeTeamProvider.notifier).select(teams.isEmpty ? null : teams.first);
  }
  return teams;
});
final membersProvider = FutureProvider.autoDispose.family<List<Member>, String>((ref, id) => ref.watch(apiProvider).listMembers(id));
final taskListProvider = FutureProvider.autoDispose.family<List<TaskItem>, TaskQuery>((ref, query) => ref.watch(apiProvider).listTasks(query.teamId, status: query.status, search: query.search, onlyMine: query.onlyMine));
final taskProvider = FutureProvider.autoDispose.family<TaskItem, String>((ref, id) => ref.watch(apiProvider).getTask(id));
final notificationsProvider = FutureProvider.autoDispose<NotificationPage>((ref) => ref.watch(apiProvider).listNotifications());
final dashboardProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) => ref.watch(apiProvider).dashboard(id));
final countdownNowProvider = StreamProvider.autoDispose<DateTime>((ref) {
  final output = StreamController<DateTime>();
  Timer? timer;
  void stop() { timer?.cancel(); timer = null; }
  void start() {
    stop();
    output.add(DateTime.now());
    timer = Timer.periodic(const Duration(seconds: 1), (_) => output.add(DateTime.now()));
  }
  final lifecycle = AppLifecycleListener(onResume: start, onPause: stop, onHide: stop, onDetach: stop);
  if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) start();
  ref.onDispose(() { stop(); lifecycle.dispose(); output.close(); });
  return output.stream;
});
final localeProvider = NotifierProvider<LocaleController, Locale>(LocaleController.new);
class LocaleController extends Notifier<Locale> {
  @override Locale build() => const Locale('ar');
  void toggle() => state = state.languageCode == 'ar' ? const Locale('en') : const Locale('ar');
}

class TaskQuery {
  const TaskQuery(this.teamId, {this.status = '', this.search = '', this.onlyMine = false});
  final String teamId, status, search;
  final bool onlyMine;
  @override bool operator ==(Object other) => other is TaskQuery && other.teamId == teamId && other.status == status && other.search == search && other.onlyMine == onlyMine;
  @override int get hashCode => Object.hash(teamId, status, search, onlyMine);
}
