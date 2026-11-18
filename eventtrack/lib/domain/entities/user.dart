enum UserRole {
  admin('ADMIN', 'Administrador'),
  organizer('ORGANIZER', 'Organizador'),
  supervisor('SUPERVISOR', 'Supervisor'),
  responsible('RESPONSIBLE', 'Responsable');

  const UserRole(this.code, this.label);

  final String code;
  final String label;

  static UserRole fromCode(String? code) => UserRole.values.firstWhere(
    (r) => r.code == code?.toUpperCase(),
    orElse: () => UserRole.responsible,
  );
}

class User {
  const User({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
  });

  final String id;
  final String fullName;
  final String email;
  final UserRole role;

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.take(2).map((p) => p.isEmpty ? '' : p[0]).join().toUpperCase();
  }
}
