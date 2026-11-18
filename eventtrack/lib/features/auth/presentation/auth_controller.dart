import 'package:flutter/foundation.dart';

import '../../../domain/entities/user.dart';
import '../../../domain/repositories/repositories.dart';
import '../../sync/application/sync_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthController extends ChangeNotifier {
  /// [sync] es la cola offline de Android; el panel web no la usa.
  AuthController(this._repository, [this._sync]);

  final AuthRepository _repository;
  final SyncService? _sync;

  AuthStatus _status = AuthStatus.unknown;
  User? _user;
  String? _notice;

  AuthStatus get status => _status;
  User? get user => _user;

  /// Aviso para mostrar en la pantalla de login (p. ej. sesión expirada).
  String? takeNotice() {
    final n = _notice;
    _notice = null;
    return n;
  }

  Future<void> restore() async {
    final user = await _repository.restoreSession();
    await _setUser(user);
  }

  /// Lanza [AppException] con un mensaje listo para mostrar.
  Future<void> login(String email, String password) async {
    final user = await _repository.login(email: email, password: password);
    await _setUser(user);
  }

  Future<void> logout() async {
    await _repository.logout();
    await _setUser(null);
  }

  /// Llamado cuando la API responde 401 (TC-23). Las evidencias locales se
  /// conservan y se sincronizarán tras volver a iniciar sesión.
  Future<void> onSessionExpired() async {
    if (_status != AuthStatus.authenticated) return;
    _notice =
        'Tu sesión expiró. Inicia sesión para continuar; '
        'tus evidencias pendientes se conservan.';
    await _repository.logout();
    await _setUser(null);
  }

  Future<void> _setUser(User? user) async {
    _user = user;
    _status = user == null
        ? AuthStatus.unauthenticated
        : AuthStatus.authenticated;
    if (user == null) {
      await _sync?.stop();
    } else {
      await _sync?.start(user.id);
    }
    notifyListeners();
  }
}
