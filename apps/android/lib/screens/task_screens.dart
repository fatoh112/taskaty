import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../api.dart';
import '../app.dart';
import '../models.dart';
import '../state.dart';
import '../task_form_validation.dart';
import '../task_parser.dart';
import '../theme.dart';
import 'common.dart';
import 'team_screens.dart';

class TaskListScreen extends ConsumerStatefulWidget { const TaskListScreen({super.key}); @override ConsumerState<TaskListScreen> createState() => _TaskListScreenState(); }
class _TaskListScreenState extends ConsumerState<TaskListScreen> {
  final _search = TextEditingController(); Timer? _searchDebounce; String _status = '', _searchText = ''; bool _mine = false;
  @override void dispose() { _searchDebounce?.cancel(); _search.dispose(); super.dispose(); }
  Future<void> _refresh() async { final team = ref.read(activeTeamProvider); if (team != null) ref.invalidate(taskListProvider(TaskQuery(team.id, status: _status, search: _searchText, onlyMine: _mine))); }
  @override Widget build(BuildContext context) {
    final teams = ref.watch(teamsProvider);
    return teams.when(loading: () => const Center(child: CircularProgressIndicator()), error: (e, _) => ErrorPanel(message: e.toString(), onRetry: () => ref.invalidate(teamsProvider)), data: (items) {
      if (items.isEmpty) return const TeamOnboardingScreen();
      final selected = ref.watch(activeTeamProvider); final team = items.where((t) => t.id == selected?.id).firstOrNull ?? items.first;
      final query = TaskQuery(team.id, status: _status, search: _searchText, onlyMine: _mine);
      final tasks = ref.watch(taskListProvider(query));
      final members = ref.watch(membersProvider(team.id)).whenOrNull(data: (value) => value) ?? const <Member>[];
      return PollingRefresh(refresh: _refresh, child: Column(children: [
        ScreenTitle(tr(context, 'المهام', 'Tasks'), subtitle: tr(context, 'تابع شغل الفريق ومواعيده.', 'Track work and deadlines.'), trailing: IconButton(onPressed: () => context.push('/create'), icon: const Icon(Icons.add, color: TaskatyColors.cyan))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: SelectTeamCard(teams: items)),
        Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 4), child: TextField(controller: _search, onChanged: (v) { _searchDebounce?.cancel(); _searchDebounce = Timer(const Duration(milliseconds: 350), () { if (mounted) setState(() => _searchText = v.trim()); }); }, decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr(context, 'ابحث في المهام', 'Search tasks'), suffixIcon: _searchText.isEmpty ? null : IconButton(onPressed: () { _searchDebounce?.cancel(); _search.clear(); setState(() => _searchText = ''); }, icon: const Icon(Icons.close))))),
        SizedBox(height: 54, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5), children: [
          _FilterChip(label: tr(context, 'الكل', 'All'), selected: _status.isEmpty, onTap: () => setState(() => _status = '')),
          _FilterChip(label: tr(context, 'قيد الانتظار', 'Pending'), selected: _status == 'pending', onTap: () => setState(() => _status = 'pending')),
          _FilterChip(label: tr(context, 'جارية', 'In progress'), selected: _status == 'in_progress', onTap: () => setState(() => _status = 'in_progress')),
          _FilterChip(label: tr(context, 'مكتملة', 'Completed'), selected: _status == 'completed', onTap: () => setState(() => _status = 'completed')),
          _FilterChip(label: tr(context, 'ملغية', 'Cancelled'), selected: _status == 'cancelled', onTap: () => setState(() => _status = 'cancelled')),
        ])),
        SwitchListTile(value: _mine, onChanged: (v) => setState(() => _mine = v), title: Text(tr(context, 'مهامي فقط', 'Assigned to me')), dense: true, secondary: const Icon(Icons.person_outline)),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: tasks.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorPanel(message: e.toString(), onRetry: () => ref.invalidate(taskListProvider(query))),
              data: (list) {
                if (list.isEmpty) {
                  return ListView(
                    children: [
                      SizedBox(
                        height: 220,
                        child: EmptyPanel(
                          icon: Icons.checklist_outlined,
                          title: tr(context, 'مفيش مهام هنا', 'No tasks here'),
                          body: tr(context, 'غيّر الفلتر أو اعمل مهمة جديدة.', 'Change the filter or create a task.'),
                          action: FilledButton(
                            onPressed: () => context.push('/create'),
                            child: Text(tr(context, 'إنشاء مهمة', 'Create task')),
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final task = list[index];
                    final owner = members.where((member) => member.id == task.assignedTo).firstOrNull;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: TaskCard(
                        task: task,
                        assignee: owner?.name.isNotEmpty == true ? owner!.name : owner?.email,
                        onTap: () => context.push('/task/' + task.id),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ]));
    });
  }
}
class _FilterChip extends StatelessWidget { const _FilterChip({required this.label, required this.selected, required this.onTap}); final String label; final bool selected; final VoidCallback onTap; @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap())); }

class TaskCreateScreen extends ConsumerStatefulWidget {
  const TaskCreateScreen({super.key, this.transcript}); final String? transcript;
  @override ConsumerState<TaskCreateScreen> createState() => _TaskCreateScreenState();
}
class _TaskCreateScreenState extends ConsumerState<TaskCreateScreen> {
  final _form = GlobalKey<FormState>(); final _title = TextEditingController(), _description = TextEditingController(), _duration = TextEditingController(text: '240');
  String _priority = 'normal'; String? _assignee; DateTime? _dueAt; bool _busy = false, _parsed = false, _needsReview = false; String? _error, _parsedAssigneeName;
  final String _idempotencyKey = const Uuid().v4().replaceAll('-', '');
  @override void dispose() { _title.dispose(); _description.dispose(); _duration.dispose(); super.dispose(); }
  void _applyParse(List<Member> members) {
    if (_parsed || widget.transcript == null || widget.transcript!.trim().isEmpty) return;
    final parsed = TaskParser.parse(widget.transcript!, members.map((m) => TeamName(id: m.id, name: m.name)).toList());
    _title.text = parsed.title; _duration.text = '${parsed.durationMinutes}'; _priority = parsed.priority; _dueAt = parsed.dueAt;
    _assignee = parsed.assignedTo; _needsReview = parsed.assignmentNeedsReview; _parsedAssigneeName = parsed.assigneeName; _parsed = true;
  }
  Future<void> _save(Team team) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final duration = parseDurationMinutes(_duration.text);
    if (duration == null) { setState(() => _error = tr(context, 'المدة لازم تكون من دقيقة لسنة.', 'Duration must be between 1 minute and 1 year.')); return; }
    setState(() { _busy = true; _error = null; });
    try {
      final remainingMinutes = _dueAt == null ? duration : _dueAt!.difference(DateTime.now()).inMinutes;
      if (remainingMinutes < 1) { setState(() { _error = tr(context, 'الموعد اللي اخترته عدى. راجع التاريخ أو استخدم مدة جديدة.', 'That deadline has passed. Review it or choose a new duration.'); _busy = false; }); return; }
      final task = await ref.read(apiProvider).createTask(teamId: team.id, title: _title.text.trim(), description: _description.text.trim(), durationMinutes: _dueAt == null ? duration : remainingMinutes, priority: _priority, idempotencyKey: _idempotencyKey, assignedTo: _assignee);
      ref.invalidate(taskListProvider(TaskQuery(team.id))); ref.invalidate(dashboardProvider(team.id)); ref.invalidate(notificationsProvider);
      if (mounted) context.go('/task/${task.id}');
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    if (mounted) setState(() => _busy = false);
  }
  @override Widget build(BuildContext context) {
    final teamsAsync = ref.watch(teamsProvider);
    return teamsAsync.when(loading: () => const Center(child: CircularProgressIndicator()), error: (e, _) => ErrorPanel(message: e.toString()), data: (teams) {
      if (teams.isEmpty) return const TeamOnboardingScreen();
      final current = ref.watch(activeTeamProvider); final team = teams.where((t) => t.id == current?.id).firstOrNull ?? teams.first;
      final membersAsync = ref.watch(membersProvider(team.id));
      return membersAsync.when(loading: () => const Center(child: CircularProgressIndicator()), error: (e, _) => ErrorPanel(message: e.toString()), data: (members) {
        _applyParse(members);
        final self = FirebaseAuth.instance.currentUser;
        final choices = members.any((m) => m.id == self?.uid) ? members : [...members, Member(id: self?.uid ?? '', name: self?.displayName ?? tr(context, 'أنا', 'Me'), email: self?.email ?? '', role: 'member')];
        if (_assignee == null && !_needsReview && self != null && !_parsed) _assignee = self.uid;
        return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
          ScreenTitle(tr(context, 'مهمة جديدة', 'New task'), subtitle: tr(context, 'راجع التفاصيل قبل ما تضيفها للفريق.', 'Confirm all details before adding it to the team.')),
          if (widget.transcript != null) Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.graphic_eq, color: TaskatyColors.cyan), const SizedBox(width: 10), Expanded(child: Text(widget.transcript!, style: Theme.of(context).textTheme.bodyMedium))]))),
          const SizedBox(height: 8),
          Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextFormField(controller: _title, maxLength: 240, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: tr(context, 'عنوان المهمة', 'Task title'), prefixIcon: const Icon(Icons.task_alt)), validator: (v) => validateTaskTitle(v, arabic: Localizations.localeOf(context).languageCode == 'ar')),
            const SizedBox(height: 10),
            TextFormField(controller: _description, maxLines: 3, maxLength: 4000, decoration: InputDecoration(labelText: tr(context, 'تفاصيل إضافية (اختياري)', 'Description (optional)'), alignLabelWithHint: true)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(value: _assignee ?? '', decoration: InputDecoration(labelText: tr(context, 'المسؤول عن المهمة', 'Assignee'), prefixIcon: const Icon(Icons.person_outline)), items: [DropdownMenuItem(value: '', child: Text(tr(context, 'بدون مسؤول', 'Unassigned'))), ...choices.where((m) => m.id.isNotEmpty).map((m) => DropdownMenuItem(value: m.id, child: Text(m.name.isNotEmpty ? m.name : m.email)))], onChanged: (v) => setState(() { _assignee = v == '' ? null : v; _needsReview = false; })),
            if (_needsReview) Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr(context, 'الاسم المذكور ممكن يطابق أكتر من عضو. اختار المسؤول بنفسك.', 'The spoken name may match multiple team members. Choose the assignee explicitly.'), style: const TextStyle(color: TaskatyColors.amber))),
            if (_parsedAssigneeName != null && !_needsReview && _assignee == null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr(context, 'ما لقيناش "$_parsedAssigneeName" في الفريق. اختار المسؤول يدويًا أو خليه بدون مسؤول.', '“$_parsedAssigneeName” is not a team member. Choose an assignee or leave it unassigned.'), style: const TextStyle(color: TaskatyColors.amber))),
            const SizedBox(height: 14),
            Row(children: [Expanded(child: TextField(controller: _duration, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr(context, 'المدة بالدقائق', 'Duration in minutes'), prefixIcon: const Icon(Icons.hourglass_bottom)))), const SizedBox(width: 10), PopupMenuButton<int>(tooltip: tr(context, 'مدد جاهزة', 'Quick durations'), icon: const Icon(Icons.tune), onSelected: (v) => setState(() { _duration.text = '$v'; _dueAt = null; }), itemBuilder: (_) => [60, 120, 240, 360, 480, 720, 1440].map((v) => PopupMenuItem(value: v, child: Text('$v ${tr(context, 'دقيقة', 'min')}'))).toList())]),
            if (_dueAt != null) Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [const Icon(Icons.event, color: TaskatyColors.cyan), const SizedBox(width: 8), Expanded(child: Text('${tr(context, 'موعد مبدئي', 'Parsed deadline')} · ${MaterialLocalizations.of(context).formatMediumDate(_dueAt!)} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(_dueAt!))}')), TextButton(onPressed: () => setState(() => _dueAt = null), child: Text(tr(context, 'استخدم المدة', 'Use duration')))])),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(value: _priority, decoration: InputDecoration(labelText: tr(context, 'الأولوية', 'Priority'), prefixIcon: const Icon(Icons.flag_outlined)), items: [('low', tr(context, 'منخفضة', 'Low')), ('normal', tr(context, 'عادية', 'Normal')), ('high', tr(context, 'عالية', 'High')), ('urgent', tr(context, 'عاجلة', 'Urgent'))].map((p) => DropdownMenuItem(value: p.$1, child: Text(p.$2))).toList(), onChanged: (v) => setState(() => _priority = v ?? 'normal')),
          ])),
          const SizedBox(height: 18),
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
          FilledButton.icon(onPressed: _busy ? null : () => _save(team), icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check), label: Text(tr(context, 'تأكيد وإنشاء المهمة', 'Confirm and create task'))),
          const SizedBox(height: 6), Text(tr(context, 'موعد الاستحقاق يتحدد من وقت الخادم عند حفظ المهمة.', 'The server sets the authoritative deadline when the task is saved.'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        ]);
      });
    });
  }
}

class TaskDetailsScreen extends ConsumerWidget {
  const TaskDetailsScreen({super.key, required this.taskId}); final String taskId;
  Future<void> _mutate(BuildContext context, WidgetRef ref, TaskItem task, {String? status, String? priority}) async {
    try { await ref.read(apiProvider).updateTask(task.id, version: task.version, status: status, priority: priority); ref.invalidate(taskProvider(task.id)); ref.invalidate(taskListProvider(TaskQuery(task.teamId))); ref.invalidate(dashboardProvider(task.teamId)); ref.invalidate(notificationsProvider); }
    catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
  }
  @override Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(taskProvider(taskId));
    return async.when(loading: () => const Center(child: CircularProgressIndicator()), error: (e, _) => ErrorPanel(message: e.toString(), onRetry: () => ref.invalidate(taskProvider(taskId))), data: (task) {
      final teams = ref.watch(teamsProvider).whenOrNull(data: (value) => value) ?? const <Team>[];
      final team = teams.where((t) => t.id == task.teamId).firstOrNull;
      final userId = FirebaseAuth.instance.currentUser?.uid;
      final canEditContent = team != null && (team.role != 'member' || task.createdBy == userId);
      final members = ref.watch(membersProvider(task.teamId)).whenOrNull(data: (value) => value) ?? const <Member>[];
      final assigneeName = members.where((m) => m.id == task.assignedTo).firstOrNull?.name;
      return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      ScreenTitle(tr(context, 'تفاصيل المهمة', 'Task details'), subtitle: tr(context, 'الحالة والتاريخ وسجل النشاط.', 'Status, deadline, and activity.')),
      TaskCard(task: task),
      if (task.active && canEditContent) Padding(padding: const EdgeInsets.only(top: 8), child: OutlinedButton.icon(onPressed: () async {
        final updated = await showDialog<bool>(context: context, builder: (_) => TaskEditDialog(task: task));
        if (updated == true) { ref.invalidate(taskProvider(task.id)); ref.invalidate(taskListProvider(TaskQuery(task.teamId))); ref.invalidate(dashboardProvider(task.teamId)); }
      }, icon: const Icon(Icons.edit_outlined), label: Text(tr(context, 'تعديل تفاصيل المهمة', 'Edit task details')))),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _DetailRow(icon: Icons.groups_outlined, label: tr(context, 'الفريق', 'Team'), value: team?.name ?? task.teamId),
        _DetailRow(icon: Icons.person_outline, label: tr(context, 'المسؤول', 'Assignee'), value: task.assignedTo == null ? tr(context, 'غير معيّن', 'Unassigned') : assigneeName?.isNotEmpty == true ? assigneeName! : task.assignedTo!),
        _DetailRow(icon: Icons.hourglass_bottom, label: tr(context, 'المدة', 'Duration'), value: '${task.durationMinutes} ${tr(context, 'دقيقة', 'minutes')}'),
        _DetailRow(icon: Icons.event_available, label: tr(context, 'الموعد النهائي', 'Deadline'), value: MaterialLocalizations.of(context).formatFullDate(task.dueAt)),
        if (task.completedAt != null) _DetailRow(icon: Icons.check_circle_outline, label: tr(context, 'وقت الإكمال', 'Completed at'), value: task.completedAt!),
        if (task.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(task.description)),
      ]))),
      if (task.active) ...[
        const SizedBox(height: 12),
        if (task.status == 'pending') OutlinedButton.icon(onPressed: () => _mutate(context, ref, task, status: 'in_progress'), icon: const Icon(Icons.play_arrow), label: Text(tr(context, 'بدء المهمة', 'Start task'))),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: () => _mutate(context, ref, task, status: 'completed'), icon: const Icon(Icons.check_circle_outline), label: Text(tr(context, 'تحديد كمكتملة', 'Mark completed'))),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: () => _mutate(context, ref, task, status: 'cancelled'), icon: const Icon(Icons.cancel_outlined), label: Text(tr(context, 'إلغاء المهمة', 'Cancel task'))),
        const SizedBox(height: 12),
        if (canEditContent) Wrap(spacing: 8, children: ['low', 'normal', 'high', 'urgent'].map((p) => ChoiceChip(label: Text(switch (p) {'urgent' => tr(context, 'عاجلة', 'Urgent'), 'high' => tr(context, 'عالية', 'High'), 'low' => tr(context, 'منخفضة', 'Low'), _ => tr(context, 'عادية', 'Normal')}), selected: task.priority == p, onSelected: (_) => _mutate(context, ref, task, priority: p))).toList()),
      ],
      const SizedBox(height: 20), Text(tr(context, 'سجل النشاط', 'Activity history'), style: Theme.of(context).textTheme.titleLarge),
      FutureBuilder<List<Map<String, dynamic>>>(future: ref.read(apiProvider).taskActivity(task.id), builder: (context, snapshot) { if (snapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()); if (snapshot.hasError) return Text(snapshot.error.toString()); final items = snapshot.data ?? []; if (items.isEmpty) return Text(tr(context, 'لا يوجد نشاط مسجل.', 'No activity yet.'), style: Theme.of(context).textTheme.bodySmall); return Column(children: items.map((item) => ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.circle, size: 10, color: TaskatyColors.cyan), title: Text(_activityLabel(context, item['action'] as String? ?? 'updated')), subtitle: Text('${item['actorName'] ?? ''} · ${item['createdAt'] ?? ''}'))).toList()); }),
    ]);
    });
  }
  static String _activityLabel(BuildContext context, String action) => switch (action) {'created' => tr(context, 'تم إنشاء المهمة', 'Task created'), 'started' => tr(context, 'بدأ التنفيذ', 'Started'), 'completed' => tr(context, 'اكتملت المهمة', 'Completed'), 'cancelled' => tr(context, 'تم إلغاء المهمة', 'Cancelled'), 'assigned' => tr(context, 'تغير المسؤول', 'Assignee changed'), _ => tr(context, 'تم تحديث المهمة', 'Task updated')};
}

class TaskEditDialog extends ConsumerStatefulWidget {
  const TaskEditDialog({super.key, required this.task});
  final TaskItem task;
  @override ConsumerState<TaskEditDialog> createState() => _TaskEditDialogState();
}
class _TaskEditDialogState extends ConsumerState<TaskEditDialog> {
  late final TextEditingController _title = TextEditingController(text: widget.task.title);
  late final TextEditingController _description = TextEditingController(text: widget.task.description);
  late final TextEditingController _duration = TextEditingController(text: '${widget.task.durationMinutes}');
  late String _priority = widget.task.priority;
  String? _assignee;
  bool _loadedAssignee = false, _busy = false;
  String? _error;
  @override void dispose() { _title.dispose(); _description.dispose(); _duration.dispose(); super.dispose(); }
  Future<void> _save() async {
    final duration = parseDurationMinutes(_duration.text);
    final titleError = validateTaskTitle(_title.text, arabic: Localizations.localeOf(context).languageCode == 'ar');
    if (titleError != null || duration == null) { setState(() => _error = titleError ?? tr(context, 'المدة لازم تكون من دقيقة لسنة.', 'Duration must be between 1 minute and 1 year.')); return; }
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(apiProvider).updateTask(widget.task.id, version: widget.task.version, title: _title.text.trim(), description: _description.text.trim(), durationMinutes: duration, priority: _priority, assignedTo: _assignee, clearAssignee: _assignee == null);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) { if (mounted) setState(() { _busy = false; _error = e.toString(); }); }
  }
  @override Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersProvider(widget.task.teamId));
    return AlertDialog(title: Text(tr(context, 'تعديل المهمة', 'Edit task')), content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: _title, maxLength: 240, decoration: InputDecoration(labelText: tr(context, 'عنوان المهمة', 'Task title'))),
      const SizedBox(height: 10), TextField(controller: _description, maxLines: 3, maxLength: 4000, decoration: InputDecoration(labelText: tr(context, 'التفاصيل', 'Description'))),
      const SizedBox(height: 10), TextField(controller: _duration, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr(context, 'المدة بالدقائق', 'Duration in minutes'))),
      const SizedBox(height: 10),
      membersAsync.when(loading: () => const LinearProgressIndicator(), error: (e, _) => Text(e.toString()), data: (members) {
        if (!_loadedAssignee) { _assignee = widget.task.assignedTo; _loadedAssignee = true; }
        final choices = [...members];
        if (_assignee != null && !choices.any((m) => m.id == _assignee)) choices.add(Member(id: _assignee!, name: _assignee!, email: '', role: 'member'));
        return DropdownButtonFormField<String>(value: _assignee ?? '', decoration: InputDecoration(labelText: tr(context, 'المسؤول', 'Assignee')), items: [DropdownMenuItem(value: '', child: Text(tr(context, 'بدون مسؤول', 'Unassigned'))), ...choices.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name.isNotEmpty ? m.name : m.email)))], onChanged: (v) => setState(() => _assignee = v == '' ? null : v));
      }),
      const SizedBox(height: 10), DropdownButtonFormField<String>(value: _priority, decoration: InputDecoration(labelText: tr(context, 'الأولوية', 'Priority')), items: [('low', tr(context, 'منخفضة', 'Low')), ('normal', tr(context, 'عادية', 'Normal')), ('high', tr(context, 'عالية', 'High')), ('urgent', tr(context, 'عاجلة', 'Urgent'))].map((p) => DropdownMenuItem(value: p.$1, child: Text(p.$2))).toList(), onChanged: (v) => setState(() => _priority = v ?? 'normal')),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
    ]))), actions: [TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text(tr(context, 'إلغاء', 'Cancel'))), FilledButton(onPressed: _busy ? null : _save, child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(tr(context, 'حفظ', 'Save')))]);
  }
}

class _DetailRow extends StatelessWidget { const _DetailRow({required this.icon, required this.label, required this.value}); final IconData icon; final String label, value; @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [Icon(icon, size: 18, color: TaskatyColors.cyan), const SizedBox(width: 10), SizedBox(width: 95, child: Text(label, style: Theme.of(context).textTheme.bodySmall)), Expanded(child: Text(value, textAlign: TextAlign.end))])); }
