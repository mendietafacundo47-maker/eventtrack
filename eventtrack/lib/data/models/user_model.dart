import '../../domain/entities/user.dart';

class UserModel {
  UserModel._();

  static User fromJson(Map<String, dynamic> json) => User(
    id: json['id'].toString(),
    fullName: json['fullName'] as String,
    email: json['email'] as String,
    role: UserRole.fromCode(json['role'] as String?),
  );

  static Map<String, dynamic> toJson(User u) => {
    'id': u.id,
    'fullName': u.fullName,
    'email': u.email,
    'role': u.role.code,
  };
}
