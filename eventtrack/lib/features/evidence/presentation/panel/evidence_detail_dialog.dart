import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../data/remote/panel_api.dart';
import '../../../../domain/entities/panel.dart';
import '../../../panel/presentation/panel_widgets.dart';

const _locationLabels = {
  'PERMISSION_DENIED': 'Permiso de ubicación denegado',
  'PERMISSION_DENIED_FOREVER': 'Permiso de ubicación bloqueado',
  'SERVICE_DISABLED': 'GPS desactivado en el dispositivo',
  'UNAVAILABLE': 'Sin lectura GPS válida',
};

/// Describe la ubicación sin inventar datos (RB-07).
String locationSummary(EvidenceRecord e) {
  if (!e.hasLocation) {
    return _locationLabels[e.locationStatus] ?? 'No disponible';
  }
  final accuracy = e.accuracyM == null
      ? ''
      : ' (±${Formatters.meters(e.accuracyM!)})';
  return '${e.latitude!.toStringAsFixed(5)}, ${e.longitude!.toStringAsFixed(5)}$accuracy';
}

/// Abre la evidencia: foto, metadatos, historial y revisión (P-07).
/// Devuelve `true` si se registró una revisión.
Future<bool> showEvidenceDetail(BuildContext context, String evidenceId) async {
  final reviewed = await showDialog<bool>(
    context: context,
    builder: (_) => Provider.value(
      value: context.read<PanelApi>(),
      child: _EvidenceDetailDialog(
        evidenceId: evidenceId,
        canReview: panelUser(context).canReview,
      ),
    ),
  );
  return reviewed ?? false;
}

/// Revisión rápida desde una tabla. El rechazo siempre pide motivo (TC-20).
Future<bool> quickReview(
  BuildContext context,
  String evidenceId,
  ReviewStatus result,
) async {
  final api = context.read<PanelApi>();
  String comment = '';
  if (result == ReviewStatus.rejected) {
    final reason = await _askRejectReason(context);
    if (reason == null) return false;
    comment = reason;
  } else {
    final ok = await confirmAction(
      context,
      title: 'Aprobar evidencia',
      message: 'La actividad se marcará como completada.',
      confirmLabel: 'Aprobar',
    );
    if (!ok) return false;
  }
  try {
    await api.review(evidenceId, result, comment);
    if (context.mounted) {
      showPanelMessage(
        context,
        result == ReviewStatus.approved
            ? 'Evidencia aprobada.'
            : 'Evidencia rechazada.',
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      showPanelMessage(context, errorMessage(e), error: true);
    }
    return false;
  }
}

Future<String?> _askRejectReason(BuildContext context) {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rechazar evidencia'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            maxLength: 1000,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Motivo del rechazo',
              hintText: 'Ej.: la foto no muestra el ambiente preparado.',
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Indica el motivo del rechazo.'
                : null,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child: const Text('Rechazar'),
        ),
      ],
    ),
  );
}

class _EvidenceDetailDialog extends StatefulWidget {
  const _EvidenceDetailDialog({
    required this.evidenceId,
    required this.canReview,
  });

  final String evidenceId;
  final bool canReview;

  @override
  State<_EvidenceDetailDialog> createState() => _EvidenceDetailDialogState();
}

class _EvidenceDetailDialogState extends State<_EvidenceDetailDialog> {
  late final PanelApi _api = context.read<PanelApi>();
  final _comment = TextEditingController();
  late Future<EvidenceRecord> _evidence;
  late final Future<Uint8List> _photo = _api.evidencePhoto(widget.evidenceId);
  bool _sending = false;
  String? _commentError;

  @override
  void initState() {
    super.initState();
    _evidence = _api.evidence(widget.evidenceId);
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _review(ReviewStatus result) async {
    final comment = _comment.text.trim();
    if (result == ReviewStatus.rejected && comment.isEmpty) {
      setState(() => _commentError = 'Indica el motivo del rechazo.');
      return;
    }
    setState(() {
      _sending = true;
      _commentError = null;
    });
    try {
      await _api.review(widget.evidenceId, result, comment);
      if (!mounted) return;
      showPanelMessage(
        context,
        result == ReviewStatus.approved
            ? 'Evidencia aprobada.'
            : 'Evidencia rechazada.',
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      showPanelMessage(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 900;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1000,
          maxHeight: size.height * 0.9,
        ),
        child: FutureBuilder<EvidenceRecord>(
          future: _evidence,
          builder: (context, snap) {
            if (snap.hasError) {
              return ErrorBox(
                message: errorMessage(snap.error!),
                onRetry: () => setState(() {
                  _evidence = _api.evidence(widget.evidenceId);
                }),
              );
            }
            if (!snap.hasData) return const LoadingBox();
            final e = snap.data!;
            final photo = _Photo(future: _photo);
            final details = _details(e);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(e),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 5, child: photo),
                              const SizedBox(width: 24),
                              Expanded(flex: 4, child: details),
                            ],
                          )
                        : Column(
                            children: [
                              photo,
                              const SizedBox(height: 16),
                              details,
                            ],
                          ),
                  ),
                ),
                if (widget.canReview && e.status == ReviewStatus.pending) ...[
                  const Divider(height: 1),
                  _reviewBar(),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(EvidenceRecord e) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
    child: Row(
      children: [
        Expanded(
          child: Column(
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
            ],
          ),
        ),
        reviewStatusChip(e.status),
        IconButton(
          tooltip: 'Cerrar',
          onPressed: () => Navigator.pop(context, false),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );

  Widget _details(EvidenceRecord e) {
    Widget row(String label, Widget value) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          value,
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row('Responsable', Text(e.createdByName)),
        row(
          'Estado de la actividad',
          Align(
            alignment: Alignment.centerLeft,
            child: StatusChip.activity(e.activityStatus),
          ),
        ),
        // §4.3.5: hora del dispositivo y del servidor por separado.
        row('Capturada (dispositivo)', Text(Formatters.dateTime(e.capturedAt))),
        row('Recibida (servidor)', Text(Formatters.dateTime(e.receivedAt))),
        row(
          'Ubicación GPS',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    e.hasLocation ? Icons.place : Icons.location_off,
                    size: 18,
                    color: e.hasLocation ? AppColors.error : AppColors.neutral,
                  ),
                  const SizedBox(width: 4),
                  Expanded(child: SelectableText(locationSummary(e))),
                ],
              ),
              if (e.distanceToEventM != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'A ${Formatters.meters(e.distanceToEventM!)} del punto del evento '
                    '(indicador, no prueba de presencia).',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              if (e.hasLocation)
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.https('www.google.com', '/maps', {
                      'q': '${e.latitude},${e.longitude}',
                    }),
                    webOnlyWindowName: '_blank',
                  ),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Ver en el mapa'),
                ),
            ],
          ),
        ),
        row(
          'Observación',
          Text(e.notes.isEmpty ? 'Sin observación.' : e.notes),
        ),
        if (e.reviews.isNotEmpty)
          row(
            'Historial de revisión',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in e.reviews)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${r.result.label} por ${r.reviewerName} · '
                      '${Formatters.dateTime(r.reviewedAt)}'
                      '${r.comment.isEmpty ? '' : '\n“${r.comment}”'}',
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _reviewBar() => Padding(
    padding: const EdgeInsets.all(16),
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.end,
      children: [
        SizedBox(
          width: 420,
          child: TextField(
            controller: _comment,
            enabled: !_sending,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: 'Comentario (obligatorio para rechazar)',
              errorText: _commentError,
              isDense: true,
              counterText: '',
            ),
          ),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: const BorderSide(color: AppColors.error),
          ),
          onPressed: _sending ? null : () => _review(ReviewStatus.rejected),
          icon: const Icon(Icons.close),
          label: const Text('Rechazar'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.success),
          onPressed: _sending ? null : () => _review(ReviewStatus.approved),
          icon: const Icon(Icons.check),
          label: const Text('Aprobar'),
        ),
      ],
    ),
  );
}

class _Photo extends StatelessWidget {
  const _Photo({required this.future});

  final Future<Uint8List> future;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: AppColors.background,
        constraints: const BoxConstraints(minHeight: 240, maxHeight: 520),
        alignment: Alignment.center,
        child: FutureBuilder<Uint8List>(
          future: future,
          builder: (context, snap) {
            if (snap.hasError) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No se pudo cargar la fotografía.'),
              );
            }
            if (!snap.hasData) return const CircularProgressIndicator();
            return Semantics(
              label: 'Fotografía de la evidencia',
              image: true,
              child: Image.memory(
                snap.data!,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'El archivo de la fotografía no se puede mostrar.',
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
