import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../domain/entities/assignment.dart';
import '../../../domain/entities/local_evidence.dart';
import '../../sync/application/sync_service.dart';
import 'activities_controller.dart';

/// Pantalla B. Mis actividades (§4.4.2, RF-08, P-03).
class MyActivitiesScreen extends StatelessWidget {
  const MyActivitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ActivitiesController>();
    final sync = context.watch<SyncService>();
    final items = controller.visible;

    return Scaffold(
      appBar: AppBar(
        title: const Text('EVENTTRACK'),
        actions: const [ProfileButton()],
      ),
      body: RefreshIndicator(
        onRefresh: controller.load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              sliver: SliverList.list(
                children: [
                  Text(
                    'Mis actividades',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: controller.search,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'Buscar actividad...',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  if (controller.fromCache) ...[
                    const SizedBox(height: 12),
                    const InfoBanner(
                      message:
                          'Sin conexión: se muestran las actividades '
                          'guardadas en el dispositivo.',
                    ),
                  ],
                ],
              ),
            ),
            if (controller.loading && controller.all.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (controller.error != null && controller.all.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'No se pudieron cargar tus actividades',
                    message: controller.error,
                    action: OutlinedButton.icon(
                      onPressed: controller.load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('REINTENTAR'),
                    ),
                  ),
                ),
              )
            else if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: EmptyState(
                    icon: Icons.event_available_outlined,
                    title: controller.query.isEmpty
                        ? 'No tienes actividades asignadas'
                        : 'Sin resultados para "${controller.query}"',
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverList.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final a = items[i];
                    final unsynced = sync.evidences
                        .where(
                          (e) =>
                              e.assignmentId == a.id &&
                              e.syncStatus != SyncStatus.synced,
                        )
                        .length;
                    return ActivityCard(assignment: a, unsyncedCount: unsynced);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ActivityCard extends StatelessWidget {
  const ActivityCard({
    super.key,
    required this.assignment,
    this.unsyncedCount = 0,
  });

  final Assignment assignment;
  final int unsyncedCount;

  @override
  Widget build(BuildContext context) {
    final a = assignment;
    final subtitle = a.dueAt == null
        ? a.eventName
        : '${a.eventName} / ${Formatters.shortDate(a.dueAt!)}';
    final chip = StatusChip.activity(a.activityStatus);

    void open() => context.push('/activities/${a.id}', extra: a);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.tint(chip.color),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.assignment_outlined, color: chip.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.activityTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (unsyncedCount > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.sync_problem,
                            size: 16,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              unsyncedCount == 1
                                  ? '1 evidencia sin sincronizar'
                                  : '$unsyncedCount evidencias sin sincronizar',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    // Wrap: con texto ampliado el botón baja de línea en vez
                    // de desbordarse (RNF-12).
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        chip,
                        OutlinedButton(
                          onPressed: open,
                          child: const Text('VER DETALLE'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Acceso a Perfil desde la barra superior (wireframe "[Perfil]").
class ProfileButton extends StatelessWidget {
  const ProfileButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: IconButton(
        tooltip: 'Perfil',
        icon: const Icon(Icons.account_circle_outlined),
        onPressed: () => context.push('/profile'),
      ),
    );
  }
}
