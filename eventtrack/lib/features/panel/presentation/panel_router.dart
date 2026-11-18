import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../../domain/entities/user.dart';
import '../../activities/presentation/panel_activities_page.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/login_screen.dart';
import '../../events/presentation/events_page.dart';
import '../../evidence/presentation/panel/evidences_page.dart';
import '../../reports/presentation/dashboard_page.dart';
import '../../reports/presentation/reports_page.dart';
import '../../users/presentation/users_page.dart';
import 'panel_shell.dart';
import 'panel_widgets.dart';

/// Rutas del panel web con protección por sesión y por rol (§4.5.2).
GoRouter buildPanelRouter(AuthController auth) {
  return GoRouter(
    initialLocation: '/resumen',
    refreshListenable: auth,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      switch (auth.status) {
        case AuthStatus.unknown:
          return loc == '/splash' ? null : '/splash';
        case AuthStatus.unauthenticated:
          return loc == '/login' ? null : '/login';
        case AuthStatus.authenticated:
          final user = auth.user!;
          if (user.role == UserRole.responsible) {
            return loc == '/solo-android' ? null : '/solo-android';
          }
          if (loc == '/login' || loc == '/splash' || loc == '/solo-android') {
            return '/resumen';
          }
          // La interfaz oculta Usuarios; el backend igual responde 403.
          if (loc == '/usuarios' && !user.isAdmin) return '/resumen';
          return null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const _Splash()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/solo-android',
        builder: (_, _) => const ResponsibleOnWebScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            PanelShell(location: state.matchedLocation, child: child),
        routes: [
          _page('/resumen', const DashboardPage()),
          _page('/eventos', const EventsPage()),
          _page('/actividades', const PanelActivitiesPage()),
          _page('/evidencias', const EvidencesPage()),
          _page('/usuarios', const UsersPage()),
          _page('/reportes', const ReportsPage()),
        ],
      ),
    ],
  );
}

/// Sin animación entre secciones, como en una aplicación web.
GoRoute _page(String path, Widget page) => GoRoute(
  path: path,
  pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: page),
);

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: AppColors.primary,
    body: Center(child: BrandLogo(size: 88)),
  );
}
