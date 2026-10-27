import 'package:dio/dio.dart';
import 'auth_service.dart';

class AdminUser {
  final int id;
  final String username;
  final String displayName;
  final String role;
  final bool active;
  final bool locked;
  final bool pinLocked;
  final bool hasPin;

  const AdminUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    required this.active,
    required this.locked,
    required this.pinLocked,
    required this.hasPin,
  });

  factory AdminUser.fromJson(Map j) => AdminUser(
        id: (j['id'] as num).toInt(),
        username: '${j['username']}',
        displayName: '${j['display_name'] ?? j['username']}',
        role: '${j['role']}',
        active: j['active'] == true,
        locked: j['locked'] == true,
        pinLocked: j['pin_locked'] == true,
        hasPin: j['has_pin'] == true,
      );
}

class UsersException implements Exception {
  final String message;
  const UsersException(this.message);
  @override
  String toString() => message;
}

/// The Administrator's user management (design, section 3): add users, deactivate them,
/// reset passwords and PINs. The Administrator manages accounts and cannot read logs.
class UsersService {
  final Dio _dio;

  UsersService(Session session, {Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: session.serverUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 20),
              headers: {'authorization': 'Bearer ${session.token}'},
            ));

  Future<T> _call<T>(Future<Response> Function() request, T Function(dynamic) read) async {
    try {
      return read((await request()).data);
    } on DioException catch (e) {
      if (e.response == null) throw const UsersException('Managing users needs a connection to the LogBridge server.');
      final d = e.response!.data;
      throw UsersException(d is Map && d['error'] != null ? '${d['error']}' : 'The server answered ${e.response!.statusCode}');
    }
  }

  Future<List<AdminUser>> list() =>
      _call(() => _dio.get('/api/admin/users'), (d) => [for (final u in (d['users'] as List)) AdminUser.fromJson(u as Map)]);

  Future<AdminUser> add({
    required String username,
    required String displayName,
    required String role,
    required String password,
    String? pin,
  }) =>
      _call(
        () => _dio.post('/api/admin/users', data: {
          'username': username,
          'display_name': displayName,
          'role': role,
          'password': password,
          if (pin != null && pin.isNotEmpty) 'pin': pin,
          if (role == Roles.viewer) 'all_vessels': false,
        }),
        (d) => AdminUser.fromJson(d as Map),
      );

  /// Any of: display_name, role, active, password, pin, unlock.
  Future<AdminUser> update(int id, Map<String, dynamic> changes) =>
      _call(() => _dio.patch('/api/admin/users/$id', data: changes), (d) => AdminUser.fromJson(d as Map));
}
