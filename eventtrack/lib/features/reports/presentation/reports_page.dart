import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../data/remote/panel_api.dart';
import '../../../domain/entities/assignment.dart';
import '../../../domain/entities/panel.dart';
import '../../panel/application/panel_selection.dart';
import '../../panel/presentation/panel_widgets.dart';

/// Reporte de avance y cumplimiento por evento (RF-17, P-08, CAP-10). Los
/// totales se calculan en el backend a partir de los registros (TC-21).
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late final PanelApi _api = context.read<PanelApi>();
  late final PanelSelection _selection = context.read<PanelSelection>();
  Future<EventReport>? _report;
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
      _report = id == null ? null : _api.eventReport(id);
    });
  }

  void _reload() => setState(() {
    _report = _api.eventReport(_eventId!);
  });

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<PanelSelection>();
    return PanelPage(
      title: 'Reportes',
      subtitle: 'Indicadores de avance y cumplimiento por evento.',
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
        if (_report == null)
          selection.loading ? const LoadingBox() : const NoEventsBox()
        else
          FutureBuilder<EventReport>(
            future: _report,
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

  Widget _content(EventReport r) {
    final e = r.event;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          child: Wrap(
            spacing: 32,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _fact('Evento', e.name),
              _fact('Organizador', e.organizerName),
              _fact(
                'Fechas',
                '${Formatters.date(e.startsAt)} – ${Formatters.date(e.endsAt)}',
              ),
              eventStatusChip(e.status),
              _fact('Generado', Formatters.dateTime(r.generatedAt)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ResponsiveRow(
          children: [
            StatCard(
              label: 'Avance',
              value:
                  '${r.completionRate.toStringAsFixed(r.completionRate % 1 == 0 ? 0 : 1)} %',
              icon: Icons.trending_up,
              color: AppColors.success,
              filled: true,
            ),
            StatCard(
              label: 'Actividades',
              value: '${r.activitiesTotal}',
              icon: Icons.checklist,
              color: AppColors.action,
            ),
            StatCard(
              label: 'Asignaciones vigentes',
              value: '${r.assignmentsActive}',
              icon: Icons.people_outline,
              color: AppColors.primary,
            ),
            StatCard(
              label: 'Evidencias recibidas',
              value: '${r.evidencesTotal}',
              icon: Icons.photo_camera_outlined,
              color: AppColors.primary,
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final cards = [
              SectionCard(
                title: 'Actividades por estado',
                child: Column(
                  children: [
                    for (final s in ActivityStatus.values)
                      _bar(
                        s.label,
                        r.activitiesByStatus[s] ?? 0,
                        r.activitiesTotal,
                        StatusChip.activity(s).color,
                      ),
                  ],
                ),
              ),
              SectionCard(
                title: 'Evidencias y revisiones',
                child: Column(
                  children: [
                    _bar(
                      'Por revisar',
                      r.evidencesPending,
                      r.evidencesTotal,
                      AppColors.warning,
                    ),
                    _bar(
                      'Aprobadas',
                      r.evidencesApproved,
                      r.evidencesTotal,
                      AppColors.success,
                    ),
                    _bar(
                      'Rechazadas',
                      r.evidencesRejected,
                      r.evidencesTotal,
                      AppColors.error,
                    ),
                    const Divider(height: 24),
                    _bar(
                      'Con GPS',
                      r.evidencesWithLocation,
                      r.evidencesTotal,
                      AppColors.action,
                    ),
                    _bar(
                      'Sin GPS (no disponible)',
                      r.evidencesWithoutLocation,
                      r.evidencesTotal,
                      AppColors.neutral,
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Revisiones registradas: ${r.reviewsTotal}',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ];
            if (c.maxWidth < 800) {
              return Column(
                children: [cards[0], const SizedBox(height: 16), cards[1]],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 16),
                  Expanded(child: cards[1]),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Detalle por actividad',
          child: PanelTable(
            columns: const [
              'Actividad',
              'Responsables',
              'Fecha límite',
              'Evidencias',
              'Aprob. / Rech. / Pend.',
              'Última evidencia',
              'Estado',
            ],
            emptyMessage: 'Este evento aún no tiene actividades.',
            rows: [
              for (final i in r.items)
                DataRow(
                  cells: [
                    DataCell(
                      Text(
                        i.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    DataCell(
                      Text(
                        i.responsibles.isEmpty
                            ? 'Sin asignar'
                            : i.responsibles.join(', '),
                      ),
                    ),
                    DataCell(
                      Text(i.dueAt == null ? '—' : Formatters.date(i.dueAt!)),
                    ),
                    DataCell(Text('${i.evidencesTotal}')),
                    DataCell(
                      Text(
                        '${i.approved} / ${i.rejected} / ${i.pendingReview}',
                      ),
                    ),
                    DataCell(
                      Text(
                        i.lastEvidenceAt == null
                            ? '—'
                            : Formatters.dateTime(i.lastEvidenceAt!),
                      ),
                    ),
                    DataCell(StatusChip.activity(i.status)),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fact(String label, String value) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
    ],
  );

  /// Barra con valor numérico y porcentaje (el color nunca va solo, §4.3.6).
  Widget _bar(String label, int value, int total, Color color) {
    final ratio = total == 0 ? 0.0 : value / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                '$value  (${(ratio * 100).round()} %)',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              color: color,
              backgroundColor: AppColors.border,
            ),
          ),
        ],
      ),
    );
  }
}
