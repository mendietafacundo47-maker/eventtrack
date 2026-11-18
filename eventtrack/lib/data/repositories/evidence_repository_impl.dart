import 'dart:io';

import '../../core/config/app_config.dart';
import '../../domain/entities/local_evidence.dart';
import '../../domain/repositories/repositories.dart';
import '../local/evidence_local_data_source.dart';
import '../remote/remote_data_sources.dart';

class EvidenceRepositoryImpl implements EvidenceRepository {
  EvidenceRepositoryImpl(this._local, this._remote);

  final EvidenceLocalDataSource _local;
  final RemoteDataSource _remote;

  @override
  Future<LocalEvidence> saveLocal(LocalEvidence evidence) async {
    final id = await _local.insert(evidence);
    return (await _local.getById(id))!;
  }

  @override
  Future<List<LocalEvidence>> getAll(String userId) => _local.getAll(userId);

  @override
  Future<List<LocalEvidence>> getDueForSync(String userId, DateTime now) =>
      _local.getDue(userId, now);

  @override
  Future<DateTime?> nextScheduledRetry(String userId) =>
      _local.nextScheduledRetry(userId);

  @override
  Future<void> markUploading(int localId) =>
      _local.update(localId, {'sync_status': SyncStatus.uploading.code});

  @override
  Future<void> markSynced(int localId, EvidenceReceipt receipt) async {
    await _local.update(localId, {
      'sync_status': SyncStatus.synced.code,
      'server_evidence_id': receipt.evidenceId,
      'server_received_at': receipt.receivedAt.toUtc().toIso8601String(),
      'next_retry_at': null,
      'last_error': null,
    });
    if (AppConfig.deleteLocalPhotoAfterSync) {
      // Solo después de la confirmación del servidor (§4.4.7).
      final evidence = await _local.getById(localId);
      if (evidence != null) await _deleteFile(evidence.photoPath);
    }
  }

  @override
  Future<void> markRetry(
    int localId, {
    required int retryCount,
    required DateTime nextRetryAt,
    required String error,
  }) => _local.update(localId, {
    'sync_status': SyncStatus.pending.code,
    'retry_count': retryCount,
    'next_retry_at': nextRetryAt.toUtc().toIso8601String(),
    'last_error': error,
  });

  @override
  Future<void> markFailed(int localId, String error) => _local.update(localId, {
    'sync_status': SyncStatus.failed.code,
    'next_retry_at': null,
    'last_error': error,
  });

  @override
  Future<void> resetForRetry(int localId) => _local.update(localId, {
    'sync_status': SyncStatus.pending.code,
    'retry_count': 0,
    'next_retry_at': null,
  });

  @override
  Future<int> recoverInterruptedUploads() => _local.resetUploading();

  @override
  Future<void> discard(LocalEvidence evidence) async {
    await _local.delete(evidence.localId!);
    await _deleteFile(evidence.photoPath);
  }

  @override
  Future<EvidenceReceipt> upload(LocalEvidence evidence) =>
      _remote.uploadEvidence(evidence);

  Future<void> _deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
