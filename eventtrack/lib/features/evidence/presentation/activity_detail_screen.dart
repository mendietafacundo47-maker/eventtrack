import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../domain/entities/assignment.dart';
import '../../../domain/entities/geo_reading.dart';
import '../../../domain/repositories/repositories.dart';
import '../../activities/presentation/activities_controller.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../sync/application/sync_service.dart';
import '../services/location_service.dart';
import '../services/photo_service.dart';
import 'evidence_form_controller.dart';

/// Resuelve la asignación (desde la navegación o la caché local) y monta la
/// Pantalla C.
class ActivityDetailRoute extends StatelessWidget {
  const ActivityDetailRoute({
    super.key,
    required this.assignmentId,
    this.initial,
  });

  final String assignmentId;
  final Assignment? initial;

  @override
  Widget build(BuildContext context) {
    if (initial != null) return _withController(context, initial!);
    return FutureBuilder<Assignment?>(
      future: context.read<ActivitiesController>().findById(assignmentId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final assignment = snapshot.data;
        if (assignment == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('DETALLE')),
            body: const Center(
              child: EmptyState(
                icon: Icons.search_off,
                title: 'Actividad no encontrada',
                message: 'Puede que ya no esté asignada a tu cuenta.',
              ),
            ),
          );
        }
        return _withController(context, assignment);
      },
    );
  }

  Widget _withController(BuildContext context, Assignment assignment) {
    return ChangeNotifierProvider(
      create: (context) => EvidenceFormController(
        assignment: assignment,
        user: context.read<AuthController>().user!,
        photos: context.read<PhotoService>(),
        location: context.read<LocationService>(),
        repository: context.read<EvidenceRepository>(),
        sync: context.read<SyncService>(),
      )..recoverLostPhoto(),
      child: const ActivityDetailScreen(),
    );
  }
}

/// Pantalla C. Detalle y registro de evidencia (§4.4.2, CU-07).
class ActivityDetailScreen extends StatefulWidget {
  const ActivityDetailScreen({super.key});

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  Future<bool> _confirmDiscard() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Descartar evidencia?'),
        content: const Text(
          'La fotografía y los datos capturados aún no se han guardado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Seguir editando'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _choosePhotoSource(EvidenceFormController c) async {
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto con la cámara'),
              onTap: () => Navigator.pop(context, PhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Seleccionar de la galería'),
              onTap: () => Navigator.pop(context, PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await c.pickPhoto(source);
  }

  Future<void> _save(EvidenceFormController c) async {
    FocusScope.of(context).unfocus();
    if (c.photo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agrega una fotografía antes de guardar.'),
        ),
      );
      return;
    }
    if (c.locating) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Espera a que termine la lectura de ubicación.'),
        ),
      );
      return;
    }
    final reading = c.reading;
    if (reading == null || !reading.isAvailable) {
      // RB-06/RB-07: se permite guardar sin ubicación, marcándola como no
      // disponible, pero el usuario debe saberlo.
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Guardar sin ubicación'),
          content: const Text(
            'No se obtuvo una ubicación GPS válida. La evidencia se guardará '
            'con la ubicación marcada como "no disponible".',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar igual'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    if (!mounted) return;
    final activities = context.read<ActivitiesController>();
    final result = await c.save();
    // El backend cambia la actividad a SUBMITTED al recibir la evidencia.
    if (result.outcome == SaveOutcome.synced) unawaited(activities.load());
    if (!mounted) return;
    final color = switch (result.outcome) {
      SaveOutcome.synced => AppColors.success,
      SaveOutcome.pending => AppColors.warning,
      SaveOutcome.failed => AppColors.error,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message), backgroundColor: color),
    );
    if (!c.hasUnsavedData) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EvidenceFormController>();
    final a = c.assignment;
    final canRegister = a.activityStatus.acceptsEvidence;

    return PopScope(
      canPop: !c.hasUnsavedData,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leadingWidth: 100,
          leading: TextButton.icon(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Volver'),
          ),
          centerTitle: true,
          title: const Text('DETALLE'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _ActivityInfoCard(
              assignment: a,
              responsible: context.read<AuthController>().user?.fullName ?? '',
            ),
            const SizedBox(height: 16),
            if (!canRegister)
              const InfoBanner(
                icon: Icons.lock_outline,
                color: AppColors.neutral,
                message:
                    'Esta actividad no admite nuevas evidencias por su estado.',
              )
            else ...[
              _PhotoSection(controller: c, onPick: () => _choosePhotoSource(c)),
              const SizedBox(height: 16),
              _LocationSection(controller: c),
              const SizedBox(height: 16),
              TextField(
                enabled: !c.saving,
                minLines: 3,
                maxLines: 5,
                maxLength: AppConfig.maxNotesLength,
                onChanged: (v) => c.notes = v,
                decoration: const InputDecoration(
                  labelText: 'Observación',
                  hintText: 'Escribe una observación opcional...',
                  alignLabelWithHint: true,
                ),
              ),
            ],
            _PreviousEvidences(assignmentId: a.id),
          ],
        ),
        bottomNavigationBar: canRegister
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton.icon(
                    onPressed: c.saving ? null : () => _save(c),
                    icon: c.saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      c.saving ? 'GUARDANDO...' : 'GUARDAR EVIDENCIA',
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

class _ActivityInfoCard extends StatelessWidget {
  const _ActivityInfoCard({
    required this.assignment,
    required this.responsible,
  });

  final Assignment assignment;
  final String responsible;

  @override
  Widget build(BuildContext context) {
    final a = assignment;
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row('Actividad', a.activityTitle),
            row('Evento', a.eventName),
            row(
              'Fecha límite',
              a.dueAt == null ? 'Sin fecha' : Formatters.date(a.dueAt!),
            ),
            row('Responsable', responsible),
            const SizedBox(height: 8),
            StatusChip.activity(a.activityStatus),
            if (a.activityDescription.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                a.activityDescription,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PhotoSection extends StatelessWidget {
  const _PhotoSection({required this.controller, required this.onPick});

  final EvidenceFormController controller;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: c.saving ? null : onPick,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: AppColors.tint(AppColors.action),
          ),
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(
            c.photo == null ? 'TOMAR / ADJUNTAR FOTO' : 'CAMBIAR FOTO',
          ),
        ),
        if (c.photoError != null) ...[
          const SizedBox(height: 8),
          InfoBanner(
            icon: Icons.no_photography_outlined,
            color: AppColors.error,
            message: c.photoError!,
            action: TextButton(
              onPressed: onPick,
              child: const Text('Reintentar'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        AspectRatio(
          aspectRatio: 16 / 10,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: c.photo == null
                ? Container(
                    color: const Color(0xFFEFF2F6),
                    alignment: Alignment.center,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.image_outlined,
                          size: 40,
                          color: AppColors.neutral,
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Sin fotografía',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  )
                : Semantics(
                    label: 'Vista previa de la fotografía de evidencia',
                    image: true,
                    child: Image.file(File(c.photo!.path), fit: BoxFit.cover),
                  ),
          ),
        ),
        if (c.capturedAt != null) ...[
          const SizedBox(height: 6),
          Text(
            'Capturada: ${Formatters.dateTime(c.capturedAt!)}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

class _LocationSection extends StatelessWidget {
  const _LocationSection({required this.controller});

  final EvidenceFormController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final r = c.reading;

    final Widget content;
    if (c.locating) {
      content = const Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(width: 12),
          Expanded(child: Text('Obteniendo ubicación GPS...')),
        ],
      );
    } else if (r == null) {
      content = Row(
        children: [
          const Expanded(
            child: Text(
              'La ubicación se obtiene al capturar la fotografía.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: c.requestLocation,
            child: const Text('Obtener ahora'),
          ),
        ],
      );
    } else if (r.isAvailable) {
      final distance = c.distanceToEventM;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, color: AppColors.success, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  Formatters.coordinates(r.latitude!, r.longitude!),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Actualizar ubicación',
                onPressed: c.requestLocation,
                icon: const Icon(Icons.my_location),
              ),
            ],
          ),
          Text(
            r.accuracyM == null
                ? 'Precisión no informada por el dispositivo'
                : 'Precisión estimada: ±${r.accuracyM!.toStringAsFixed(0)} m',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          if (distance != null)
            Text(
              'A ${Formatters.meters(distance)} del punto del evento '
              '(indicador de referencia, no prueba de presencia)',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          if (c.lowAccuracy) ...[
            const SizedBox(height: 8),
            InfoBanner(
              icon: Icons.gps_not_fixed,
              message:
                  'Precisión baja. Si concediste ubicación aproximada, '
                  'activa "Usar ubicación precisa" en los permisos de '
                  'EventTrack, o reintenta en un lugar abierto.',
              action: TextButton(
                onPressed: c.openAppSettings,
                child: const Text('Ajustes'),
              ),
            ),
          ],
        ],
      );
    } else {
      final needsSettings =
          r.status == LocationStatus.serviceDisabled ||
          r.status == LocationStatus.permissionDeniedForever;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_off, color: AppColors.error, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  r.status.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _help(r.status),
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: c.requestLocation,
                child: const Text('Reintentar'),
              ),
              if (needsSettings)
                TextButton(
                  onPressed: () => c.openSettingsFor(r.status),
                  child: const Text('Abrir ajustes'),
                ),
            ],
          ),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ubicación GPS',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            content,
          ],
        ),
      ),
    );
  }

  static String _help(LocationStatus status) => switch (status) {
    LocationStatus.serviceDisabled =>
      'Activa la ubicación del dispositivo y vuelve a intentar.',
    LocationStatus.permissionDenied =>
      'EventTrack usa la ubicación solo al registrar evidencia. '
          'Concede el permiso para asociar coordenadas.',
    LocationStatus.permissionDeniedForever =>
      'El permiso está bloqueado. Habilítalo en Ajustes > Aplicaciones > '
          'EventTrack > Permisos > Ubicación.',
    _ =>
      'No se obtuvo una lectura válida. Prueba en un lugar abierto '
          'o vuelve a intentar.',
  };
}

class _PreviousEvidences extends StatelessWidget {
  const _PreviousEvidences({required this.assignmentId});

  final String assignmentId;

  @override
  Widget build(BuildContext context) {
    final list = context
        .watch<SyncService>()
        .evidences
        .where((e) => e.assignmentId == assignmentId)
        .toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Evidencias registradas',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          for (final e in list)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.photo_outlined),
              title: Text(Formatters.dateTime(e.capturedAt)),
              subtitle: e.location.isAvailable
                  ? Text(
                      Formatters.coordinates(
                        e.location.latitude!,
                        e.location.longitude!,
                      ),
                    )
                  : Text(e.location.status.label),
              trailing: StatusChip.sync(e.syncStatus),
            ),
        ],
      ),
    );
  }
}
