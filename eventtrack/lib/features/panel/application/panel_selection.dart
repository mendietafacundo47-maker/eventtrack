import 'package:flutter/foundation.dart';

import '../../../data/remote/panel_api.dart';
import '../../../domain/entities/panel.dart';
import '../presentation/panel_widgets.dart' show errorMessage;

/// Evento de trabajo seleccionado en el panel. Se comparte entre Resumen,
/// Actividades y Reportes para no volver a elegirlo en cada página.
class PanelSelection extends ChangeNotifier {
  PanelSelection(this._api);

  final PanelApi _api;

  List<PanelEvent> _events = const [];
  String? _selectedId;
  String? _filterEventId;
  bool _loading = false;
  String? _error;

  List<PanelEvent> get events => _events;
  bool get loading => _loading;
  String? get error => _error;
  String? get selectedId => _selectedId;

  /// Filtro de la bandeja de evidencias (null = todos los eventos).
  String? get filterEventId => _filterEventId;

  PanelEvent? get selected {
    for (final e in _events) {
      if (e.id == _selectedId) return e;
    }
    return null;
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _events = (await _api.events(limit: 100)).items;
      if (_events.every((e) => e.id != _selectedId)) {
        // Por defecto, el primer evento activo (resumen del evento activo).
        _selectedId =
            _events
                .where((e) => e.status == EventStatus.active)
                .firstOrNull
                ?.id ??
            _events.firstOrNull?.id;
      }
    } catch (e) {
      _error = errorMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void select(String id) {
    if (id == _selectedId) return;
    _selectedId = id;
    notifyListeners();
  }

  void setFilter(String? eventId) {
    _filterEventId = eventId;
    notifyListeners();
  }

  void clear() {
    _events = const [];
    _selectedId = null;
    _filterEventId = null;
    notifyListeners();
  }
}
