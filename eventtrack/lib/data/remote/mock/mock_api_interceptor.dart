import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

/// Backend simulado en memoria para desarrollar y demostrar la app mientras
/// la API Node.js no está desplegada. Se activa con `USE_MOCK_API=true`.
///
/// Reproduce el contrato de §4.3.5 / §4.5.4: login, asignaciones propias y
/// carga idempotente de evidencias. Respeta el modo avión del dispositivo
/// para poder probar el flujo offline (TC-13, TC-14).
///
/// Los resultados obtenidos contra este mock NO sustituyen las pruebas con
/// el backend real.
class MockApiInterceptor extends Interceptor {
  MockApiInterceptor({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  final _random = Random();

  static const demoEmail = 'responsable@uajms.edu.bo';
  static const demoPassword = 'Demo1234';
  static const _token = 'mock-token-responsable';

  static const _user = {
    'id': 'usr-demo-1',
    'fullName': 'Responsable de Prueba',
    'email': demoEmail,
    'role': 'RESPONSIBLE',
  };

  /// client_uuid → respuesta ya emitida (idempotencia, RB-10).
  static final Map<String, Map<String, dynamic>> _receivedEvidences = {};

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    await Future<void>.delayed(
      Duration(milliseconds: 300 + _random.nextInt(500)),
    );

    final results = await _connectivity.checkConnectivity();
    if (results.every((r) => r == ConnectivityResult.none)) {
      return handler.reject(
        DioException.connectionError(
          requestOptions: options,
          reason: 'Mock: dispositivo sin conectividad',
        ),
      );
    }

    final path = options.path;
    final method = options.method.toUpperCase();

    if (method == 'POST' && path == '/auth/login') {
      return _login(options, handler);
    }

    if (options.headers['Authorization'] != 'Bearer $_token') {
      return handler.reject(_error(options, 401, 'No autenticado.'));
    }

    if (method == 'POST' && path == '/auth/logout') {
      return handler.resolve(
        Response(requestOptions: options, statusCode: 204),
      );
    }
    if (method == 'GET' && path == '/me') {
      return handler.resolve(_ok(options, _user));
    }
    if (method == 'GET' && path == '/me/assignments') {
      return handler.resolve(_ok(options, _assignments()));
    }
    if (method == 'POST' && path == '/evidences') {
      return _evidence(options, handler);
    }
    handler.reject(_error(options, 404, 'Ruta no encontrada.'));
  }

  void _login(RequestOptions options, RequestInterceptorHandler handler) {
    final body = options.data as Map<String, dynamic>;
    final email = (body['email'] as String?)?.trim().toLowerCase();
    if (email == demoEmail && body['password'] == demoPassword) {
      return handler.resolve(
        _ok(options, {'accessToken': _token, 'user': _user}),
      );
    }
    handler.reject(_error(options, 401, 'Credenciales inválidas.'));
  }

  void _evidence(RequestOptions options, RequestInterceptorHandler handler) {
    final form = options.data as FormData;
    final key = options.headers['Idempotency-Key'] as String?;
    final metadataRaw = form.fields
        .firstWhere((f) => f.key == 'metadata')
        .value;
    final metadata = jsonDecode(metadataRaw) as Map<String, dynamic>;
    final photo = form.files.where((f) => f.key == 'photo').firstOrNull;

    if (key == null || key != metadata['clientUuid']) {
      return handler.reject(_error(options, 400, 'Idempotency-Key inválida.'));
    }
    final existing = _receivedEvidences[key];
    if (existing != null) {
      return handler.resolve(_ok(options, existing));
    }
    if (photo == null) {
      return handler.reject(_error(options, 400, 'Falta la fotografía.'));
    }
    final lat = metadata['latitude'] as num?;
    final lng = metadata['longitude'] as num?;
    if ((lat != null && (lat < -90 || lat > 90)) ||
        (lng != null && (lng < -180 || lng > 180))) {
      return handler.reject(
        _error(options, 422, 'Coordenadas fuera de rango.'),
      );
    }
    final known = _assignments().any(
      (a) => a['id'] == metadata['assignmentId'],
    );
    if (!known) {
      return handler.reject(
        _error(
          options,
          403,
          'No tienes una asignación vigente para esta actividad.',
        ),
      );
    }

    final receipt = {
      'id': 'evd-${_receivedEvidences.length + 1}',
      'status': 'PENDING_REVIEW',
      'receivedAt': DateTime.now().toUtc().toIso8601String(),
    };
    _receivedEvidences[key] = receipt;
    handler.resolve(_ok(options, receipt, status: 201));
  }

  static List<Map<String, dynamic>> _assignments() {
    final today = DateTime.now().toUtc();
    DateTime day(int offset) =>
        DateTime.utc(today.year, today.month, today.day + offset, 22);
    Map<String, dynamic> item(
      String id,
      String title,
      String description,
      String status,
      DateTime due,
      String eventId,
      String eventName,
    ) => {
      'id': 'asg-$id',
      'status': 'ACTIVE',
      'activity': {
        'id': 'act-$id',
        'title': title,
        'description': description,
        'dueAt': due.toIso8601String(),
        'status': status,
      },
      'event': {
        'id': eventId,
        'name': eventName,
        // Campus central UAJMS, Tarija (referencia aproximada).
        'latitude': -21.5337,
        'longitude': -64.7348,
      },
    };

    return [
      item(
        '1',
        'Inspección de Zona A',
        'Verificar señalización y ambientes de la zona A antes del ingreso.',
        'PENDING',
        day(0),
        'evt-1',
        'Evento Central',
      ),
      item(
        '2',
        'Registro de Asistencia',
        'Habilitar mesas de registro y fotografiar el punto de acreditación.',
        'IN_PROGRESS',
        day(0),
        'evt-2',
        'Conferencia Tech',
      ),
      item(
        '3',
        'Evidencia Fotográfica',
        'Registrar el montaje de stands en el patio central.',
        'PENDING',
        day(1),
        'evt-3',
        'Feria de Ciencias',
      ),
      item(
        '4',
        'Acreditación',
        'Entrega de credenciales a expositores.',
        'SUBMITTED',
        day(-1),
        'evt-4',
        'Congreso universitario',
      ),
    ];
  }

  static Response<dynamic> _ok(
    RequestOptions o,
    Object data, {
    int status = 200,
  }) => Response(requestOptions: o, statusCode: status, data: data);

  static DioException _error(RequestOptions o, int status, String message) =>
      DioException.badResponse(
        statusCode: status,
        requestOptions: o,
        response: Response(
          requestOptions: o,
          statusCode: status,
          data: {'message': message},
        ),
      );
}
