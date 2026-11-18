import 'package:flutter/material.dart';

/// Paleta oficial de EventTrack (informe §4.1.3 y §4.4.3).
///
/// Los colores de estado siempre se acompañan de texto; nunca transmiten
/// información por sí solos (§4.3.6).
class AppColors {
  AppColors._();

  /// Azul profundo: encabezados y navegación.
  static const Color primary = Color(0xFF17365D);

  /// Azul de acción: botones primarios.
  static const Color action = Color(0xFF2563EB);

  /// Verde: aprobado / sincronizado.
  static const Color success = Color(0xFF16803C);

  /// Ámbar: pendiente.
  static const Color warning = Color(0xFFB7791F);

  /// Rojo: rechazo / error.
  static const Color error = Color(0xFFB42318);

  static const Color background = Color(0xFFF5F7FA);
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF4B5563);
  static const Color border = Color(0xFFE5E7EB);
  static const Color neutral = Color(0xFF6B7280);

  static Color tint(Color color) => color.withValues(alpha: 0.12);
}
