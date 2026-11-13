import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'config.dart';
import 'notification_adapter.dart';
import 'screens/auth_screens.dart';
import 'screens/notification_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/task_screens.dart';
import 'screens/team_screens.dart';
import 'screens/voice_screen.dart';
import 'state.dart';
import 'theme.dart';

String tr(BuildContext context, String ar, String en) =>
    Localizations.localeOf(context).languageCode == 'ar' ? ar : en;

String? authRedirectForPath({
  required bool configured,
  required bool signedIn,
  required bool emailVerified,
  required String path,
}) {
  final authPath =
      path == '/login' ||
      path == '/register' ||
      path == '/forgot' ||
      path == '/verify';
  if (!configured) return authPath ? null : '/login';
  if (!signedIn && !authPath) return '/login';
  if (signedIn && !emailVerified && path != '/verify') return '/verify';
  if (signedIn && emailVerified && authPath) return '/home';
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = AuthRefreshListenable();
  ref.onDispose(refresh.dispose);
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final path = state.matchedLocation;
      final configured = AppConfig.firebaseConfigured;
      final user = configured ? FirebaseAuth.instance.currentUser : null;
      return authRedirectForPath(
        configured: configured,
        signedIn: user != null,
        emailVerified: user?.emailVerified ?? false,
        path: path,
      );
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(
        path: '/forgot',
        builder: (_, __) => const ForgotPasswordScreen(),
      ),
      GoRoute(path: '/verify', builder: (_, __) => const VerifyEmailScreen()),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const DashboardScreen()),
          GoRoute(path: '/tasks', builder: (_, __) => const TaskListScreen()),
          GoRoute(
            path: '/notifications',
            builder: (_, __) => const NotificationScreen(),
          ),
          GoRoute(path: '/team', builder: (_, __) => const TeamScreen()),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/create',
            builder: (_, state) =>
                TaskCreateScreen(transcript: state.extra as String?),
          ),
          GoRoute(path: '/voice', builder: (_, __) => const VoiceScreen()),
          GoRoute(
            path: '/voice/review',
            builder: (_, state) =>
                VoiceCommandReviewScreen(transcript: state.extra as String),
          ),
          GoRoute(
            path: '/task/:id',
            builder: (_, state) =>
                TaskDetailsScreen(taskId: state.pathParameters['id']!),
          ),
        ],
      ),
    ],
  );
});

class AuthRefreshListenable extends ChangeNotifier {
  AuthRefreshListenable() {
    if (AppConfig.firebaseConfigured)
      _subscription = FirebaseAuth.instance.authStateChanges().listen(
        (_) => notifyListeners(),
      );
  }
  StreamSubscription<User?>? _subscription;
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

class TaskatyApp extends ConsumerWidget {
  const TaskatyApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      title: 'Taskaty',
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTaskatyTheme(),
      darkTheme: buildTaskatyTheme(brightness: Brightness.dark),
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child, required this.location});
  final Widget child;
  final String location;
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  StreamSubscription<RemoteMessage>? _opened;
  StreamSubscription<RemoteMessage>? _foreground;
  StreamSubscription<String>? _tokenRefresh;
  @override
  void initState() {
    super.initState();
    if (AppConfig.firebaseConfigured) {
      if (!kIsWeb)
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _configureMessaging(),
        );
      _opened = FirebaseMessaging.onMessageOpenedApp.listen(_openMessage);
      _foreground = FirebaseMessaging.onMessage.listen((message) {
        ref.invalidate(notificationsProvider);
        final notification = message.notification;
        if (notification != null) {
          showForegroundNotification(
            message,
            notification.title ?? tr(context, 'تنبيه Taskaty', 'Taskaty alert'),
            notification.body ??
                tr(context, 'وصلك تحديث جديد', 'You have a new update'),
          );
        }
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                message.notification?.body ??
                    tr(context, 'وصلك تحديث جديد', 'You have a new update'),
              ),
            ),
          );
      });
      _tokenRefresh = FirebaseMessaging.instance.onTokenRefresh.listen((
        token,
      ) async {
        try {
          await ref.read(apiProvider).registerFcmToken(token);
        } catch (_) {
          /* Retry after next session. */
        }
      });
    }
  }

  Future<void> _configureMessaging() async {
    try {
      final token = await configureNotifications((taskId) {
        if (mounted) context.go('/task/${Uri.encodeComponent(taskId)}');
        ref.invalidate(notificationsProvider);
      });
      if (token != null) await ref.read(apiProvider).registerFcmToken(token);
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _openMessage(initial);
    } catch (_) {
      /* The app remains usable when push setup or permission is unavailable. */
    }
  }

  void _openMessage(RemoteMessage message) {
    final taskId = message.data['taskId'];
    if (taskId is String && taskId.isNotEmpty && mounted)
      context.go('/task/${Uri.encodeComponent(taskId)}');
    ref.invalidate(notificationsProvider);
  }

  @override
  void dispose() {
    _opened?.cancel();
    _foreground?.cancel();
    _tokenRefresh?.cancel();
    super.dispose();
  }

  int get _selectedIndex => widget.location.startsWith('/tasks')
      ? 1
      : widget.location.startsWith('/team')
      ? 2
      : widget.location.startsWith('/notifications')
      ? 3
      : 0;
  @override
  Widget build(BuildContext context) {
    final wideLayout = MediaQuery.sizeOf(context).width >= 700;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.bolt, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Taskaty',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: tr(context, 'الإعدادات', 'Settings'),
            onPressed: () => context.go('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Row(
        children: [
          if (wideLayout) ...[
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _goToDestination,
              labelType: NavigationRailLabelType.all,
              destinations: [
                NavigationRailDestination(
                  icon: const Icon(Icons.space_dashboard_outlined),
                  selectedIcon: const Icon(Icons.space_dashboard),
                  label: Text(tr(context, 'الرئيسية', 'Home')),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.checklist_outlined),
                  selectedIcon: const Icon(Icons.checklist),
                  label: Text(tr(context, 'المهام', 'Tasks')),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.groups_outlined),
                  selectedIcon: const Icon(Icons.groups),
                  label: Text(tr(context, 'الفريق', 'Team')),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.notifications_none),
                  selectedIcon: const Icon(Icons.notifications),
                  label: Text(tr(context, 'التنبيهات', 'Alerts')),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
          ],
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton:
          widget.location == '/home' || widget.location == '/tasks'
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/voice'),
              icon: const Icon(Icons.mic),
              label: Text(tr(context, 'مهمة بالصوت', 'Voice task')),
            )
          : null,
      bottomNavigationBar: wideLayout
          ? null
          : NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _goToDestination,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.space_dashboard_outlined),
                  selectedIcon: const Icon(Icons.space_dashboard),
                  label: tr(context, 'الرئيسية', 'Home'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.checklist_outlined),
                  selectedIcon: const Icon(Icons.checklist),
                  label: tr(context, 'المهام', 'Tasks'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.groups_outlined),
                  selectedIcon: const Icon(Icons.groups),
                  label: tr(context, 'الفريق', 'Team'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.notifications_none),
                  selectedIcon: const Icon(Icons.notifications),
                  label: tr(context, 'التنبيهات', 'Alerts'),
                ),
              ],
            ),
    );
  }

  void _goToDestination(int index) =>
      context.go(['/home', '/tasks', '/team', '/notifications'][index]);
}
