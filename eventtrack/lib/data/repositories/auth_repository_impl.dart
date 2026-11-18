import '../../domain/entities/user.dart';
import '../../domain/repositories/repositories.dart';
import '../local/session_storage.dart';
import '../remote/remote_data_sources.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._remote, this._session);

  final RemoteDataSource _remote;
  final SessionStorage _session;

  @override
  Future<User> login({required String email, required String password}) async {
    final res = await _remote.login(email.trim().toLowerCase(), password);
    await _session.save(token: res.accessToken, user: res.user);
    return res.user;
  }

  @override
  Future<User?> restoreSession() async {
    final token = await _session.readToken();
    if (token == null) return null;
    return _session.readUser();
  }

  @override
  Future<void> logout() async {
    await _remote.logout();
    // Las evidencias pendientes NO se borran: quedan asociadas al usuario y
    // se sincronizan cuando vuelva a iniciar sesión (RNF-07).
    await _session.clear();
  }
}
