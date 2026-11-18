import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../domain/entities/panel.dart';
import '../../domain/entities/user.dart';
import '../models/panel_models.dart';
import 'api_client.dart';

/// Endpoints que usa el panel web administrativo (§4.5.4). La autorización
/// real la aplica el backend en cada operación (RNF-02); el panel solo oculta
/// acciones que el rol no puede realizar.
class PanelApi {
  PanelApi(this._api);

  final ApiClient _api;

  Future<Json> _get(String path, [Map<String, Object?>? query]) async {
    final res = await _api.call(
      (dio) => dio.get<Json>(
        path,
        queryParameters: {...?query}..removeWhere((_, v) => v == null),
      ),
    );
    return res.data!;
  }

  Future<List<Json>> _getList(String path) async {
    final res = await _api.call((dio) => dio.get<List<dynamic>>(path));
    return res.data!.cast<Json>();
  }

  Future<Json> _send(String method, String path, Object? body) async {
    final res = await _api.call(
      (dio) => dio.request<Json>(
        path,
        data: body,
        options: Options(method: method),
      ),
    );
    return res.data ?? const {};
  }

  Paged<T> _paged<T>(Json body, T Function(Json) parse) => Paged(
    (body['items'] as List).cast<Json>().map(parse).toList(),
    (body['total'] as num).toInt(),
  );

  // ---- Eventos (RF-05) ----

  Future<Paged<PanelEvent>> events({
    String? search,
    EventStatus? status,
    int limit = 20,
    int offset = 0,
  }) async => _paged(
    await _get('/events', {
      'search': (search?.isEmpty ?? true) ? null : search,
      'status': status?.code,
      'limit': limit,
      'offset': offset,
    }),
    PanelModels.event,
  );

  Future<PanelEvent> createEvent(
    EventDraft draft, {
    required bool activate,
  }) async => PanelModels.event(
    await _send('POST', '/events', {
      ...PanelModels.eventDraft(draft)..removeWhere((_, v) => v == null),
      'status': activate ? EventStatus.active.code : EventStatus.draft.code,
    }),
  );

  Future<PanelEvent> updateEvent(String id, EventDraft draft) async =>
      PanelModels.event(
        await _send('PATCH', '/events/$id', PanelModels.eventDraft(draft)),
      );

  Future<PanelEvent> changeEventStatus(String id, EventStatus status) async =>
      PanelModels.event(
        await _send('PATCH', '/events/$id', {'status': status.code}),
      );

  // ---- Actividades y asignaciones (RF-06, RF-07) ----

  Future<List<PanelActivity>> activities(String eventId) async =>
      (await _getList('/events/$eventId/activities'))
          .map(PanelModels.activity)
          .toList();

  Future<PanelActivity> createActivity(
    String eventId, {
    required String title,
    required String description,
    DateTime? dueAt,
  }) async => PanelModels.activity(
    await _send('POST', '/events/$eventId/activities', {
      'title': title,
      'description': description,
      'dueAt': ?dueAt?.toUtc().toIso8601String(),
    }),
  );

  Future<PanelActivity> updateActivity(
    String id, {
    String? title,
    String? description,
    DateTime? dueAt,
    bool clearDueAt = false,
    String? status,
  }) async => PanelModels.activity(
    await _send('PATCH', '/activities/$id', {
      'title': ?title,
      'description': ?description,
      if (dueAt != null || clearDueAt)
        'dueAt': dueAt?.toUtc().toIso8601String(),
      'status': ?status,
    }),
  );

  Future<List<AssignableUser>> assignableUsers() async =>
      (await _getList('/assignments/assignable-users'))
          .map(PanelModels.assignable)
          .toList();

  Future<void> assign(String activityId, String userId) => _send(
    'POST',
    '/assignments',
    {'activityId': activityId, 'userId': userId},
  );

  Future<void> revokeAssignment(String assignmentId) =>
      _send('DELETE', '/assignments/$assignmentId', null);

  // ---- Evidencias y revisión (RF-15, RF-16) ----

  Future<Paged<EvidenceRecord>> evidences({
    String? eventId,
    ReviewStatus? status,
    int limit = 20,
    int offset = 0,
  }) async => _paged(
    await _get('/evidences', {
      'eventId': eventId,
      'status': status?.code,
      'limit': limit,
      'offset': offset,
    }),
    PanelModels.evidence,
  );

  Future<EvidenceRecord> evidence(String id) async =>
      PanelModels.evidence(await _get('/evidences/$id'));

  /// La foto se descarga con el token (no hay URL pública, §4.3.7).
  Future<Uint8List> evidencePhoto(String id) async {
    final res = await _api.call(
      (dio) => dio.get<List<int>>(
        '/evidences/$id/photo',
        options: Options(responseType: ResponseType.bytes),
      ),
    );
    return Uint8List.fromList(res.data!);
  }

  Future<void> review(String evidenceId, ReviewStatus result, String comment) =>
      _send('POST', '/evidences/$evidenceId/reviews', {
        'result': result.code,
        'comment': comment,
      });

  // ---- Reportes (RF-17) ----

  Future<EventReport> eventReport(String eventId) async =>
      PanelModels.report(await _get('/reports/events/$eventId'));

  // ---- Usuarios (RF-03, solo administrador) ----

  Future<Paged<ManagedUser>> users({
    String? search,
    UserRole? role,
    int limit = 20,
    int offset = 0,
  }) async => _paged(
    await _get('/users', {
      'search': (search?.isEmpty ?? true) ? null : search,
      'role': role?.code,
      'limit': limit,
      'offset': offset,
    }),
    PanelModels.user,
  );

  Future<void> createUser({
    required String fullName,
    required String email,
    required UserRole role,
    required String password,
  }) => _send('POST', '/users', {
    'fullName': fullName,
    'email': email,
    'role': role.code,
    'password': password,
  });

  Future<void> updateUser(
    String id, {
    String? fullName,
    UserRole? role,
    bool? active,
    String? password,
  }) => _send('PATCH', '/users/$id', {
    'fullName': ?fullName,
    'role': ?role?.code,
    'active': ?active,
    'password': ?password,
  });
}
