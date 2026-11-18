import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/assignment.dart';
import '../../features/activities/presentation/my_activities_screen.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/profile_screen.dart';
import '../../features/evidence/presentation/activity_detail_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/sync/application/sync_service.dart';
import '../../features/sync/presentation/sync_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/brand_logo.dart';

/// Navegación con protección de rutas según sesión (§4.5.2, go_router).
GoRouter buildRouter(AuthController auth) {
  final rootKey = GlobalKey<NavigatorState>();

  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: '/home',
    refreshListenable: auth,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      switch (auth.status) {
        case AuthStatus.unknown:
          return loc == '/splash' ? null : '/splash';
        case AuthStatus.unauthenticated:
          return loc == '/login' ? null : '/login';
        case AuthStatus.authenticated:
          return (loc == '/login' || loc == '/splash') ? '/home' : null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const _SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/profile',
        parentNavigatorKey: rootKey,
        builder: (_, _) => const ProfileScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/activities',
                builder: (_, _) => const MyActivitiesScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: rootKey,
                    builder: (_, state) => ActivityDetailRoute(
                      assignmentId: state.pathParameters['id']!,
                      initial: state.extra is Assignment
                          ? state.extra! as Assignment
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/sync', builder: (_, _) => const SyncScreen()),
            ],
          ),
        ],
      ),
    ],
  );
}

/// Navegación inferior: Inicio, Actividades, Pendientes (§4.3.6).
class _AppShell extends StatelessWidget {
  const _AppShell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final waiting = sync.pendingCount + sync.failedCount;

    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          const NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: 'Actividades',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: waiting > 0,
              backgroundColor: sync.failedCount > 0
                  ? AppColors.error
                  : AppColors.warning,
              label: Text('$waiting'),
              child: const Icon(Icons.sync_outlined),
            ),
            selectedIcon: const Icon(Icons.sync),
            label: 'Pendientes',
          ),
        ],
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: AppColors.primary,
    body: Center(child: BrandLogo(size: 88)),
  );
}
