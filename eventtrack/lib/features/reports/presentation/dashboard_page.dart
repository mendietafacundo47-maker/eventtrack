import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../data/remote/panel_api.dart';
import '../../../domain/entities/assignment.dart';
import '../../../domain/entities/panel.dart';
import '../../evidence/presentation/panel/evidence_detail_dialog.dart';
import '../../panel/application/panel_selection.dart';
import '../../panel/presentation/panel_widgets.dart';

/// Resumen del evento activo y bandeja de evidencias recientes (CAP-02).
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _Row {
  const _Row(this.activity, this.latest);

  final PanelActivity activity;
  final EvidenceRecord? latest;
}

class _DashboardData {
  const _DashboardData(this.report, this.rows);

  final EventReport report;
  final List<_Row> rows;
}

class _DashboardPageState extends State<DashboardPage> {
  late final PanelApi _api = context.read<PanelApi>();
  late final PanelSelection _selection = context.read<PanelSelection>();
  Future<_DashboardData>? _data;
  String? _eventId;

  @override
  void initState() {
    super.initState();
    _selection.addListener(_onSelection);
    _onSelection();
  }

  @override
  void dispose() {
    _selection.removeListener(_onSelection);
    super.dispose();
  }

  void _onSelection() {
    final id = _selection.selectedId;
    if (id == _eventId) return;
    setState(() {
      _eventId = id;
      _data = id == null ? null : _load(id);
    });
  }

  void _reload() => setState(() {
    _data = _load(_eventId!);
  });

  Future<_DashboardData> _load(String eventId) async {
    final results = await Future.wait([
      _api.eventReport(eventId),
      _api.activities(eventId),
      _api.evidences(eventId: eventId, limit: 100),
    ]);
    final report = results[0] as EventReport;
    final activities = results[1] as List<PanelActivity>;
    final evidences = (results[2] as Paged<EvidenceRecord>).items;
    // Las evidencias llegan de la más reciente a la más antigua.
    final latest = <String, EvidenceRecord>{};
    for (final e in evidences) {
      latest.putIfAbsent(e.activityId, () => e);
    }
    final rows = [for (final a in activities) _Row(a, latest[a.id])]
      ..sort((a, b) {
        final ta = a.latest?.receivedAt;
        final tb = b.latest?.receivedAt;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
    return _DashboardData(report, rows);
  }

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<PanelSelection>();
    return PanelPage(
      title: 'Resumen del evento',
      subtitle: selection.selected == null
          ? null
          : '${selection.selected!.name} · ${Formatters.shortDate(selection.selected!.startsAt)}',
      actions: [
        const EventSelector(),
        if (_eventId != null)
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
      ],
      children: [
        if (_data == null)
          selection.loading ? const LoadingBox() : const NoEventsBox()
        else
          FutureBuilder<_DashboardData>(
            future: _data,
            builder: (context, snap) {
              if (snap.hasError) {
                return ErrorBox(
                  message: errorMessage(snap.error!),
                  onRetry: _reload,
                );
              }
              if (!snap.hasData) return const LoadingBox();
              return _content(snap.data!);
            },
          ),
      ],
    );
  }

  Widget _content(_DashboardData data) {
    final r = data.report;
    final canReview = panelUser(context).canReview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveRow(
          children: [
            StatCard(
              label: 'Total actividades',
              value: '${r.activitiesTotal}',
              icon: Icons.check_box_outline_blank,
              color: AppColors.action,
            ),
            StatCard(
              label: 'Pendientes',
              value: '${r.activitiesOpen}',
              icon: Icons.schedule,
              color: AppColors.warning,
              filled: true,
            ),
            StatCard(
              label: 'Completadas',
              value: '${r.activitiesByStatus[ActivityStatus.completed] ?? 0}',
              icon: Icons.check_circle,
              color: AppColors.success,
              filled: true,
            ),
            StatCard(
              label: 'Evidencias por revisar',
              value: '${r.evidencesPending}',
              icon: Icons.rate_review_outlined,
              color: AppColors.primary,
            ),
          ],
        ),
        const SizedBox(height: 20),
        SectionCard(
          title: 'Bandeja de evidencias y actividades recientes',
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: PanelTable(
            columns: const [
              'Actividad',
              'Responsable',
              'Estado',
              'Foto / GPS / Fecha',
              'Revisión',
            ],
            emptyMessage: 'Este evento aún no tiene actividades.',
            rows: [for (final row in data.rows) _tableRow(row, canReview)],
          ),
        ),
      ],
    );
  }

  DataRow _tableRow(_Row row, bool canReview) {
    final a = row.activity;
    final e = row.latest;
    final responsibles = a.responsibles.map((r) => r.fullName).join(', ');
    return DataRow(
      cells: [
        // Ancho acotado: los textos largos pasan a dos líneas y la columna
        // Revisión queda visible a 1366 px (§3.2.2).
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(
              a.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              responsibles.isEmpty ? 'Sin asignar' : responsibles,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: responsibles.isEmpty ? AppColors.textSecondary : null,
              ),
            ),
          ),
        ),
        DataCell(StatusChip.activity(a.status)),
        DataCell(
          e == null
              ? const Text(
                  'Sin evidencia aún',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: AppColors.textSecondary,
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () async {
                        if (await showEvidenceDetail(context, e.id)) _reload();
                      },
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.image_outlined,
                            size: 16,
                            color: AppColors.action,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Ver foto',
                            style: TextStyle(
                              color: AppColors.action,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${locationSummary(e)}\n${Formatters.dateTime(e.capturedAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
        ),
        DataCell(_reviewCell(e, canReview)),
      ],
    );
  }

  Widget _reviewCell(EvidenceRecord? e, bool canReview) {
    if (e == null) {
      return const Text(
        'Esperando evidencia',
        style: TextStyle(
          fontStyle: FontStyle.italic,
          color: AppColors.textSecondary,
        ),
      );
    }
    if (e.status != ReviewStatus.pending || !canReview) {
      return reviewStatusChip(e.status);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.success,
            side: const BorderSide(color: AppColors.success),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: () async {
            if (await quickReview(context, e.id, ReviewStatus.approved)) {
              _reload();
            }
          },
          child: const Text('Aprobar'),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: const BorderSide(color: AppColors.error),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: () async {
            if (await quickReview(context, e.id, ReviewStatus.rejected)) {
              _reload();
            }
          },
          child: const Text('Rechazar'),
        ),
      ],
    );
  }
}
