import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/remote/panel_api.dart';
import '../../../domain/entities/panel.dart';
import '../../panel/presentation/panel_widgets.dart';

/// Alta o edición de evento. Devuelve el evento guardado o `null`.
Future<PanelEvent?> showEventForm(BuildContext context, {PanelEvent? event}) =>
    showDialog<PanelEvent>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Provider.value(
        value: context.read<PanelApi>(),
        child: _EventFormDialog(event: event),
      ),
    );

class _EventFormDialog extends StatefulWidget {
  const _EventFormDialog({this.event});

  final PanelEvent? event;

  @override
  State<_EventFormDialog> createState() => _EventFormDialogState();
}

class _EventFormDialogState extends State<_EventFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.event?.name);
  late final _description = TextEditingController(
    text: widget.event?.description,
  );
  late final _location = TextEditingController(
    text: widget.event?.locationName,
  );
  late final _lat = TextEditingController(
    text: widget.event?.latitude?.toString(),
  );
  late final _lng = TextEditingController(
    text: widget.event?.longitude?.toString(),
  );
  late DateTime? _startsAt = widget.event?.startsAt.toLocal();
  late DateTime? _endsAt = widget.event?.endsAt.toLocal();
  bool _activate = true;
  bool _saving = false;
  String? _dateError;
  String? _serverError;

  bool get _isNew => widget.event == null;

  @override
  void dispose() {
    for (final c in [_name, _description, _location, _lat, _lng]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime? current) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        current ?? DateTime(now.year, 1, 1, 9),
      ),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  static double? _parse(String text) => text.trim().isEmpty
      ? null
      : double.tryParse(text.trim().replaceAll(',', '.'));

  String? _coordValidator(String? v, double limit) {
    if (v == null || v.trim().isEmpty) return null;
    final n = _parse(v);
    if (n == null) return 'Número no válido.';
    if (n < -limit || n > limit) return 'Debe estar entre -$limit y $limit.';
    return null;
  }

  Future<void> _save() async {
    setState(() {
      _serverError = null;
      _dateError = _startsAt == null || _endsAt == null
          ? 'Indica la fecha de inicio y de fin.'
          // TC-05: el fin no puede ser anterior al inicio.
          : _endsAt!.isBefore(_startsAt!)
          ? 'La fecha de fin no puede ser anterior a la de inicio.'
          : null;
    });
    final valid = _form.currentState!.validate();
    if (!valid || _dateError != null) return;

    final lat = _parse(_lat.text);
    final lng = _parse(_lng.text);
    if ((lat == null) != (lng == null)) {
      setState(
        () => _serverError =
            'Ingresa latitud y longitud juntas, o deja ambas vacías.',
      );
      return;
    }

    final draft = EventDraft(
      name: _name.text.trim(),
      description: _description.text.trim(),
      locationName: _location.text.trim().isEmpty
          ? null
          : _location.text.trim(),
      startsAt: _startsAt!,
      endsAt: _endsAt!,
      latitude: lat,
      longitude: lng,
    );
    setState(() => _saving = true);
    final api = context.read<PanelApi>();
    try {
      final saved = _isNew
          ? await api.createEvent(draft, activate: _activate)
          : await api.updateEvent(widget.event!.id, draft);
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _serverError = errorMessage(e);
        });
      }
    }
  }

  Widget _dateField(
    String label,
    DateTime? value,
    ValueChanged<DateTime> onPicked,
  ) {
    return InkWell(
      onTap: _saving
          ? null
          : () async {
              final picked = await _pickDateTime(value);
              if (picked != null) setState(() => onPicked(picked));
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today_outlined),
          isDense: true,
        ),
        child: Text(value == null ? 'Seleccionar' : Formatters.dateTime(value)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? 'Nuevo evento' : 'Editar evento'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del evento *',
                  ),
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
                TextFormField(
                  controller: _location,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Ubicación',
                    hintText: 'Ej.: Auditorio de la Facultad de Tecnología',
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _dateField(
                        'Inicio *',
                        _startsAt,
                        (d) => _startsAt = d,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _dateField('Fin *', _endsAt, (d) => _endsAt = d),
                    ),
                  ],
                ),
                if (_dateError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _dateError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'Punto de referencia (opcional). Se usa para calcular la distancia '
                  'de las evidencias al evento como indicador (RB-11).',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _lat,
                        decoration: const InputDecoration(
                          labelText: 'Latitud',
                          hintText: '-21.5337',
                        ),
                        validator: (v) => _coordValidator(v, 90),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lng,
                        decoration: const InputDecoration(
                          labelText: 'Longitud',
                          hintText: '-64.7348',
                        ),
                        validator: (v) => _coordValidator(v, 180),
                      ),
                    ),
                  ],
                ),
                if (_isNew)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _activate,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _activate = v ?? true),
                    title: const Text('Publicar como activo'),
                    subtitle: const Text(
                      'Si lo desmarcas, se guarda como borrador.',
                    ),
                  ),
                if (_serverError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _serverError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Guardando...' : 'Guardar'),
        ),
      ],
    );
  }
}
