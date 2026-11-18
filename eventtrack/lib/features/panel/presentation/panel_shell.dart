import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../../domain/entities/user.dart';
import '../../auth/presentation/auth_controller.dart';
import 'panel_widgets.dart';

class PanelSection {
  const PanelSection(this.path, this.label, this.icon);

  final String path;
  final String label;
  final IconData icon;
}

/// Secciones visibles según el rol (§4.1.4).
List<PanelSection> sectionsFor(User user) => [
  const PanelSection('/resumen', 'Resumen', Icons.dashboard_outlined),
  const PanelSection('/eventos', 'Eventos', Icons.event_outlined),
  const PanelSection('/actividades', 'Actividades', Icons.checklist_outlined),
  const PanelSection('/evidencias', 'Evidencias', Icons.photo_library_outlined),
  if (user.isAdmin)
    const PanelSection('/usuarios', 'Usuarios', Icons.people_outline),
  const PanelSection('/reportes', 'Reportes', Icons.bar_chart_outlined),
];

/// Estructura del panel web: barra superior con navegación (escritorio) o
/// menú lateral (pantallas angostas, §3.2.2).
class PanelShell extends StatelessWidget {
  const PanelShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user!;
    final sections = sectionsFor(user);
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.primary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
        automaticallyImplyLeading: !wide,
        titleSpacing: wide ? 24 : 0,
        title: Row(
          children: [
            const Flexible(
              flex: 0,
              child: Text(
                'EVENTTRACK',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.action,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            if (wide) ...[
              const SizedBox(width: 24),
              // Con texto ampliado las pestañas se desplazan en vez de desbordarse.
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final s in sections)
                        _NavTab(
                          section: s,
                          selected: location.startsWith(s.path),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          _UserMenu(user: user),
          const SizedBox(width: 16),
        ],
      ),
      drawer: wide
          ? null
          : Drawer(
              child: ListView(
                children: [
                  const DrawerHeader(
                    decoration: BoxDecoration(color: AppColors.primary),
                    child: Center(child: BrandLogo(size: 64)),
                  ),
                  for (final s in sections)
                    ListTile(
                      leading: Icon(s.icon),
                      title: Text(s.label),
                      selected: location.startsWith(s.path),
                      onTap: () {
                        Navigator.pop(context);
                        context.go(s.path);
                      },
                    ),
                ],
              ),
            ),
      body: child,
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({required this.section, required this.selected});

  final PanelSection section;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: () => context.go(section.path),
        child: Container(
          height: kToolbarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColors.action : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Text(
            section.label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              color: selected ? AppColors.action : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _UserMenu extends StatelessWidget {
  const _UserMenu({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Cuenta',
      offset: const Offset(0, kToolbarHeight),
      onSelected: (value) async {
        if (value != 'logout') return;
        final ok = await confirmAction(
          context,
          title: 'Cerrar sesión',
          message: '¿Deseas salir del panel?',
          confirmLabel: 'Cerrar sesión',
        );
        if (ok && context.mounted) {
          await context.read<AuthController>().logout();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Text(
            '${user.fullName}\n${user.email}',
            style: const TextStyle(color: AppColors.textPrimary),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, size: 18),
              SizedBox(width: 8),
              Text('Cerrar sesión'),
            ],
          ),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.tint(AppColors.primary),
            child: Text(
              user.initials,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (MediaQuery.sizeOf(context).width >= 600)
            Text(
              '${user.fullName.split(' ').first} · ${user.role.label}',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}

/// El responsable registra evidencias desde Android, no desde la web.
class ResponsibleOnWebScreen extends StatelessWidget {
  const ResponsibleOnWebScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SectionCard(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.phone_android,
                  size: 48,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Hola, ${auth.user?.fullName ?? ''}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'El panel web es para organizadores, supervisores y administradores. '
                  'Consulta tus actividades y registra evidencias desde la aplicación '
                  'EventTrack para Android.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: auth.logout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Cerrar sesión'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
