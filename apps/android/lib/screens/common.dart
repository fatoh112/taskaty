import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';

extension IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.title, {super.key, this.subtitle, this.trailing});
  final String title; final String? subtitle; final Widget? trailing;
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.headlineMedium), if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 5), child: Text(subtitle!, style: Theme.of(context).textTheme.bodySmall))])), if (trailing != null) trailing! ]));
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.message, this.onRetry});
  final String message; final VoidCallback? onRetry;
  @override Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off_outlined, size: 42, color: TaskatyColors.amber), const SizedBox(height: 12), Text(message, textAlign: TextAlign.center), if (onRetry != null) TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(tr(context, 'حاول تاني', 'Try again')))])));
}

class EmptyPanel extends StatelessWidget { const EmptyPanel({super.key, required this.icon, required this.title, required this.body, this.action}); final IconData icon; final String title, body; final Widget? action; @override Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 46, color: TaskatyColors.muted), const SizedBox(height: 12), Text(title, style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 6), Text(body, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall), if (action != null) Padding(padding: const EdgeInsets.only(top: 16), child: action!)]))); }

class TaskCard extends ConsumerWidget {
  const TaskCard({super.key, required this.task, this.assignee, this.onTap});
  final TaskItem task; final String? assignee; final VoidCallback? onTap;
  @override Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(countdownNowProvider).whenOrNull(data: (value) => value) ?? DateTime.now();
    final overdue = task.isOverdue && task.active;
    final remaining = task.dueAt.difference(now);
    final status = switch (task.status) {'completed' => tr(context, 'مكتملة', 'Completed'), 'cancelled' => tr(context, 'ملغية', 'Cancelled'), 'in_progress' => tr(context, 'جاري التنفيذ', 'In progress'), _ => tr(context, 'قيد الانتظار', 'Pending')};
    return Card(child: InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium)), const SizedBox(width: 10), _StatusPill(text: overdue ? tr(context, 'متأخرة', 'Overdue') : status, color: overdue ? TaskatyColors.amber : task.status == 'completed' ? TaskatyColors.green : TaskatyColors.cyan)]),
      if (task.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 7), child: Text(task.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)),
      const SizedBox(height: 14),
      Row(children: [Icon(Icons.schedule, size: 16, color: overdue ? TaskatyColors.amber : TaskatyColors.muted), const SizedBox(width: 6), Expanded(child: Text(task.status == 'completed' ? tr(context, 'اكتملت ${_formatDate(task.completedAt)}', 'Completed ${_formatDate(task.completedAt)}') : '${tr(context, 'الموعد', 'Due')} ${_formatDate(task.dueAt.toIso8601String())}', style: Theme.of(context).textTheme.bodySmall)), if (task.active) Text(_countdown(remaining, context), style: TextStyle(color: overdue ? TaskatyColors.amber : TaskatyColors.cyan, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]))]),
      if (assignee != null && assignee!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Row(children: [const Icon(Icons.person_outline, size: 16, color: TaskatyColors.muted), const SizedBox(width: 6), Text(assignee!, style: Theme.of(context).textTheme.bodySmall), const Spacer(), _PriorityPill(priority: task.priority)])),
    ]))));
  }
}

class _StatusPill extends StatelessWidget { const _StatusPill({required this.text, required this.color}); final String text; final Color color; @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(99)), child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700))); }
class _PriorityPill extends StatelessWidget { const _PriorityPill({required this.priority}); final String priority; @override Widget build(BuildContext context) { final c = priority == 'urgent' || priority == 'high' ? TaskatyColors.amber : TaskatyColors.muted; final txt = switch (priority) {'urgent' => tr(context, 'عاجلة', 'Urgent'), 'high' => tr(context, 'عالية', 'High'), 'low' => tr(context, 'منخفضة', 'Low'), _ => tr(context, 'عادية', 'Normal')}; return Text(txt, style: TextStyle(color: c, fontSize: 11)); } }

String countdownText(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final days = d.inDays, hours = d.inHours % 24, minutes = d.inMinutes % 60;
  if (days > 0) return '${days}d ${hours}h';
  if (d.inHours > 0) return '${d.inHours}h ${minutes}m';
  return '${d.inMinutes}m';
}
String _countdown(Duration d, BuildContext context) => d.isNegative ? tr(context, 'انتهى الوقت', 'Time passed') : countdownText(d);
String _formatDate(String? value) { if (value == null || value.isEmpty) return ''; final date = DateTime.tryParse(value)?.toLocal(); if (date == null) return ''; final two = (int n) => n.toString().padLeft(2, '0'); return '${two(date.day)}/${two(date.month)} · ${two(date.hour)}:${two(date.minute)}'; }

class PollingRefresh extends ConsumerStatefulWidget {
  const PollingRefresh({super.key, required this.child, required this.refresh});
  final Widget child; final Future<void> Function() refresh;
  @override ConsumerState<PollingRefresh> createState() => _PollingRefreshState();
}
class _PollingRefreshState extends ConsumerState<PollingRefresh> with WidgetsBindingObserver {
  Timer? _timer;
  @override void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); _start(); }
  void _start() { _timer?.cancel(); if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) _timer = Timer.periodic(const Duration(seconds: 25), (_) => widget.refresh()); }
  @override void didChangeAppLifecycleState(AppLifecycleState state) { if (state == AppLifecycleState.resumed) { _start(); widget.refresh(); } else { _timer?.cancel(); } }
  @override void dispose() { _timer?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override Widget build(BuildContext context) => widget.child;
}

class SelectTeamCard extends ConsumerWidget {
  const SelectTeamCard({super.key, required this.teams}); final List<Team> teams;
  @override Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(activeTeamProvider);
    final selected = teams.any((t) => t.id == current?.id) ? current : teams.first;
    return Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: DropdownButtonHideUnderline(child: DropdownButton<Team>(value: selected, isExpanded: true, items: teams.map((t) => DropdownMenuItem(value: t, child: Text(t.name, overflow: TextOverflow.ellipsis))).toList(), onChanged: (team) { if (team != null) ref.read(activeTeamProvider.notifier).select(team); }))));
  }
}
