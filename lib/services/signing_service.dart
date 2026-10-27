import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'auth_service.dart';

class SigningException implements Exception {
  final String message;
  const SigningException(this.message);
  @override
  String toString() => message;
}

/// A log waiting for a signature, as the server lists it.
class WaitingLog {
  final String id;
  final String date;
  final int round;
  final String screenName;
  final String screenCode;
  final String logType;
  final String? submittedBy;
  final String? submittedAt;

  const WaitingLog({
    required this.id,
    required this.date,
    required this.round,
    required this.screenName,
    required this.screenCode,
    required this.logType,
    this.submittedBy,
    this.submittedAt,
  });

  factory WaitingLog.fromJson(Map j) => WaitingLog(
        id: '${j['id']}',
        date: '${j['log_date']}',
        round: (j['round'] as num).toInt(),
        screenName: '${j['screen_name']}',
        screenCode: '${j['screen_code']}',
        logType: '${j['log_type']}',
        submittedBy: j['submitted_by_name'] as String?,
        submittedAt: j['submitted_at'] as String?,
      );
}

/// Signing (design, sections 6 and 7): it goes through the LogBridge server, so it needs a
/// connection. The server checks the role, the vessel, the log's status, the approver for
/// that log type, that the signer is not the author, and then the PIN - in that order - and
/// a refusal leaves the log unchanged.
class SigningService {
  final Session session;
  final Dio _dio;

  SigningService(this.session, {Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: session.serverUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 30),
              headers: {'authorization': 'Bearer ${session.token}'},
            ));

  Future<T> _call<T>(Future<Response> Function() request, T Function(dynamic data) read) async {
    try {
      return read((await request()).data);
    } on DioException catch (e) {
      if (e.response == null) throw const SigningException('Signing needs a connection to the LogBridge server.');
      final d = e.response!.data;
      throw SigningException(d is Map && d['error'] != null ? '${d['error']}' : 'The server answered ${e.response!.statusCode}');
    }
  }

  /// Logs waiting for a signature that this user signs: the log types whose approver is their role.
  Future<List<WaitingLog>> waiting(Map<String, dynamic>? config) => _call(
        () => _dio.get('/api/logs', queryParameters: {'status': 'submitted'}),
        (d) {
          final types = (config?['log_types'] as Map?) ?? const {};
          return [
            for (final l in (d['logs'] as List))
              if (types[l['log_type']] == null || types[l['log_type']]['approver'] == session.user.role) WaitingLog.fromJson(l as Map),
          ];
        },
      );

  Future<Map<String, dynamic>> detail(String logId) =>
      _call(() => _dio.get('/api/logs/${Uri.encodeComponent(logId)}'), (d) => Map<String, dynamic>.from(d as Map));

  Future<void> approve(String logId, String pin) =>
      _call(() => _dio.post('/api/logs/${Uri.encodeComponent(logId)}/approve', data: {'pin': pin}), (_) {});

  Future<void> sendBack(String logId, String reason) =>
      _call(() => _dio.post('/api/logs/${Uri.encodeComponent(logId)}/reject', data: {'reason': reason}), (_) {});

  Future<Uint8List> photo(String photoId) => _call(
        () => _dio.get('/api/photos/${Uri.encodeComponent(photoId)}', options: Options(responseType: ResponseType.bytes)),
        (d) => Uint8List.fromList(d as List<int>),
      );
}

/// "Time", "Noon", "Round 1", ... from the vessel configuration's log types.
String roundLabel(Map<String, dynamic>? config, String logType, int round) {
  final rounds = (((config?['log_types'] as Map?)?[logType] as Map?)?['rounds'] as List?) ?? const [];
  for (final r in rounds) {
    if ((r['no'] as num).toInt() == round) return '${r['label']}';
  }
  return 'Round $round';
}
