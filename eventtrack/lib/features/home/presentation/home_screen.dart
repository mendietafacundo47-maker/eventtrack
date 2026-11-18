import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../domain/entities/assignment.dart';
import '../../activities/presentation/activities_controller.dart';
import '../../activities/presentation/my_activities_screen.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../sync/application/sync_service.dart';

/// Inicio: resumen del trabajo asignado y del estado de sincronización.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;
    final activities = context.watch<ActivitiesController>();
    final sync = context.watch<SyncService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('EVENTTRACK'),
        actions: const [ProfileButton()],
      ),
      body: RefreshIndicator(
        onRefresh: activities.load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Hola, ${user?.fullName.split(' ').first ?? ''}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              user?.role.label ?? '',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            if (AppConfig.useMockApi) ...[
              const InfoBanner(
                icon: Icons.science_outlined,
                message:
                    'Modo demostración: los datos provienen de un '
                    'backend simulado.',
              ),
              const SizedBox(height: 12),
            ],
            InfoBanner(
              icon: sync.isOnline ? Icons.wifi : Icons.wifi_off,
              color: sync.isOnline ? AppColors.success : AppColors.warning,
              message: sync.isOnline
                  ? 'Conectado. Las evidencias se envían automáticamente.'
                  : 'Sin conexión. Puedes seguir registrando evidencias.',
            ),
            const SizedBox(height: 20),
            const _SectionTitle('Mis actividades'),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.7,
              children: [
                _StatCard(
                  label: 'Pendientes',
                  value: activities.countBy(ActivityStatus.pending),
                  color: AppColors.warning,
                  icon: Icons.schedule,
                ),
                _StatCard(
                  label: 'En ejecución',
                  value: activities.countBy(ActivityStatus.inProgress),
                  color: AppColors.action,
                  icon: Icons.play_circle_outline,
                ),
                _StatCard(
                  label: 'Enviadas',
                  value: activities.countBy(ActivityStatus.submitted),
                  color: AppColors.primary,
                  icon: Icons.outbox_outlined,
                ),
                _StatCard(
                  label: 'Completadas',
                  value: activities.countBy(ActivityStatus.completed),
                  color: AppColors.success,
                  icon: Icons.check_circle_outline,
                ),
              ],
            ),
            const SizedBox(height: 20),
            const _SectionTitle('Evidencias en este dispositivo'),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                onTap: () => context.go('/sync'),
                leading: Icon(
                  sync.failedCount > 0
                      ? Icons.error_outline
                      : sync.pendingCount > 0
                      ? Icons.sync_problem
                      : Icons.cloud_done_outlined,
                  color: sync.failedCount > 0
                      ? AppColors.error
                      : sync.pendingCount > 0
                      ? AppColors.warning
                      : AppColors.success,
                ),
                title: Text(
                  '${sync.pendingCount} pendientes · '
                  '${sync.syncedCount} sincronizadas'
                  '${sync.failedCount > 0 ? ' · ${sync.failedCount} con error' : ''}',
                ),
                subtitle: const Text('Ver cola de sincronización'),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => context.go('/activities'),
              icon: const Icon(Icons.assignment_outlined),
              label: const Text('VER MIS ACTIVIDADES'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: 15,
      color: AppColors.textPrimary,
    ),
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final int value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.tint(color),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
