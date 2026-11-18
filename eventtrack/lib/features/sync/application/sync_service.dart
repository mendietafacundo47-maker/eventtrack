import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/network/network_monitor.dart';
import '../../../domain/entities/local_evidence.dart';
import '../../../domain/repositories/repositories.dart';

/// Cola de sincronización de evidencias (§4.3.4):
///
/// 1. La evidencia se guarda localmente como PENDING antes de cualquier envío.
/// 2. Al detectar conectividad (o a demanda) se envían las pendientes.
/// 3. Solo una respuesta exitosa del servidor la marca como SYNCED.
/// 4. Errores de red → reintento con backoff exponencial y límite.
/// 5. Errores permanentes → FAILED, visible al usuario, sin reintento automático.
/// 6. Los envíos interrumpidos por un cierre de la app (UPLOADING) se
///    recuperan al iniciar; el `client_uuid` evita duplicados en el servidor.
class SyncService extends ChangeNotifier {
  SyncService({
    required this._repository,
    required this._network,
    required this._store,
    DateTime Function()? clock,
    this.maxRetries = AppConfig.maxSyncRetries,
    this.baseBackoff = AppConfig.syncBaseBackoff,
    this.maxBackoff = AppConfig.syncMaxBackoff,
  }) : _now = clock ?? DateTime.now;

  final EvidenceRepository _repository;
  final NetworkMonitor _network;
  final KeyValueStore _store;
  final DateTime Function() _now;

  final int maxRetries;
  final Duration baseBackoff;
  final Duration maxBackoff;

  static const _lastSyncKey = 'last_sync_at';

  String? _userId;
  StreamSubscription<bool>? _networkSub;
  Timer? _retryTimer;
  bool _running = false;
  bool _rerunRequested = false;
  bool _rerunIgnoresBackoff = false;
  bool _disposed = false;

  List<LocalEvidence> _evidences = const [];
  bool _online = true;
  DateTime? _lastSyncAt;

  List<LocalEvidence> get evidences => _evidences;
  bool get isSyncing => _running;
  bool get isOnline => _online;
  DateTime? get lastSyncAt => _lastSyncAt;

  int get pendingCount => _evidences
      .where(
        (e) =>
            e.syncStatus == SyncStatus.pending ||
            e.syncStatus == SyncStatus.uploading,
      )
      .length;
  int get syncedCount =>
      _evidences.where((e) => e.syncStatus == SyncStatus.synced).length;
  int get failedCount =>
      _evidences.where((e) => e.syncStatus == SyncStatus.failed).length;

  /// Fracción sincronizada (0..1) para el indicador circular de la pantalla D.
  double get progress =>
      _evidences.isEmpty ? 1 : syncedCount / _evidences.length;

  LocalEvidence? findByUuid(String clientUuid) =>
      _evidences.where((e) => e.clientUuid == clientUuid).firstOrNull;

  /// Inicia la cola para el usuario autenticado.
  Future<void> start(String userId) async {
    if (_userId == userId) return;
    await stop();
    _userId = userId;
    final raw = await _store.readValue('$_lastSyncKey:$userId');
    _lastSyncAt = raw == null ? null : DateTime.parse(raw);
    await _repository.recoverInterruptedUploads();
    _online = await _network.isOnline();
    _networkSub = _network.onStatusChange.listen((online) {
      _online = online;
      _notify();
      if (online) unawaited(syncNow());
    });
    await refresh();
    unawaited(syncNow());
  }

  Future<void> stop() async {
    await _networkSub?.cancel();
    _networkSub = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _userId = null;
    _evidences = const [];
    _lastSyncAt = null;
    _notify();
  }

  Future<void> refresh() async {
    final userId = _userId;
    if (userId == null) return;
    _evidences = await _repository.getAll(userId);
    _notify();
  }

  /// Procesa la cola. Con [ignoreBackoff] (botón "Sincronizar ahora") también
  /// envía las que esperan su próximo reintento.
  Future<void> syncNow({bool ignoreBackoff = false}) async {
    final userId = _userId;
    if (userId == null) return;
    if (_running) {
      _rerunRequested = true;
      _rerunIgnoresBackoff |= ignoreBackoff;
      return;
    }
    _running = true;
    _retryTimer?.cancel();
    _notify();

    try {
      var ignore = ignoreBackoff;
      do {
        _rerunRequested = false;
        _rerunIgnoresBackoff = false;
        await _processQueue(userId, ignoreBackoff: ignore);
        ignore = _rerunIgnoresBackoff;
      } while (_rerunRequested && _userId == userId);
    } finally {
      _running = false;
      await refresh();
      await _scheduleNextRetry(userId);
    }
  }

  Future<void> _processQueue(
    String userId, {
    required bool ignoreBackoff,
  }) async {
    _online = await _network.isOnline();
    if (!_online) return;

    final cutoff = ignoreBackoff ? DateTime.utc(9999) : _now();
    final due = await _repository.getDueForSync(userId, cutoff);
    var anySuccess = false;

    for (final evidence in due) {
      if (_userId != userId) return;
      final id = evidence.localId!;
      await _repository.markUploading(id);
      await refresh();
      try {
        final receipt = await _repository.upload(evidence);
        await _repository.markSynced(id, receipt);
        anySuccess = true;
      } on UnauthorizedException catch (e) {
        // Sesión expirada: se conserva la evidencia y se detiene la cola.
        await _repository.markRetry(
          id,
          retryCount: evidence.retryCount,
          // No reintentar de inmediato: evita un bucle de 401 mientras se
          // cierra la sesión. Tras el nuevo login, start() la envía.
          nextRetryAt: _now().add(baseBackoff),
          error: e.toString(),
        );
        break;
      } on NetworkException catch (e) {
        await _handleTransient(evidence, e.toString());
        // Si la red falla, el resto de la cola también fallaría.
        break;
      } on PermanentException catch (e) {
        await _repository.markFailed(id, e.toString());
      } catch (e) {
        // Archivo inaccesible u otro error local inesperado.
        await _repository.markFailed(id, 'LOCAL_ERROR: ${e.runtimeType}');
      }
    }

    if (anySuccess || due.isEmpty) {
      _lastSyncAt = _now();
      await _store.writeValue(
        '$_lastSyncKey:$userId',
        _lastSyncAt!.toUtc().toIso8601String(),
      );
    }
  }

  Future<void> _handleTransient(LocalEvidence evidence, String error) async {
    final attempts = evidence.retryCount + 1;
    if (attempts >= maxRetries) {
      await _repository.markFailed(
        evidence.localId!,
        '$error (sin éxito tras $attempts intentos)',
      );
      return;
    }
    await _repository.markRetry(
      evidence.localId!,
      retryCount: attempts,
      nextRetryAt: _now().add(backoffFor(attempts)),
      error: error,
    );
  }

  /// Backoff exponencial: base · 2^(intento-1), acotado por [maxBackoff].
  Duration backoffFor(int attempt) {
    final factor = pow(2, max(0, attempt - 1)).toInt();
    final ms = baseBackoff.inMilliseconds * factor;
    return Duration(milliseconds: min(ms, maxBackoff.inMilliseconds));
  }

  Future<void> _scheduleNextRetry(String userId) async {
    if (_disposed || _userId != userId) return;
    final next = await _repository.nextScheduledRetry(userId);
    if (next == null) return;
    var delay = next.difference(_now());
    if (delay.isNegative) delay = Duration.zero;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => unawaited(syncNow()));
  }

  /// Reintento manual de una evidencia en estado FAILED.
  Future<void> retry(LocalEvidence evidence) async {
    await _repository.resetForRetry(evidence.localId!);
    await refresh();
    await syncNow(ignoreBackoff: true);
  }

  /// Descarta una evidencia local (requiere confirmación en la UI, §4.3.6).
  Future<void> discard(LocalEvidence evidence) async {
    await _repository.discard(evidence);
    await refresh();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _networkSub?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }
}
