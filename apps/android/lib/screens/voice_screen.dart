import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../api.dart';
import '../app.dart';
import '../models.dart';
import '../state.dart';
import '../task_parser.dart';
import '../theme.dart';
import 'common.dart';
import 'team_screens.dart';

class VoiceScreen extends StatefulWidget { const VoiceScreen({super.key}); @override State<VoiceScreen> createState() => _VoiceScreenState(); }
class _VoiceScreenState extends State<VoiceScreen> {
  final SpeechToText _speech = SpeechToText(); final TextEditingController _transcript = TextEditingController();
  bool _available = false, _listening = false, _initializing = true; String? _error, _status;
  @override void initState() { super.initState(); _initialize(); }
  Future<void> _initialize() async {
    try {
      final supported = await _speech.initialize(onStatus: (s) { if (mounted) setState(() { _status = s; _listening = s == 'listening'; }); }, onError: (e) { if (mounted) setState(() { _error = e.errorMsg; _listening = false; }); }, debugLogging: false);
      if (mounted) setState(() { _available = supported; _initializing = false; if (!supported) _error = tr(context, 'التعرف على الكلام مش متاح على الجهاز. اكتب المهمة يدويًا.', 'Speech recognition is unavailable. Enter the task manually.'); });
    } catch (_) { if (mounted) setState(() { _available = false; _initializing = false; _error = tr(context, 'التعرف على الكلام مش متاح. تقدر تكمل بالكتابة.', 'Speech recognition is unavailable. You can continue by typing.'); }); }
  }
  Future<void> _listen() async {
    if (_listening) { await _speech.stop(); if (mounted) setState(() => _listening = false); return; }
    setState(() => _error = null);
    try {
      final locales = await _speech.locales();
      final egyptian = locales.where((l) => l.localeId.toLowerCase().replaceAll('-', '_').startsWith('ar_eg')).toList();
      final anyArabic = locales.where((l) => l.localeId.toLowerCase().startsWith('ar')).toList();
      final arabic = egyptian.isNotEmpty ? egyptian.first : anyArabic.isNotEmpty ? anyArabic.first : null;
      await _speech.listen(
        onResult: (result) { if (mounted) setState(() => _transcript.text = result.recognizedWords); },
        localeId: arabic?.localeId ?? 'ar_EG',
        listenFor: const Duration(seconds: 55),
        pauseFor: const Duration(seconds: 4),
        listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: true, listenMode: ListenMode.dictation),
      );
      if (mounted) setState(() => _listening = true);
    } catch (e) { if (mounted) setState(() { _error = tr(context, 'ماقدرناش نبدأ التسجيل. اتأكد من إذن الميكروفون وخدمة التعرف على الكلام.', 'Could not start recognition. Check microphone permission and your speech service.'); _listening = false; }); }
  }
  @override void dispose() { _speech.cancel(); _transcript.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'إنشاء بالصوت', 'Voice task'))),
    body: ListView(padding: const EdgeInsets.all(22), children: [
      const SizedBox(height: 12),
      Center(child: AnimatedContainer(duration: const Duration(milliseconds: 250), width: 148, height: 148, decoration: BoxDecoration(color: (_listening ? const Color(0xFF5D2832) : TaskatyColors.cyan.withValues(alpha: .12)), shape: BoxShape.circle, border: Border.all(color: _listening ? const Color(0xFFFF7777) : TaskatyColors.cyan.withValues(alpha: .3), width: 2)), child: Icon(_listening ? Icons.mic : Icons.mic_none_rounded, color: _listening ? const Color(0xFFFF7777) : TaskatyColors.cyan, size: 58))),
      const SizedBox(height: 22), Text(_listening ? tr(context, 'سامعك… اتكلم دلوقتي', 'Listening… speak now') : tr(context, 'قول المهمة بطريقتك', 'Say the task in your own words'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8), Text(tr(context, 'مثال: أحمد يخلص تصميم الموقع خلال أربع ساعات.', 'Example: Assign the design to Ahmed for four hours.'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 24),
      FilledButton.icon(onPressed: !_available || _initializing ? null : _listen, icon: Icon(_listening ? Icons.stop : Icons.mic), label: Text(_initializing ? tr(context, 'جاري تجهيز الميكروفون…', 'Preparing speech…') : _listening ? tr(context, 'إيقاف التسجيل', 'Stop recording') : tr(context, 'ابدأ التسجيل', 'Start recording'))),
      if (_status != null) Padding(padding: const EdgeInsets.only(top: 7), child: Text(_status!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall)),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: TaskatyColors.amber), textAlign: TextAlign.center)),
      const SizedBox(height: 22),
      Text(tr(context, 'النص المسموع — راجعه وعدّله', 'Transcript — review and edit'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      TextField(controller: _transcript, onChanged: (_) => setState(() {}), minLines: 3, maxLines: 6, textDirection: TextDirection.rtl, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(hintText: tr(context, 'اكتب المهمة يدويًا لو التعرف على الصوت مش متاح…', 'Type the task here if speech recognition is unavailable…'), alignLabelWithHint: true)),
      const SizedBox(height: 14),
      OutlinedButton.icon(onPressed: _transcript.text.isEmpty ? null : () { _transcript.clear(); setState(() {}); }, icon: const Icon(Icons.refresh), label: Text(tr(context, 'مسح وإعادة المحاولة', 'Clear and retry'))),
      const SizedBox(height: 9),
      FilledButton.icon(onPressed: _transcript.text.trim().isEmpty ? null : () => context.push('/voice/review', extra: _transcript.text.trim()), icon: const Icon(Icons.fact_check_outlined), label: Text(tr(context, 'مراجعة المهمة وتأكيدها', 'Review and confirm'))),
      const SizedBox(height: 12), Text(tr(context, 'التسجيل لا ينشئ مهمة تلقائيًا. هتراجع العنوان والمسؤول والمدة قبل الحفظ.', 'Recording never creates a task automatically. Review its title, assignee, and deadline before saving.'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
    ]),
  );
}

class VoiceCommandReviewScreen extends ConsumerStatefulWidget {
  const VoiceCommandReviewScreen({super.key, required this.transcript});
  final String transcript;
  @override ConsumerState<VoiceCommandReviewScreen> createState() => _VoiceCommandReviewScreenState();
}

class _VoiceCommandReviewScreenState extends ConsumerState<VoiceCommandReviewScreen> {
  String? _selectedTaskId; bool _busy = false, _redirectingToCreate = false;
  @override Widget build(BuildContext context) {
    final parsed = TaskParser.parse(widget.transcript, const []);
    if (parsed.intent == 'create') {
      if (!_redirectingToCreate) {
        _redirectingToCreate = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go('/create', extra: widget.transcript);
        });
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final teams = ref.watch(teamsProvider);
    final verb = switch (parsed.intent) {'completed' => tr(context, 'إكمال', 'Complete'), 'in_progress' => tr(context, 'بدء', 'Start'), _ => tr(context, 'إلغاء', 'Cancel')};
    return Scaffold(appBar: AppBar(title: Text(tr(context, 'مراجعة تحديث صوتي', 'Review voice update'))), body: teams.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorPanel(message: e.toString(), onRetry: () => ref.invalidate(teamsProvider)),
      data: (teamList) {
        if (teamList.isEmpty) return const TeamOnboardingScreen();
        final active = ref.watch(activeTeamProvider);
        final team = teamList.where((t) => t.id == active?.id).firstOrNull ?? teamList.first;
        final allTasks = ref.watch(taskListProvider(TaskQuery(team.id)));
        return allTasks.when(loading: () => const Center(child: CircularProgressIndicator()), error: (e, _) => ErrorPanel(message: e.toString()), data: (tasks) {
          final activeTasks = tasks.where((t) => t.active).toList();
          final phrase = TaskParser.normalizeForMatch(parsed.title);
          final suggested = activeTasks.where((task) {
            final title = TaskParser.normalizeForMatch(task.title);
            return phrase.isNotEmpty && (title.contains(phrase) || phrase.contains(title));
          }).toList();
          final candidates = suggested.isNotEmpty ? suggested : activeTasks;
          return ListView(padding: const EdgeInsets.all(20), children: [
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.transcript, style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 10), Text('${tr(context, 'الأمر', 'Action')}: $verb', style: const TextStyle(color: TaskatyColors.cyan, fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text('${tr(context, 'الاسم المسموع', 'Matched phrase')}: ${parsed.title}', style: Theme.of(context).textTheme.bodySmall)]))),
            const SizedBox(height: 16),
            Text(suggested.isNotEmpty ? tr(context, 'اختار المهمة المقصودة', 'Choose the task to update') : tr(context, 'ما لقيناش تطابق واضح. اختار المهمة بنفسك.', 'No confident match. Select the task yourself.'), style: Theme.of(context).textTheme.titleMedium),
            if (candidates.isEmpty) Padding(padding: const EdgeInsets.only(top: 20), child: EmptyPanel(icon: Icons.task_alt, title: tr(context, 'مفيش مهام نشطة', 'No active tasks'), body: tr(context, 'مفيش مهمة قابلة للتحديث في الفريق.', 'There are no open team tasks to update.'))),
            ...candidates.map((task) => Card(child: RadioListTile<String>(value: task.id, groupValue: _selectedTaskId, onChanged: (id) => setState(() => _selectedTaskId = id), title: Text(task.title), subtitle: Text('${task.status} · ${MaterialLocalizations.of(context).formatMediumDate(task.dueAt)}')))),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _busy || _selectedTaskId == null ? null : () => _apply(parsed.intent, tasks), icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_circle_outline), label: Text(tr(context, 'تأكيد $verb المهمة', 'Confirm $verb task'))),
          ]);
        });
      },
    ));
  }

  Future<void> _apply(String intent, List<TaskItem> tasks) async {
    final task = tasks.where((item) => item.id == _selectedTaskId).firstOrNull;
    if (task == null) return;
    final status = intent;
    final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text(tr(context, 'تأكيد تحديث المهمة؟', 'Confirm task update?')), content: Text('${task.title}\n${tr(context, 'الحالة الجديدة', 'New status')}: $status'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr(context, 'رجوع', 'Back'))), FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr(context, 'تأكيد', 'Confirm')))]));
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).updateTask(task.id, version: task.version, status: status);
      ref.invalidate(taskProvider(task.id)); ref.invalidate(taskListProvider(TaskQuery(task.teamId))); ref.invalidate(dashboardProvider(task.teamId)); ref.invalidate(notificationsProvider);
      if (mounted) context.go('/task/${task.id}');
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
    if (mounted) setState(() => _busy = false);
  }
}
