import 'package:flutter/material.dart';

import '../../domain/entities/assignment.dart';
import '../../domain/entities/local_evidence.dart';
import '../theme/app_colors.dart';

/// Etiqueta de estado: siempre color + icono + texto, nunca solo color
/// (§4.3.6, §4.4.3).
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    required this.icon,
  });

  factory StatusChip.activity(ActivityStatus status) {
    final (color, icon) = switch (status) {
      ActivityStatus.pending => (AppColors.warning, Icons.schedule),
      ActivityStatus.inProgress => (
        AppColors.action,
        Icons.play_circle_outline,
      ),
      ActivityStatus.submitted => (AppColors.primary, Icons.outbox_outlined),
      ActivityStatus.completed => (
        AppColors.success,
        Icons.check_circle_outline,
      ),
      ActivityStatus.cancelled => (AppColors.neutral, Icons.block),
    };
    return StatusChip(label: status.label, color: color, icon: icon);
  }

  factory StatusChip.sync(SyncStatus status) {
    final (color, icon) = syncStyle(status);
    return StatusChip(label: status.label, color: color, icon: icon);
  }

  static (Color, IconData) syncStyle(SyncStatus status) => switch (status) {
    SyncStatus.pending => (AppColors.warning, Icons.schedule),
    SyncStatus.uploading => (AppColors.action, Icons.cloud_upload_outlined),
    SyncStatus.synced => (AppColors.success, Icons.cloud_done_outlined),
    SyncStatus.failed => (AppColors.error, Icons.error_outline),
  };

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.tint(color),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
