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

/// Actividades de un evento y asignación de responsables (RF-06, RF-07,
/// P-02, CAP-04).
class PanelActivitiesPage extends StatefulWidget {
  const PanelActivitiesPage({super.key});

  @override
  State<PanelActivitiesPage> createState() => _PanelActivitiesPageState();
}

class _PanelActivitiesPageState extends State<PanelActivitiesPage> {
  late final PanelApi _api = context.read<PanelApi>();
  late final PanelSelection _selection = context.read<PanelSelection>();
  Future<List<PanelActivity>>? _activities;
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
      _activities = id == null ? null : _api.activities(id);
    });
  }

  void _reload() => setState(() {
    _activities = _api.activities(_eventId!);
  });

  bool _canManage(PanelEvent? event) {
    final user = panelUser(context);
    return event != null &&
        user.canManageEvents &&
        (user.isAdmin || event.organizerId == user.id);
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    try {
      await action();
      if (!mounted) return;
      showPanelMessage(context, success);
      _reload();
    } catch (e) {
      if (mounted) showPanelMessage(context, errorMessage(e), error: true);
    }
  }

  Future<void> _edit({PanelActivity? activity}) async {
    final result = await showDialog<_ActivityForm>(
      context: context,
      builder: (_) => _ActivityFormDialog(activity: activity),
    );
    if (result == null) return;
    if (activity == null) {
      await _run(
        () => _api.createActivity(
          _eventId!,
          title: result.title,
          description: result.description,
          dueAt: result.dueAt,
        ),
        'Actividad creada.',
      );
    } else {
      await _run(
        () => _api.updateActivity(
          activity.id,
          title: result.title,
          description: result.description,
          dueAt: result.dueAt,
          clearDueAt: result.dueAt == null,
        ),
        'Actividad actualizada.',
      );
    }
  }

  Future<void> _assign(PanelActivity activity) async {
    final userId = await showDialog<String>(
      context: context,
      builder: (_) => Provider.value(
        value: _api,
        child: _AssignDialog(activity: activity),
      ),
    );
    if (userId == null) return;
    await _run(() => _api.assign(activity.id, userId), 'Responsable asignado.');
  }

  Future<void> _revoke(PanelActivity activity, ActivityResponsible r) async {
    final ok = await confirmAction(
      context,
      title: 'Quitar responsable',
      message:
          '${r.fullName} dejará de ver "${activity.title}" en su app. '
          'Las evidencias ya enviadas se conservan.',
      confirmLabel: 'Quitar',
      destructive: true,
    );
    if (ok) {
      await _run(
        () => _api.revokeAssignment(r.assignmentId),
        'Asignación revocada.',
      );
    }
  }

  Future<void> _setStatus(PanelActivity activity, ActivityStatus status) async {
    final ok = await confirmAction(
      context,
      title: status == ActivityStatus.cancelled
          ? 'Cancelar actividad'
          : 'Cambiar estado',
      message: '"${activity.title}" pasará a ${status.label.toLowerCase()}.',
      confirmLabel: 'Confirmar',
      destructive: status == ActivityStatus.cancelled,
    );
    if (ok) {
      await _run(
        () => _api.updateActivity(activity.id, status: status.code),
        'Estado actualizado.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<PanelSelection>();
    final event = selection.selected;
    final canManage = _canManage(event);
    return PanelPage(
      title: 'Actividades',
      subtitle: event == null
          ? null
          : 'Actividades y responsables de ${event.name}.',
      actions: [
        const EventSelector(),
        if (canManage && event!.status.isOpen)
          FilledButton.icon(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('Nueva actividad'),
          ),
      ],
      children: [
        if (event != null && !event.status.isOpen)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'El evento está ${event.status.label.toLowerCase()}: '
              'no admite cambios en sus actividades.',
              style: const TextStyle(
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (_activities == null)
          selection.loading ? const LoadingBox() : const NoEventsBox()
        else
          SectionCard(
            child: FutureBuilder<List<PanelActivity>>(
              future: _activities,
              builder: (context, snap) {
                if (snap.hasError) {
                  return ErrorBox(
                    message: errorMessage(snap.error!),
                    onRetry: _reload,
                  );
                }
                if (!snap.hasData) return const LoadingBox();
                final editable = canManage && event!.status.isOpen;
                return PanelTable(
                  columns: const [
                    'Actividad',
                    'Fecha límite',
                    'Responsables',
                    'Evidencias',
                    'Estado',
                    'Acciones',
                  ],
                  emptyMessage: 'Este evento aún no tiene actividades.',
                  rows: [for (final a in snap.data!) _row(a, editable)],
                );
              },
            ),
          ),
      ],
    );
  }

  DataRow _row(PanelActivity a, bool editable) {
    final locked = a.status == ActivityStatus.cancelled;
    return DataRow(
      cells: [
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (a.description.isNotEmpty)
                  Text(
                    a.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
        DataCell(Text(a.dueAt == null ? '—' : Formatters.dateTime(a.dueAt!))),
        DataCell(
          a.responsibles.isEmpty
              ? const Text(
                  'Sin asignar',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: AppColors.textSecondary,
                  ),
                )
              : Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final r in a.responsibles)
                      InputChip(
                        label: Text(r.fullName),
                        visualDensity: VisualDensity.compact,
                        onDeleted: editable ? () => _revoke(a, r) : null,
                        deleteButtonTooltipMessage: 'Quitar responsable',
                      ),
                  ],
                ),
        ),
        DataCell(Text('${a.evidencesTotal}')),
        DataCell(StatusChip.activity(a.status)),
        DataCell(
          editable && !locked
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: () => _assign(a),
                      icon: const Icon(Icons.person_add_alt, size: 18),
                      label: const Text('Asignar'),
                    ),
                    IconButton(
                      tooltip: 'Editar',
                      onPressed: () => _edit(activity: a),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    PopupMenuButton<ActivityStatus>(
                      tooltip: 'Más acciones',
                      icon: const Icon(Icons.more_vert),
                      onSelected: (s) => _setStatus(a, s),
                      itemBuilder: (_) => [
                        if (a.status == ActivityStatus.pending)
                          const PopupMenuItem(
                            value: ActivityStatus.inProgress,
                            child: Text('Marcar en ejecución'),
                          ),
                        if (a.status != ActivityStatus.completed)
                          const PopupMenuItem(
                            value: ActivityStatus.completed,
                            child: Text('Marcar como completada'),
                          ),
                        const PopupMenuItem(
                          value: ActivityStatus.cancelled,
                          child: Text('Cancelar actividad'),
                        ),
                      ],
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _ActivityForm {
  const _ActivityForm(this.title, this.description, this.dueAt);

  final String title;
  final String description;
  final DateTime? dueAt;
}

class _ActivityFormDialog extends StatefulWidget {
  const _ActivityFormDialog({this.activity});

  final PanelActivity? activity;

  @override
  State<_ActivityFormDialog> createState() => _ActivityFormDialogState();
}

class _ActivityFormDialogState extends State<_ActivityFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.activity?.title);
  late final _description = TextEditingController(
    text: widget.activity?.description,
  );
  late DateTime? _dueAt = widget.activity?.dueAt?.toLocal();

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueAt ?? DateTime(2000, 1, 1, 18)),
    );
    if (time == null) return;
    setState(
      () => _dueAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.activity == null ? 'Nueva actividad' : 'Editar actividad',
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _title,
                autofocus: true,
                maxLength: 160,
                decoration: const InputDecoration(labelText: 'Título *'),
                validator: (v) => (v == null || v.trim().length < 3)
                    ? 'Ingresa al menos 3 caracteres.'
                    : null,
              ),
              TextFormField(
                controller: _description,
                maxLines: 3,
                maxLength: 5000,
                decoration: const InputDecoration(labelText: 'Descripción'),
              ),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickDue,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Fecha límite',
                          prefixIcon: Icon(Icons.event_outlined),
                          isDense: true,
                        ),
                        child: Text(
                          _dueAt == null
                              ? 'Sin fecha límite'
                              : Formatters.dateTime(_dueAt!),
                        ),
                      ),
                    ),
                  ),
                  if (_dueAt != null)
                    IconButton(
                      tooltip: 'Quitar fecha límite',
                      onPressed: () => setState(() => _dueAt = null),
                      icon: const Icon(Icons.clear),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
              context,
              _ActivityForm(
                _title.text.trim(),
                _description.text.trim(),
                _dueAt,
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _AssignDialog extends StatefulWidget {
  const _AssignDialog({required this.activity});

  final PanelActivity activity;

  @override
  State<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<_AssignDialog> {
  late final Future<List<AssignableUser>> _users = context
      .read<PanelApi>()
      .assignableUsers();
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final assigned = {for (final r in widget.activity.responsibles) r.userId};
    return AlertDialog(
      title: const Text('Asignar responsable'),
      content: SizedBox(
        width: 440,
        child: FutureBuilder<List<AssignableUser>>(
          future: _users,
          builder: (context, snap) {
            if (snap.hasError) return Text(errorMessage(snap.error!));
            if (!snap.hasData) return const LoadingBox();
            final available = snap.data!
                .where((u) => !assigned.contains(u.id))
                .toList();
            if (available.isEmpty) {
              return const Text(
                'No hay más responsables activos para asignar. '
                'El administrador puede crearlos en Usuarios.',
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Actividad: ${widget.activity.title}'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selected,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Responsable'),
                  items: [
                    for (final u in available)
                      DropdownMenuItem(
                        value: u.id,
                        child: Text('${u.fullName} · ${u.email}'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _selected = v),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.pop(context, _selected),
          child: const Text('Asignar'),
        ),
      ],
    );
  }
}
