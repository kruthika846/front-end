import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pbkdf2.dart';

/// The roles of the LogBridge design (Architecture and Design, section 3) and what each may do.
class Roles {
  static const duty = 'duty_engineer';
  static const chief = 'chief_engineer';
  static const captain = 'captain';
  static const viewer = 'viewer';
  static const admin = 'admin';

  static const entry = {duty, chief, captain};
  static const approvers = {chief, captain};

  static String label(String role) => const {
        duty: 'Duty Engineer',
        chief: 'Chief Engineer',
        captain: 'Captain',
        viewer: 'Dashboard viewer',
        admin: 'Administrator',
      }[role] ??
      role;
}

class SessionUser {
  final int id;
  final String username;
  final String displayName;
  final String role;
  final int? vesselId;
  final bool hasPin;

  const SessionUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    this.vesselId,
    this.hasPin = false,
  });

  factory SessionUser.fromJson(Map<String, dynamic> j) => SessionUser(
        id: (j['id'] as num).toInt(),
        username: '${j['username']}',
        displayName: '${j['display_name'] ?? j['username']}',
        role: '${j['role']}',
        vesselId: (j['vessel_id'] as num?)?.toInt(),
        hasPin: j['has_pin'] == true,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'username': username, 'display_name': displayName, 'role': role, 'vessel_id': vesselId, 'has_pin': hasPin};

  bool get canCapture => Roles.entry.contains(role);
  bool get canSign => Roles.approvers.contains(role);
  String get roleLabel => Roles.label(role);
}

class Session {
  final SessionUser user;
  final String token;

  /// Signed in with the check kept on the tablet, because the server couldn't be reached.
  final bool offline;
  final String serverUrl;

  const Session({required this.user, required this.token, required this.offline, required this.serverUrl});
}

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

/// Where secrets live: Android's encrypted storage in the app; memory in tests.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class DeviceSecretStore implements SecretStore {
  static const _s = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

/// Sign-in against the LogBridge server, with the offline sign-in of the design: after one
/// online sign-in, a salted PBKDF2 check of the password is kept on the tablet (never the
/// password), so the same user can sign in with no network.
class AuthService {
  final SecretStore store;
  final Dio Function(String baseUrl) clientFor;

  AuthService({SecretStore? store, Dio Function(String baseUrl)? clientFor})
      : store = store ?? DeviceSecretStore(),
        clientFor = clientFor ?? _defaultClient;

  static const iterations = 60000;
  static const _prefsServer = 'logbridge_server_url';
  static const _kSession = 'session';

  static Dio _defaultClient(String baseUrl) => Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 20),
      ));

  static String normalizeUrl(String url) {
    var u = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (u.isNotEmpty && !u.startsWith(RegExp(r'https?://'))) u = 'http://$u';
    return u;
  }

  static Future<String?> savedServerUrl() async => (await SharedPreferences.getInstance()).getString(_prefsServer);

  static Future<void> saveServerUrl(String url) async =>
      (await SharedPreferences.getInstance()).setString(_prefsServer, normalizeUrl(url));

  static bool _unreachable(DioException e) =>
      e.response == null &&
      const {
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.unknown,
      }.contains(e.type);

  static String _serverMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] != null) return '${data['error']}';
    return 'The server answered ${e.response?.statusCode}';
  }

  String _verifierKey(String username) => 'verifier:${username.toLowerCase()}';
  String _userKey(String username) => 'user:${username.toLowerCase()}';

  Future<Session> signIn(String serverUrl, String username, String password) async {
    final server = normalizeUrl(serverUrl);
    final name = username.trim().toLowerCase();
    if (server.isEmpty) throw const AuthException('Enter the LogBridge server address');
    try {
      final res = await clientFor(server).post('/api/login', data: {'username': name, 'password': password});
      final data = res.data as Map<String, dynamic>;
      final user = SessionUser.fromJson(data['user'] as Map<String, dynamic>);
      final token = '${data['token']}';
      await _remember(user, token, password, server, config: data['config']);
      return Session(user: user, token: token, offline: false, serverUrl: server);
    } on DioException catch (e) {
      if (!_unreachable(e)) throw AuthException(_serverMessage(e));
      // No connection: the design's offline sign-in, for a user who signed in here before.
      final cached = await store.read(_userKey(name));
      if (cached == null || !await checkPassword(name, password)) {
        throw const AuthException(
          'The server cannot be reached, and this user has not signed in on this tablet before '
          '(or the password is wrong). Connect once to sign in.',
        );
      }
      final c = jsonDecode(cached) as Map<String, dynamic>;
      final user = SessionUser.fromJson(c['user'] as Map<String, dynamic>);
      final session = Session(user: user, token: '${c['token']}', offline: true, serverUrl: '${c['server']}');
      await store.write(_kSession, jsonEncode({'username': name}));
      return session;
    }
  }

  Future<void> _remember(SessionUser user, String token, String password, String server, {Object? config}) async {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final hash = await compute(_derive, (password, salt));
    await store.write(_verifierKey(user.username), jsonEncode({'salt': base64Encode(salt), 'n': iterations, 'hash': base64Encode(hash)}));
    await store.write(_userKey(user.username), jsonEncode({'user': user.toJson(), 'token': token, 'server': server, 'config': config}));
    await store.write(_kSession, jsonEncode({'username': user.username}));
  }

  // In a background isolate: tens of thousands of hash rounds must not freeze the screen.
  static List<int> _derive((String, List<int>) a) => pbkdf2Sha256(a.$1, a.$2, iterations);
  static List<int> _deriveN((String, List<int>, int) a) => pbkdf2Sha256(a.$1, a.$2, a.$3);

  /// The password against the check kept on the tablet (unlock, offline sign-in).
  Future<bool> checkPassword(String username, String password) async {
    final raw = await store.read(_verifierKey(username.trim().toLowerCase()));
    if (raw == null) return false;
    final v = jsonDecode(raw) as Map<String, dynamic>;
    final salt = base64Decode('${v['salt']}');
    final n = (v['n'] as num).toInt();
    final hash = await compute(_deriveN, (password, salt, n));
    return sameBytes(hash, base64Decode('${v['hash']}'));
  }

  /// The session that was open when the app was closed (it opens locked).
  Future<Session?> restore() async {
    final raw = await store.read(_kSession);
    if (raw == null) return null;
    final name = '${(jsonDecode(raw) as Map)['username']}';
    final cached = await store.read(_userKey(name));
    if (cached == null) return null;
    final c = jsonDecode(cached) as Map<String, dynamic>;
    return Session(
      user: SessionUser.fromJson(c['user'] as Map<String, dynamic>),
      token: '${c['token']}',
      offline: true,
      serverUrl: '${c['server']}',
    );
  }

  /// The vessel configuration from the last online sign-in (screens, data points, rounds).
  Future<Map<String, dynamic>?> cachedConfig(String username) async {
    final cached = await store.read(_userKey(username.toLowerCase()));
    if (cached == null) return null;
    return (jsonDecode(cached) as Map<String, dynamic>)['config'] as Map<String, dynamic>?;
  }

  /// Sign out: the session ends; the offline check stays, so this user can sign in here again.
  Future<void> signOut() => store.delete(_kSession);

  Future<Session> changePassword(Session s, String current, String next) async {
    try {
      final res = await clientFor(s.serverUrl).put('/api/me/password',
          data: {'current': current, 'new': next}, options: Options(headers: {'authorization': 'Bearer ${s.token}'}));
      final token = '${(res.data as Map)['token']}';
      await _remember(s.user, token, next, s.serverUrl, config: await cachedConfig(s.user.username));
      return Session(user: s.user, token: token, offline: false, serverUrl: s.serverUrl);
    } on DioException catch (e) {
      throw AuthException(_unreachable(e) ? 'Changing the password needs a connection to the server' : _serverMessage(e));
    }
  }

  Future<Session> setPin(Session s, String password, String pin) async {
    try {
      await clientFor(s.serverUrl).put('/api/me/pin',
          data: {'password': password, 'new_pin': pin}, options: Options(headers: {'authorization': 'Bearer ${s.token}'}));
      final user = SessionUser(
        id: s.user.id,
        username: s.user.username,
        displayName: s.user.displayName,
        role: s.user.role,
        vesselId: s.user.vesselId,
        hasPin: true,
      );
      await store.write(_userKey(user.username),
          jsonEncode({'user': user.toJson(), 'token': s.token, 'server': s.serverUrl, 'config': await cachedConfig(user.username)}));
      return Session(user: user, token: s.token, offline: s.offline, serverUrl: s.serverUrl);
    } on DioException catch (e) {
      throw AuthException(_unreachable(e) ? 'Setting the PIN needs a connection to the server' : _serverMessage(e));
    }
  }
}
