import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../domain/entities/local_evidence.dart';
import '../application/sync_service.dart';

/// Pantalla D. Sincronización (§4.4.2, RF-12, RF-13).
class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final items = sync.evidences;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(sync: sync),
            if (!sync.isOnline)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: InfoBanner(
                  message:
                      'Sin conexión. Las evidencias se enviarán '
                      'automáticamente al recuperar la red.',
                ),
              ),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: EmptyState(
                        icon: Icons.cloud_done_outlined,
                        title: 'No hay evidencias registradas',
                        message:
                            'Las evidencias que registres aparecerán '
                            'aquí con su estado de sincronización.',
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => sync.syncNow(ignoreBackoff: true),
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) =>
                            _EvidenceTile(evidence: items[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: sync.isSyncing || sync.pendingCount == 0
                    ? null
                    : () => sync.syncNow(ignoreBackoff: true),
                icon: sync.isSyncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.sync),
                label: Text(
                  sync.isSyncing ? 'SINCRONIZANDO...' : 'SINCRONIZAR AHORA',
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.history,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    sync.lastSyncAt == null
                        ? 'Aún no se ha sincronizado'
                        : 'Última sincronización: '
                              '${Formatters.dateTime(sync.lastSyncAt!)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.sync});

  final SyncService sync;

  @override
  Widget build(BuildContext context) {
    final percent = (sync.progress * 100).round();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'SINCRONIZACIÓN',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Semantics(
                label: '$percent por ciento sincronizado',
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: sync.progress,
                        strokeWidth: 4,
                        backgroundColor: AppColors.border,
                        color: AppColors.action,
                      ),
                      Text(
                        '$percent%',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _CountChip(
                count: sync.pendingCount,
                label: sync.pendingCount == 1 ? 'Pendiente' : 'Pendientes',
                color: AppColors.warning,
              ),
              _CountChip(
                count: sync.syncedCount,
                label: sync.syncedCount == 1 ? 'Sincronizada' : 'Sincronizadas',
                color: AppColors.success,
              ),
              if (sync.failedCount > 0)
                _CountChip(
                  count: sync.failedCount,
                  label: 'Con error',
                  color: AppColors.error,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.count,
    required this.label,
    required this.color,
  });

  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.tint(color),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$count $label',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  const _EvidenceTile({required this.evidence});

  final LocalEvidence evidence;

  Future<void> _showActions(BuildContext context) async {
    final sync = context.read<SyncService>();
    final e = evidence;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                e.activityTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                e.eventName,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              if (File(e.photoPath).existsSync())
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(e.photoPath),
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(height: 12),
              _kv('Estado', e.syncStatus.label),
              _kv('Capturada', Formatters.dateTime(e.capturedAt)),
              _kv(
                'Ubicación',
                e.location.isAvailable
                    ? '${Formatters.coordinates(e.location.latitude!, e.location.longitude!)}'
                          '${e.location.accuracyM == null ? '' : ' (±${e.location.accuracyM!.toStringAsFixed(0)} m)'}'
                    : e.location.status.label,
              ),
              if (e.notes.isNotEmpty) _kv('Observación', e.notes),
              if (e.retryCount > 0) _kv('Intentos', '${e.retryCount}'),
              if (e.nextRetryAt != null && e.syncStatus == SyncStatus.pending)
                _kv('Próximo intento', Formatters.dateTime(e.nextRetryAt!)),
              if (e.serverReceivedAt != null)
                _kv(
                  'Recibida por servidor',
                  Formatters.dateTime(e.serverReceivedAt!),
                ),
              if (e.lastError != null && e.syncStatus != SyncStatus.synced)
                _kv('Último error', e.lastError!),
              const SizedBox(height: 12),
              if (e.syncStatus == SyncStatus.failed)
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    sync.retry(e);
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('REINTENTAR ENVÍO'),
                ),
              if (e.syncStatus != SyncStatus.uploading) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                  onPressed: () async {
                    final ok = await _confirmDiscard(sheetContext, e);
                    if (ok && sheetContext.mounted) {
                      Navigator.pop(sheetContext);
                      await sync.discard(e);
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: Text(
                    e.syncStatus == SyncStatus.synced
                        ? 'Quitar del dispositivo'
                        : 'Descartar evidencia',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Future<bool> _confirmDiscard(
    BuildContext context,
    LocalEvidence e,
  ) async {
    final synced = e.syncStatus == SyncStatus.synced;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          synced ? '¿Quitar del dispositivo?' : '¿Descartar evidencia?',
        ),
        content: Text(
          synced
              ? 'La evidencia ya está en el servidor. Solo se eliminará la copia local.'
              : 'Esta evidencia NO se ha sincronizado. Si la descartas se perderá '
                    'definitivamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(synced ? 'Quitar' : 'Descartar'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  static Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(k, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: Text(
            v,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final e = evidence;
    final (color, icon) = StatusChip.syncStyle(e.syncStatus);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showActions(context),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 5)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.tint(color),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: e.syncStatus == SyncStatus.uploading
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: color,
                        ),
                      )
                    : Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.activityTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '${e.eventName} · ${Formatters.dateTime(e.capturedAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (e.syncStatus == SyncStatus.failed &&
                        e.lastError != null)
                      Text(
                        e.lastError!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.error,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusChip.sync(e.syncStatus),
            ],
          ),
        ),
      ),
    );
  }
}
