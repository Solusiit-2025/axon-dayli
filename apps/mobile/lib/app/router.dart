import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/assets/asset_detail_screen.dart';
import '../features/assets/assets_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/calendar/calendar_screen.dart';
import '../features/documents/documents_screen.dart';
import '../features/finance/finance_screen.dart';
import '../features/finance/wallets_screen.dart';
import '../features/planning/planning_screen.dart';
import '../features/reminders/reminders_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/settings/more_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/tasks/task_detail_screen.dart';
import '../features/tasks/tasks_screen.dart';
import '../features/today/today_screen.dart';
import 'auth_controller.dart';
import 'providers.dart';

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(20)),
                child: Image(
                  image: AssetImage('assets/branding/logo_axon.png'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Axon Dayli',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 24),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: '/today',
    refreshListenable: refresh,
    redirect: (context, state) {
      final status = ref.read(authControllerProvider).status;
      final location = state.matchedLocation;

      if (status == AuthStatus.loading) {
        return location == '/splash' ? null : '/splash';
      }
      if (status == AuthStatus.signedOut) {
        return location == '/login' ? null : '/login';
      }
      if (location == '/login' || location == '/splash') return '/today';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const _SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/calendar', builder: (_, __) => const CalendarScreen()),
      GoRoute(path: '/wallets', builder: (_, __) => const WalletsScreen()),
      GoRoute(path: '/reminders', builder: (_, __) => const RemindersScreen()),
      GoRoute(path: '/planning', builder: (_, __) => const PlanningScreen()),
      GoRoute(path: '/reports', builder: (_, __) => const ReportsScreen()),
      GoRoute(path: '/documents', builder: (_, __) => const DocumentsScreen()),
      GoRoute(
        path: '/task/:id',
        builder: (_, state) =>
            TaskDetailScreen(taskId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/asset/:id',
        builder: (_, state) =>
            AssetDetailScreen(assetId: state.pathParameters['id']!),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/today', builder: (_, __) => const TodayScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/tasks', builder: (_, __) => const TasksScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/finance',
                builder: (_, __) => const FinanceScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/assets',
                builder: (_, __) => const AssetsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/more', builder: (_, __) => const MoreScreen()),
            ],
          ),
        ],
      ),
    ],
  );

  // Ketuk notifikasi pengingat → buka detail tugas terkait.
  ref.read(notificationsProvider).onNotificationTap = (payload) {
    if (payload.isEmpty) return;
    router.push('/task/$payload');
  };

  return router;
});

/// Menghubungkan perubahan auth ke MaterialApp agar redirect langsung berlaku.
class RouterRefreshNotifier extends ChangeNotifier {
  RouterRefreshNotifier(Ref ref) {
    ref.listen(authControllerProvider, (_, __) => notifyListeners());
  }
}
