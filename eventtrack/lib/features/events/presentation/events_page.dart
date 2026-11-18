import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/remote/panel_api.dart';
import '../../../domain/entities/panel.dart';
import '../../panel/application/panel_selection.dart';
import '../../panel/presentation/panel_widgets.dart';
import 'event_form_dialog.dart';

/// Gestión de eventos (RF-05, P-01, CAP-03).
class EventsPage extends StatefulWidget {
  const EventsPage({super.key});

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  static const _limit = 20;

  late final PanelApi _api = context.read<PanelApi>();
  final _search = TextEditingController();
  Timer? _debounce;
  EventStatus? _status;
  int _offset = 0;
  late Future<Paged<PanelEvent>> _page = _load();

  Future<Paged<PanelEvent>> _load() => _api.events(
    search: _search.text.trim(),
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

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Tras crear o editar, la lista de eventos compartida también se renueva.
  Future<void> _afterChange(String message) async {
    showPanelMessage(context, message);
    _reload();
    await context.read<PanelSelection>().load();
  }

  Future<void> _create() async {
    final created = await showEventForm(context);
    if (created != null && mounted) {
      await _afterChange('Evento "${created.name}" creado.');
    }
  }

  Future<void> _edit(PanelEvent event) async {
    final updated = await showEventForm(context, event: event);
    if (updated != null && mounted) await _afterChange('Evento actualizado.');
  }

  Future<void> _changeStatus(PanelEvent event, EventStatus status) async {
    final irreversible =
        status == EventStatus.closed || status == EventStatus.cancelled;
    if (irreversible) {
      final ok = await confirmAction(
        context,
        title: '${status == EventStatus.closed ? 'Cerrar' : 'Cancelar'} evento',
        message:
            'El evento "${event.name}" pasará a ${status.label.toLowerCase()} '
            'y ya no aceptará nuevas actividades. Esta acción no se puede deshacer.',
        confirmLabel: status == EventStatus.closed
            ? 'Cerrar evento'
            : 'Cancelar evento',
        destructive: status == EventStatus.cancelled,
      );
      if (!ok) return;
    }
    try {
      await _api.changeEventStatus(event.id, status);
      if (mounted) await _afterChange('Estado cambiado a ${status.label}.');
    } catch (e) {
      if (mounted) showPanelMessage(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = panelUser(context);
    return PanelPage(
      title: 'Eventos',
      subtitle: user.canManageEvents
          ? 'Registra y administra los eventos que organizas.'
          : 'Eventos registrados en el sistema.',
      actions: [
        if (user.canManageEvents)
          FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add),
            label: const Text('Nuevo evento'),
          ),
      ],
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        hintText: 'Buscar evento...',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: (_) {
                        _debounce?.cancel();
                        _debounce = Timer(
                          const Duration(milliseconds: 350),
                          () => _reload(resetPage: true),
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<EventStatus?>(
                      isExpanded: true,
                      initialValue: _status,
                      decoration: const InputDecoration(
                        labelText: 'Estado',
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Todos'),
                        ),
                        for (final s in EventStatus.values)
                          DropdownMenuItem(value: s, child: Text(s.label)),
                      ],
                      onChanged: (s) {
                        _status = s;
                        _reload(resetPage: true);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FutureBuilder<Paged<PanelEvent>>(
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
                          'Evento',
                          'Fechas',
                          'Organizador',
                          'Avance',
                          'Estado',
                          'Acciones',
                        ],
                        emptyMessage: 'No se encontraron eventos.',
                        rows: [
                          for (final e in page.items)
                            _row(e, user.canManageEvents),
                        ],
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

  DataRow _row(PanelEvent e, bool canManage) {
    final manageable =
        canManage &&
        (panelUser(context).isAdmin || e.organizerId == panelUser(context).id);
    return DataRow(
      cells: [
        DataCell(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (e.locationName != null && e.locationName!.isNotEmpty)
                Text(
                  e.locationName!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        DataCell(
          Text(
            '${Formatters.dateTime(e.startsAt)}\n${Formatters.dateTime(e.endsAt)}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        DataCell(Text(e.organizerName)),
        DataCell(
          Text('${e.activitiesCompleted} / ${e.activitiesTotal} completadas'),
        ),
        DataCell(eventStatusChip(e.status)),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () {
                  context.read<PanelSelection>().select(e.id);
                  context.go('/actividades');
                },
                child: const Text('Actividades'),
              ),
              if (manageable && e.status.isOpen)
                IconButton(
                  tooltip: 'Editar',
                  onPressed: () => _edit(e),
                  icon: const Icon(Icons.edit_outlined),
                ),
              if (manageable && e.status.nextStatuses.isNotEmpty)
                PopupMenuButton<EventStatus>(
                  tooltip: 'Cambiar estado',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (s) => _changeStatus(e, s),
                  itemBuilder: (_) => [
                    for (final s in e.status.nextStatuses)
                      PopupMenuItem(
                        value: s,
                        child: Text(switch (s) {
                          EventStatus.active => 'Activar',
                          EventStatus.closed => 'Cerrar',
                          EventStatus.cancelled => 'Cancelar',
                          EventStatus.draft => 'Borrador',
                        }),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
