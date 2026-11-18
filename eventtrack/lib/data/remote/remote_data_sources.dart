import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../../core/errors/app_exception.dart';
import '../../domain/entities/assignment.dart';
import '../../domain/entities/local_evidence.dart';
import '../../domain/entities/user.dart';
import '../models/assignment_model.dart';
import '../models/evidence_model.dart';
import '../models/user_model.dart';
import 'api_client.dart';

class LoginResponse {
  const LoginResponse(this.accessToken, this.user);

  final String accessToken;
  final User user;
}

/// Endpoints de la API propuesta (§4.5.4) usados por la app Android.
class RemoteDataSource {
  RemoteDataSource(this._api);

  final ApiClient _api;

  /// `POST /auth/login`
  Future<LoginResponse> login(String email, String password) async {
    try {
      final res = await _api.call(
        (dio) => dio.post<Map<String, dynamic>>(
          '/auth/login',
          data: {'email': email, 'password': password},
        ),
      );
      final body = res.data!;
      return LoginResponse(
        body['accessToken'] as String,
        UserModel.fromJson(body['user'] as Map<String, dynamic>),
      );
    } on PermanentException catch (e) {
      // 400/401/403/404 en login → mensaje genérico (TC-02).
      if (e.code == 'HTTP_400' ||
          e.code == 'HTTP_403' ||
          e.code == 'HTTP_404') {
        throw const InvalidCredentialsException();
      }
      rethrow;
    } on UnauthorizedException {
      throw const InvalidCredentialsException();
    }
  }

  /// `POST /auth/logout`. Se ignoran errores: el cierre local es suficiente.
  Future<void> logout() async {
    try {
      await _api.call((dio) => dio.post<void>('/auth/logout'));
    } on AppException {
      // Sin conexión o token ya expirado.
    }
  }

  /// `GET /me/assignments`
  Future<List<Assignment>> myAssignments() async {
    final res = await _api.call(
      (dio) => dio.get<List<dynamic>>('/me/assignments'),
    );
    return res.data!
        .cast<Map<String, dynamic>>()
        .map(AssignmentModel.fromJson)
        .toList();
  }

  /// `POST /evidences` multipart con `Idempotency-Key` (§4.3.5, RB-10).
  /// Si el servidor ya procesó el UUID, devuelve la evidencia existente.
  Future<EvidenceReceipt> uploadEvidence(LocalEvidence evidence) async {
    final ext = p.extension(evidence.photoPath).toLowerCase();
    final mime = switch (ext) {
      '.png' => DioMediaType('image', 'png'),
      '.webp' => DioMediaType('image', 'webp'),
      _ => DioMediaType('image', 'jpeg'),
    };
    final form = FormData.fromMap({
      'metadata': jsonEncode(EvidenceModel.toMetadataJson(evidence)),
      'photo': await MultipartFile.fromFile(
        evidence.photoPath,
        filename: '${evidence.clientUuid}$ext',
        contentType: mime,
      ),
    });
    final res = await _api.call(
      (dio) => dio.post<Map<String, dynamic>>(
        '/evidences',
        data: form,
        options: Options(headers: {'Idempotency-Key': evidence.clientUuid}),
      ),
    );
    return EvidenceModel.receiptFromJson(res.data!);
  }
}
