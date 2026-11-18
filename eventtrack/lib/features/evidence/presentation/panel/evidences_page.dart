import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/remote/panel_api.dart';
import '../../../../domain/entities/panel.dart';
import '../../../panel/application/panel_selection.dart';
import '../../../panel/presentation/panel_widgets.dart';
import 'evidence_detail_dialog.dart';

/// Bandeja de revisión de evidencias (P-07, RF-15, RF-16, CAP-09).
class EvidencesPage extends StatefulWidget {
  const EvidencesPage({super.key});

  @override
  State<EvidencesPage> createState() => _EvidencesPageState();
}

class _EvidencesPageState extends State<EvidencesPage> {
  static const _limit = 20;

  late final PanelApi _api = context.read<PanelApi>();
  late final PanelSelection _selection = context.read<PanelSelection>();
  // Por defecto, lo que falta revisar.
  ReviewStatus? _status = ReviewStatus.pending;
  int _offset = 0;
  String? _eventId;
  late Future<Paged<EvidenceRecord>> _page;

  @override
  void initState() {
    super.initState();
    _eventId = _selection.filterEventId;
    _page = _load();
    _selection.addListener(_onSelection);
  }

  @override
  void dispose() {
    _selection.removeListener(_onSelection);
    super.dispose();
  }

  void _onSelection() {
    if (_selection.filterEventId == _eventId) return;
    _eventId = _selection.filterEventId;
    _reload(resetPage: true);
  }

  Future<Paged<EvidenceRecord>> _load() => _api.evidences(
    eventId: _eventId,
    status: _status,
    limit: _limit,
    offset: _offset,
  );

  void _reload({bool resetPage = false}) {
    if (resetPage) _offset = 0;
    setState(() {
      _page = _load();
    });
  }

  Future<void> _open(EvidenceRecord e) async {
    if (await showEvidenceDetail(context, e.id)) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final canReview = panelUser(context).canReview;
    return PanelPage(
      title: 'Evidencias',
      subtitle: canReview
          ? 'Revisa la fotografía y los metadatos, y aprueba o rechaza con comentario.'
          : 'Evidencias recibidas de tus eventos.',
      actions: [
        const EventSelector(allowAll: true),
        IconButton(
          tooltip: 'Actualizar',
          onPressed: _reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<ReviewStatus?>(
                  segments: const [
                    ButtonSegment(
                      value: ReviewStatus.pending,
                      label: Text('Por revisar'),
                    ),
                    ButtonSegment(
                      value: ReviewStatus.approved,
                      label: Text('Aprobadas'),
                    ),
                    ButtonSegment(
                      value: ReviewStatus.rejected,
                      label: Text('Rechazadas'),
                    ),
                    ButtonSegment(value: null, label: Text('Todas')),
                  ],
                  selected: {_status},
                  onSelectionChanged: (s) {
                    _status = s.first;
                    _reload(resetPage: true);
                  },
                ),
              ),
              const SizedBox(height: 12),
              FutureBuilder<Paged<EvidenceRecord>>(
                future: _page,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return ErrorBox(
                      message: errorMessage(snap.error!),
                      onRetry: _reload,
                    );
                  }
                  if (!snap.hasData) return const LoadingBox();
                  final page = snap.data!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PanelTable(
                        columns: const [
                          'Recibida',
                          'Actividad',
                          'Responsable',
                          'Ubicación GPS',
                          'Estado',
                          '',
                        ],
                        emptyMessage: _status == ReviewStatus.pending
                            ? 'No hay evidencias pendientes de revisión.'
                            : 'No hay evidencias con este filtro.',
                        rows: [for (final e in page.items) _row(e, canReview)],
                      ),
                      Pager(
                        offset: _offset,
                        limit: _limit,
                        total: page.total,
                        onChanged: (o) {
                          _offset = o;
                          _reload();
                        },
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  DataRow _row(EvidenceRecord e, bool canReview) {
    return DataRow(
      onSelectChanged: (_) => _open(e),
      cells: [
        DataCell(Text(Formatters.dateTime(e.receivedAt))),
        DataCell(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                e.activityTitle,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                e.eventName,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        DataCell(Text(e.createdByName)),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                e.hasLocation ? Icons.place : Icons.location_off,
                size: 16,
                color: e.hasLocation ? AppColors.error : AppColors.neutral,
              ),
              const SizedBox(width: 4),
              Text(locationSummary(e), style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        DataCell(reviewStatusChip(e.status)),
        DataCell(
          TextButton(
            onPressed: () => _open(e),
            child: Text(
              canReview && e.status == ReviewStatus.pending ? 'Revisar' : 'Ver',
            ),
          ),
        ),
      ],
    );
  }
}
