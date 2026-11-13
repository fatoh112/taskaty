import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../app.dart';
import '../state.dart';
import '../theme.dart';
import 'common.dart';

class NotificationScreen extends ConsumerWidget {
  const NotificationScreen({super.key});
  Future<void> _refresh(WidgetRef ref) async =>
      ref.invalidate(notificationsProvider);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    return PollingRefresh(
      refresh: () => _refresh(ref),
      child: notifications.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorPanel(message: e.toString(), onRetry: () => _refresh(ref)),
        data: (page) => RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: page.items.isEmpty
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
                  children: [
                    ScreenTitle(
                      tr(context, 'التنبيهات', 'Notifications'),
                      subtitle: tr(
                        context,
                        'كل تحديثات الفريق في مكان واحد.',
                        'Team updates in one place.',
                      ),
                    ),
                    SizedBox(height: MediaQuery.sizeOf(context).height * .12),
                    EmptyPanel(
                      icon: Icons.notifications_none,
                      title: tr(context, 'مفيش تنبيهات', 'No notifications'),
                      body: tr(
                        context,
                        'تنبيهات الفريق والمهام هتظهر هنا.',
                        'Team and task notifications will appear here.',
                      ),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
                  children: [
                    ScreenTitle(
                      tr(context, 'التنبيهات', 'Notifications'),
                      subtitle: tr(
                        context,
                        '${page.unreadCount} غير مقروء',
                        '${page.unreadCount} unread',
                      ),
                    ),
                    ...page.items.map(
                      (n) => Card(
                        child: ListTile(
                          onTap: () async {
                            if (n.readAt == null) {
                              try {
                                await ref.read(apiProvider).markRead(n.id);
                                ref.invalidate(notificationsProvider);
                              } catch (_) {}
                            }
                            if (n.taskId != null && context.mounted)
                              context.push(
                                '/task/${Uri.encodeComponent(n.taskId!)}',
                              );
                          },
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color:
                                  (n.readAt == null
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : context.taskatyMuted)
                                      .withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              _notificationIcon(n.type),
                              color: n.readAt == null
                                  ? Theme.of(context).colorScheme.primary
                                  : context.taskatyMuted,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  n.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (n.readAt == null)
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${n.body}\n${MaterialLocalizations.of(context).formatMediumDate(n.createdAt)} · ${TimeOfDay.fromDateTime(n.createdAt).format(context)}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          isThreeLine: true,
                          trailing: n.taskId == null
                              ? null
                              : const Icon(Icons.chevron_right),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  static IconData _notificationIcon(String type) => switch (type) {
    'overdue' => Icons.warning_amber_rounded,
    'reminder' => Icons.alarm,
    'assignment' => Icons.person_add_alt,
    'completion' => Icons.task_alt,
    _ => Icons.notifications_outlined,
  };
}
