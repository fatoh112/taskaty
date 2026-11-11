import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../app.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import 'common.dart';

class TeamOnboardingScreen extends ConsumerStatefulWidget {
  const TeamOnboardingScreen({super.key});
  @override ConsumerState<TeamOnboardingScreen> createState() => _TeamOnboardingScreenState();
}
class _TeamOnboardingScreenState extends ConsumerState<TeamOnboardingScreen> {
  final _teamName = TextEditingController(), _code = TextEditingController();
  bool _busy = false; String? _error, _inviteCode;
  @override void dispose() { _teamName.dispose(); _code.dispose(); super.dispose(); }
  Future<void> _create() async {
    if (_teamName.text.trim().length < 2) { setState(() => _error = tr(context, 'اكتب اسم الفريق', 'Enter a team name')); return; }
    setState(() { _busy = true; _error = null; });
    try {
      final team = await ref.read(apiProvider).createTeam(_teamName.text.trim());
      ref.read(activeTeamProvider.notifier).select(team);
      ref.invalidate(teamsProvider);
      final inviteCode = await ref.read(apiProvider).createInvitation(team.id);
      if (mounted) setState(() => _inviteCode = inviteCode);
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    if (mounted) setState(() => _busy = false);
  }
  Future<void> _join() async {
    if (_code.text.trim().isEmpty) return;
    setState(() { _busy = true; _error = null; });
    try { await ref.read(apiProvider).joinTeam(_code.text.trim()); ref.invalidate(teamsProvider); if (mounted) context.go('/home'); }
    catch (e) { if (mounted) setState(() => _error = e.toString()); }
    if (mounted) setState(() => _busy = false);
  }
  @override Widget build(BuildContext context) => SingleChildScrollView(padding: const EdgeInsets.all(20), child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const SizedBox(height: 20), const Icon(Icons.groups_2_outlined, size: 56, color: TaskatyColors.cyan), const SizedBox(height: 16),
    Text(tr(context, 'ابدأ بفريقك', 'Set up your team'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
    const SizedBox(height: 8), Text(tr(context, 'اعمل فريق جديد أو ادخل بكود دعوة آمن.', 'Create a team or join with a secure invitation code.'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
    const SizedBox(height: 24),
    Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Text(tr(context, 'فريق جديد', 'Create a team'), style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 14), TextField(controller: _teamName, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: tr(context, 'اسم الفريق', 'Team name'), prefixIcon: const Icon(Icons.groups_outlined))), const SizedBox(height: 12), FilledButton(onPressed: _busy ? null : _create, child: _busy ? const CircularProgressIndicator() : Text(tr(context, 'إنشاء الفريق', 'Create team')))]))),
    if (_inviteCode != null) Card(color: TaskatyColors.surface2, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr(context, 'كود دعوة صالح لمدة 7 أيام', 'Invitation code · valid for 7 days'), style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 8), SelectableText(_inviteCode!, style: const TextStyle(color: TaskatyColors.cyan, fontSize: 22, fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(tr(context, 'ابعت الكود لزملائك بشكل آمن. كل كود استخدامه مرة واحدة.', 'Share this code privately. Each invitation can be used once.'), style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 10), OutlinedButton.icon(onPressed: () => context.go('/home'), icon: const Icon(Icons.arrow_forward), label: Text(tr(context, 'كمل للوحة الفريق', 'Continue to dashboard')))]))),
    const SizedBox(height: 14),
    Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Text(tr(context, 'معاك دعوة؟', 'Have an invitation?'), style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 14), TextField(controller: _code, textCapitalization: TextCapitalization.none, decoration: InputDecoration(labelText: tr(context, 'كود الدعوة', 'Invitation code'), prefixIcon: const Icon(Icons.key_outlined))), const SizedBox(height: 12), OutlinedButton(onPressed: _busy ? null : _join, child: Text(tr(context, 'انضم للفريق', 'Join team')))]))),
    if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
  ]))));
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});
  Future<void> _refresh(WidgetRef ref) async { final team = ref.read(activeTeamProvider); if (team != null) ref.invalidate(dashboardProvider(team.id)); }
  @override Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(teamsProvider);
    return teams.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorPanel(message: e.toString(), onRetry: () => ref.invalidate(teamsProvider)),
      data: (items) {
        if (items.isEmpty) return const TeamOnboardingScreen();
        final selected = ref.watch(activeTeamProvider);
        final team = items.where((t) => t.id == selected?.id).firstOrNull ?? items.first;
        final dashboard = ref.watch(dashboardProvider(team.id));
        return PollingRefresh(refresh: () => _refresh(ref), child: RefreshIndicator(onRefresh: () => _refresh(ref), child: ListView(padding: const EdgeInsets.only(bottom: 90), children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 12), child: Row(children: [Expanded(child: Text('${tr(context, 'أهلاً', 'Hello')}، ${FirebaseAuth.instance.currentUser?.displayName ?? ''}', style: Theme.of(context).textTheme.titleLarge)), IconButton(tooltip: tr(context, 'إنشاء مهمة', 'New task'), onPressed: () => context.push('/create'), icon: const Icon(Icons.add_circle_outline, color: TaskatyColors.cyan, size: 28))])),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: SelectTeamCard(teams: items)),
          dashboard.when(
            loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: ErrorPanel(message: e.toString(), onRetry: () => ref.invalidate(dashboardProvider(team.id)))),
            data: (d) {
              if (d['_notModified'] == true) return const SizedBox.shrink();
              final summary = d['summary'] as Map<String, dynamic>? ?? {};
              final memberStats = (d['members'] as List? ?? const []).cast<Map<String, dynamic>>();
              final averageSeconds = (summary['averageCompletionSeconds'] as num?)?.toInt();
              final averageLabel = averageSeconds == null ? '—' : averageSeconds >= 3600
                  ? '${(averageSeconds / 3600).toStringAsFixed(1)} ${tr(context, 'س', 'h')}'
                  : '${(averageSeconds / 60).round()} ${tr(context, 'د', 'min')}';
              final statPairs = <(String, String, Color, IconData)>[
                (tr(context, 'كل المهام', 'Total'), '${summary['totalTasks'] ?? 0}', TaskatyColors.cyan, Icons.grid_view),
                (tr(context, 'نشطة', 'Active'), '${summary['activeTasks'] ?? 0}', const Color(0xFF7AA2FF), Icons.bolt),
                (tr(context, 'مكتملة', 'Done'), '${summary['completedTasks'] ?? 0}', TaskatyColors.green, Icons.check_circle_outline),
                (tr(context, 'متأخرة', 'Overdue'), '${summary['overdueTasks'] ?? 0}', TaskatyColors.amber, Icons.warning_amber_rounded),
              ];
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.all(20), crossAxisCount: 2, childAspectRatio: 1.65, crossAxisSpacing: 12, mainAxisSpacing: 12, children: statPairs.map((p) => _StatCard(label: p.$1, value: p.$2, color: p.$3, icon: p.$4)).toList()),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [
                  Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.insights_outlined, color: TaskatyColors.cyan), const SizedBox(height: 8), Text(tr(context, 'إنجاز في موعده', 'On-time completion'), style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 4), Text(summary['onTimeCompletionPercent'] == null ? '—' : '${summary['onTimeCompletionPercent']}%', style: const TextStyle(color: TaskatyColors.green, fontWeight: FontWeight.w800, fontSize: 20))])))),
                  const SizedBox(width: 10),
                  Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.timelapse, color: TaskatyColors.cyan), const SizedBox(height: 8), Text(tr(context, 'متوسط مدة الإنجاز', 'Avg. completion time'), style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 4), Text(averageLabel, style: const TextStyle(color: TaskatyColors.cyan, fontWeight: FontWeight.w800, fontSize: 20))])))),
                ])),
                if (memberStats.isNotEmpty) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(20, 22, 20, 8), child: Text(tr(context, 'أداء الفريق', 'Team performance'), style: Theme.of(context).textTheme.titleLarge)),
                  ...memberStats.take(5).map((m) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4), child: Card(child: ListTile(leading: CircleAvatar(backgroundColor: TaskatyColors.cyan.withValues(alpha: .12), child: Text(((m['displayName'] as String?) ?? '?').characters.first.toUpperCase(), style: const TextStyle(color: TaskatyColors.cyan))), title: Text((m['displayName'] as String?)?.isNotEmpty == true ? m['displayName'] as String : tr(context, 'عضو الفريق', 'Team member')), subtitle: Text('${m['completedCount'] ?? 0} ${tr(context, 'مكتملة', 'completed')} · ${m['overdueCount'] ?? 0} ${tr(context, 'متأخرة', 'overdue')}'), trailing: Text(m['onTimeCompletionPercent'] == null ? '—' : '${m['onTimeCompletionPercent']}%', style: const TextStyle(color: TaskatyColors.green, fontWeight: FontWeight.w700)))))),
                ],
              ]);
            },
          ),
          Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 8), child: Row(children: [Expanded(child: Text(tr(context, 'قريبًا من الموعد', 'Coming up'), style: Theme.of(context).textTheme.titleLarge)), TextButton(onPressed: () => context.go('/tasks'), child: Text(tr(context, 'كل المهام', 'All tasks')))])),
          dashboard.when(
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2))),
            error: (e, _) => Padding(padding: const EdgeInsets.all(18), child: Text(e.toString())),
            data: (d) {
              final upcoming = (d['approaching'] as List? ?? const []).cast<Map<String, dynamic>>().map(TaskItem.fromJson).toList();
              if (upcoming.isEmpty) return Padding(padding: const EdgeInsets.all(20), child: EmptyPanel(icon: Icons.check_circle_outline, title: tr(context, 'مفيش مواعيد قريبة', 'No approaching deadlines'), body: tr(context, 'مفيش مهام مستحقة خلال الساعتين الجايين.', 'Nothing is due in the next two hours.')));
              return Column(
                children: upcoming.take(3).map((task) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: TaskCard(
                      task: task,
                      onTap: () => context.push('/task/' + task.id),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ])));
      },
    );
  }
}

class _StatCard extends StatelessWidget { const _StatCard({required this.label, required this.value, required this.color, required this.icon}); final String label, value; final Color color; final IconData icon; @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Icon(icon, color: color, size: 20), Text(value, style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: color)), Text(label, style: Theme.of(context).textTheme.bodySmall)]))); }

class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});
  @override Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(teamsProvider); final selected = ref.watch(activeTeamProvider);
    return teams.when(loading: () => const Center(child: CircularProgressIndicator()), error: (e, _) => ErrorPanel(message: e.toString(), onRetry: () => ref.invalidate(teamsProvider)), data: (items) {
      if (items.isEmpty) return const TeamOnboardingScreen();
      final team = items.where((t) => t.id == selected?.id).firstOrNull ?? items.first;
      final members = ref.watch(membersProvider(team.id));
      return PollingRefresh(
        refresh: () async => ref.invalidate(membersProvider(team.id)),
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(membersProvider(team.id)),
          child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        ScreenTitle(tr(context, 'الفريق', 'Team'), subtitle: tr(context, 'إدارة أعضاء الفريق والدعوات.', 'Members and invitations.'), trailing: IconButton(onPressed: () => _invite(context, ref, team), icon: const Icon(Icons.person_add_alt_1, color: TaskatyColors.cyan))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: SelectTeamCard(teams: items)),
        Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 8), child: Text('${tr(context, 'الأعضاء', 'Members')} · ${team.name}', style: Theme.of(context).textTheme.titleLarge)),
        members.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.all(20),
            child: ErrorPanel(
              message: error.toString(),
              onRetry: () => ref.invalidate(membersProvider(team.id)),
            ),
          ),
          data: (list) => Column(
            children: list.map((member) {
              final displayName = member.name.isNotEmpty ? member.name : member.email;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(displayName.characters.first.toUpperCase()),
                    ),
                    title: Text(displayName),
                    subtitle: Text(member.email),
                    trailing: Chip(label: Text(_role(context, member.role))),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        Padding(padding: const EdgeInsets.all(20), child: OutlinedButton.icon(onPressed: () => _leave(context, ref, team), icon: const Icon(Icons.logout), label: Text(tr(context, 'مغادرة الفريق', 'Leave team')))),
          ]),
        ),
      );
    });
  }
  static String _role(BuildContext context, String role) => switch (role) {'owner' => tr(context, 'مالك', 'Owner'), 'admin' => tr(context, 'مشرف', 'Admin'), _ => tr(context, 'عضو', 'Member')};
  static Future<void> _invite(BuildContext context, WidgetRef ref, Team team) async {
    try { final code = await ref.read(apiProvider).createInvitation(team.id); if (context.mounted) showDialog<void>(context: context, builder: (_) => AlertDialog(title: Text(tr(context, 'كود دعوة الفريق', 'Team invitation')), content: SelectableText(code, style: const TextStyle(fontSize: 22, color: TaskatyColors.cyan, fontWeight: FontWeight.w800)), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(context, 'تم', 'Done')))])); }
    catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
  }
  static Future<void> _leave(BuildContext context, WidgetRef ref, Team team) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text(tr(context, 'مغادرة الفريق؟', 'Leave this team?')), content: Text(tr(context, 'هتفقد الوصول لمهام الفريق لحد ما تنضم تاني.', 'You will lose access to this team’s tasks.')), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr(context, 'إلغاء', 'Cancel'))), FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr(context, 'مغادرة', 'Leave')))]));
    if (confirm != true) return;
    try { await ref.read(apiProvider).leaveTeam(team.id); ref.read(activeTeamProvider.notifier).select(null); ref.invalidate(teamsProvider); if (context.mounted) context.go('/home'); }
    catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
  }
}
