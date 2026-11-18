/// Formateo de fechas sin dependencias extra. Las fechas se guardan en UTC y
/// se muestran en la hora local del dispositivo.
class Formatters {
  Formatters._();

  static const _months = [
    'Ene',
    'Feb',
    'Mar',
    'Abr',
    'May',
    'Jun',
    'Jul',
    'Ago',
    'Sep',
    'Oct',
    'Nov',
    'Dic',
  ];

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// 12 Nov 2026
  static String shortDate(DateTime date) {
    final d = date.toLocal();
    return '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  /// 12/11/2026
  static String date(DateTime date) {
    final d = date.toLocal();
    return '${_two(d.day)}/${_two(d.month)}/${d.year}';
  }

  /// 12/11/2026 - 14:30
  static String dateTime(DateTime date) {
    final d = date.toLocal();
    return '${Formatters.date(d)} - ${_two(d.hour)}:${_two(d.minute)}';
  }

  static String coordinates(double lat, double lng) =>
      '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';

  static String meters(double m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';
}
