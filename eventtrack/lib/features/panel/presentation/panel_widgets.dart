import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../domain/entities/panel.dart';
import '../../../domain/entities/user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../application/panel_selection.dart';

/// Permisos de interfaz por rol. Solo ocultan acciones: el backend vuelve a
/// verificar cada operación (§4.3.7).
extension PanelPermissions on User {
  bool get canManageEvents =>
      role == UserRole.admin || role == UserRole.organizer;
  bool get canReview => role == UserRole.admin || role == UserRole.supervisor;
  bool get isAdmin => role == UserRole.admin;
}

User panelUser(BuildContext context) => context.read<AuthController>().user!;

String errorMessage(Object error) =>
    error is AppException ? error.message : 'Ocurrió un error inesperado.';

void showPanelMessage(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        width: 480,
      ),
    );
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: AppColors.error)
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Contenedor de página: título, acciones y contenido con ancho máximo.
class PanelPage extends StatelessWidget {
  const PanelPage({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return SingleChildScrollView(
      padding: EdgeInsets.all(wide ? 24 : 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (actions.isNotEmpty)
                    Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ),
              const SizedBox(height: 20),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta blanca con título opcional.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    title!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

/// Indicador del resumen (diseño del panel web, §4.4.2).
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.filled = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: filled ? AppColors.tint(color) : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: filled ? color.withValues(alpha: 0.3) : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: filled
                  ? color.withValues(alpha: 0.18)
                  : AppColors.tint(color),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: filled ? color : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de tarjetas que pasa a columna en pantallas angostas.
class ResponsiveRow extends StatelessWidget {
  const ResponsiveRow({
    super.key,
    required this.children,
    this.minChildWidth = 220,
  });

  final List<Widget> children;
  final double minChildWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = (c.maxWidth / minChildWidth).floor().clamp(
          1,
          children.length,
        );
        final width = (c.maxWidth - 12 * (perRow - 1)) / perRow;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

/// Tabla con desplazamiento horizontal en pantallas angostas.
class PanelTable extends StatelessWidget {
  const PanelTable({
    super.key,
    required this.columns,
    required this.rows,
    this.emptyMessage = 'No hay registros.',
  });

  final List<String> columns;
  final List<DataRow> rows;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            emptyMessage,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: c.maxWidth),
          child: DataTable(
            // Las filas se abren con un botón propio, sin casillas.
            showCheckboxColumn: false,
            columnSpacing: 24,
            horizontalMargin: 16,
            headingRowColor: const WidgetStatePropertyAll(AppColors.background),
            headingTextStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: AppColors.textSecondary,
            ),
            dataRowMinHeight: 56,
            dataRowMaxHeight: double.infinity,
            columns: [
              for (final c in columns) DataColumn(label: Text(c.toUpperCase())),
            ],
            rows: rows,
          ),
        ),
      ),
    );
  }
}

/// Paginación simple (§4.3.6: tablas con paginación).
class Pager extends StatelessWidget {
  const Pager({
    super.key,
    required this.offset,
    required this.limit,
    required this.total,
    required this.onChanged,
  });

  final int offset;
  final int limit;
  final int total;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (total <= limit) return const SizedBox.shrink();
    final from = total == 0 ? 0 : offset + 1;
    final to = (offset + limit).clamp(0, total);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '$from–$to de $total',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          IconButton(
            tooltip: 'Anterior',
            onPressed: offset == 0 ? null : () => onChanged(offset - limit),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: 'Siguiente',
            onPressed: to >= total ? null : () => onChanged(offset + limit),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class LoadingBox extends StatelessWidget {
  const LoadingBox({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 48),
    child: Center(child: CircularProgressIndicator()),
  );
}

class ErrorBox extends StatelessWidget {
  const ErrorBox({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            color: AppColors.error,
            size: 36,
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

StatusChip eventStatusChip(EventStatus status) {
  final (color, icon) = switch (status) {
    EventStatus.draft => (AppColors.neutral, Icons.edit_note),
    EventStatus.active => (AppColors.success, Icons.play_circle_outline),
    EventStatus.closed => (AppColors.primary, Icons.lock_outline),
    EventStatus.cancelled => (AppColors.error, Icons.block),
  };
  return StatusChip(label: status.label, color: color, icon: icon);
}

StatusChip reviewStatusChip(ReviewStatus status) {
  final (color, icon) = switch (status) {
    ReviewStatus.pending => (AppColors.warning, Icons.schedule),
    ReviewStatus.approved => (AppColors.success, Icons.check_circle_outline),
    ReviewStatus.rejected => (AppColors.error, Icons.cancel_outlined),
  };
  return StatusChip(label: status.label, color: color, icon: icon);
}

/// Selector del evento de trabajo, compartido entre páginas.
class EventSelector extends StatelessWidget {
  const EventSelector({super.key, this.allowAll = false});

  /// Permite la opción "Todos los eventos" (bandeja de evidencias).
  final bool allowAll;

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<PanelSelection>();
    if (selection.loading && selection.events.isEmpty) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final value = allowAll ? selection.filterEventId : selection.selectedId;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 420),
      child: DropdownButtonFormField<String?>(
        initialValue: value,
        key: ValueKey('event-$value-${selection.events.length}'),
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Evento',
          prefixIcon: Icon(Icons.event_outlined),
          isDense: true,
        ),
        items: [
          if (allowAll)
            const DropdownMenuItem(
              value: null,
              child: Text('Todos los eventos'),
            ),
          for (final e in selection.events)
            DropdownMenuItem(
              value: e.id,
              child: Text(
                '${e.name} · ${e.status.label}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (id) => allowAll
            ? selection.setFilter(id)
            : (id == null ? null : selection.select(id)),
      ),
    );
  }
}

/// Mensaje cuando el usuario aún no tiene eventos visibles.
class NoEventsBox extends StatelessWidget {
  const NoEventsBox({super.key});

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<PanelSelection>();
    if (selection.error != null) {
      return ErrorBox(message: selection.error!, onRetry: selection.load);
    }
    return const SectionCard(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(Icons.event_busy_outlined, size: 36, color: AppColors.neutral),
            SizedBox(height: 8),
            Text('Todavía no hay eventos. Crea uno en la sección Eventos.'),
          ],
        ),
      ),
    );
  }
}
