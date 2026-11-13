import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';

import '../api.dart';
import '../config.dart';
import '../notification_adapter.dart';
import '../app.dart';
import '../state.dart';
import '../theme.dart';
import 'common.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 30), children: [
      ScreenTitle(tr(context, 'الإعدادات', 'Settings'), subtitle: tr(context, 'الحساب واللغة وحالة الاتصال.', 'Account, language, and connection status.')),
      Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.person_outline)), title: Text(user?.displayName ?? tr(context, 'حساب Taskaty', 'Taskaty account')), subtitle: Text(user?.email ?? ''), trailing: Icon(user?.emailVerified == true ? Icons.verified : Icons.info_outline, color: user?.emailVerified == true ? TaskatyColors.green : TaskatyColors.amber))),
      const SizedBox(height: 10),
      Card(child: ListTile(leading: const Icon(Icons.translate, color: TaskatyColors.cyan), title: Text(tr(context, 'لغة التطبيق', 'App language')), subtitle: Text(Localizations.localeOf(context).languageCode == 'ar' ? 'العربية (مصر)' : 'English'), trailing: OutlinedButton(onPressed: () => ref.read(localeProvider.notifier).toggle(), child: Text(tr(context, 'English', 'العربية'))))),
      const SizedBox(height: 10),
      _Diagnostics(),
      const SizedBox(height: 10),
      if (kIsWeb) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr(context, 'تنبيهات المتصفح', 'Browser notifications'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(AppConfig.webVapidKey.isEmpty
            ? tr(context, 'مفتاح Web Push العام غير متوفر بعد. سجل التنبيهات داخل التطبيق يعمل.', 'A public Web Push key is not configured yet. In-app notification history still works.')
            : tr(context, 'فعّل تنبيهات المتصفح لهذا الجهاز.', 'Enable browser notifications on this device.'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        FilledButton(onPressed: AppConfig.webVapidKey.isEmpty ? null : () async {
          try {
            final token = await configureNotifications((_) {});
            if (token == null) throw StateError('Notification permission was not granted.');
            await ref.read(apiProvider).registerFcmToken(token);
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'تم تسجيل المتصفح للتنبيهات.', 'Browser notifications enabled.'))));
          } catch (error) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
          }
        }, child: Text(tr(context, 'تفعيل التنبيهات', 'Enable notifications'))),
      ]))),
      if (kIsWeb) const SizedBox(height: 10),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr(context, 'حول الخصوصية', 'Privacy'), style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 8), Text(tr(context, 'الصوت يتحول لنص بخدمة التعرف على الكلام في Android؛ حسب الجهاز قد يُرسل الصوت لمزود خدمة التعرف. ما بنستخدمش خدمة ذكاء اصطناعي مدفوعة. مواعيد المهام وسجل التنبيهات محفوظة في خادم الفريق.', 'Speech is transcribed by Android’s speech recognition service; depending on device settings, audio may be sent to its provider. Task deadlines and notification history are stored by the team backend.'), style: Theme.of(context).textTheme.bodySmall)]))),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: () async {
        try {
          final token = await currentNotificationToken();
          if (token != null) await ref.read(apiProvider).unregisterFcmToken(token);
        } catch (_) { /* Sign-out still works when offline or push is unavailable. */ }
        await FirebaseAuth.instance.signOut();
        ref.read(activeTeamProvider.notifier).select(null);
        ref.invalidate(teamsProvider);
        if (context.mounted) context.go('/login');
      }, icon: const Icon(Icons.logout), label: Text(tr(context, 'تسجيل الخروج', 'Sign out'))),
      Padding(padding: const EdgeInsets.only(top: 18), child: Text('Taskaty 1.0.0 · ${tr(context, 'متصل بخدمات مجانية', 'Free-tier services')}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall)),
    ]);
  }
}

class _Diagnostics extends ConsumerWidget {
  @override Widget build(BuildContext context, WidgetRef ref) {
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [const Icon(Icons.monitor_heart_outlined, color: TaskatyColors.cyan), const SizedBox(width: 10), Expanded(child: Text(tr(context, 'حالة الخدمة', 'Service health'), style: Theme.of(context).textTheme.titleMedium)), TextButton(onPressed: () => ref.invalidate(_healthProvider), child: Text(tr(context, 'تحديث', 'Refresh')))]),
      Consumer(builder: (context, ref, _) { final health = ref.watch(_healthProvider); return health.when(loading: () => const LinearProgressIndicator(), error: (e, _) => Text(e.toString(), style: const TextStyle(color: TaskatyColors.amber)), data: (data) { final scheduler = data['scheduler'] as Map<String, dynamic>? ?? {}; return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${tr(context, 'API', 'API')}: ${data['status'] ?? '—'}', style: const TextStyle(color: TaskatyColors.green)), const SizedBox(height: 4), Text('${tr(context, 'وقت الخادم', 'Server time')}: ${data['serverTime'] ?? '—'}', style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 4), Text('${tr(context, 'آخر تشغيل للمجدول', 'Last scheduler run')}: ${scheduler['lastFinishedAt'] ?? tr(context, 'لم يصل تشغيل بعد', 'No run yet')}', style: Theme.of(context).textTheme.bodySmall), if (scheduler['delaySeconds'] != null) Text('${tr(context, 'تأخير المجدول', 'Scheduler delay')}: ${scheduler['delaySeconds']}s', style: Theme.of(context).textTheme.bodySmall)]); }); }),
      const SizedBox(height: 8), Text(tr(context, 'التطبيق يزامن أثناء استخدام الشاشات. التنبيه يعتمد على مجدول الخادم، وليس مؤقتًا على الهاتف.', 'The app syncs while screens are active. Deadline alerts use the server scheduler, not a phone timer.'), style: Theme.of(context).textTheme.bodySmall),
    ])));
  }
}
final _healthProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.watch(apiProvider).health());
