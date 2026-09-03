import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One reading the OCR backend found (or didn't) for one schema field.
class OcrFieldResult {
  final String label;
  final String? value;
  final String unit;
  final bool found;

  const OcrFieldResult({required this.label, required this.value, required this.unit, required this.found});

  factory OcrFieldResult.fromJson(String label, Map<String, dynamic> json) {
    return OcrFieldResult(
      label: label,
      value: json['value'] as String?,
      unit: json['unit'] as String? ?? '',
      found: json['found'] as bool? ?? false,
    );
  }
}

/// The full response from POST /scan/{image_type} — one entry per field in
/// that image type's fixed schema, in schema order.
class OcrScanResult {
  final String imageType;
  final int readingCount;
  final int missingCount;
  final List<OcrFieldResult> fields;

  const OcrScanResult({
    required this.imageType,
    required this.readingCount,
    required this.missingCount,
    required this.fields,
  });
}

/// Thrown for anything that stops a scan from completing — network
/// unreachable, schema not set up yet on the server, OCR engine failure,
/// etc. Always carries a message safe to show the operator directly.
class OcrServiceException implements Exception {
  final String message;
  const OcrServiceException(this.message);
  @override
  String toString() => message;
}

/// Talks to the OCR Scanner API (a separate Python/FastAPI service your
/// teammate built — see OCR/api.py) that reads gauge/dashboard panel
/// values out of a photo. This is a real network call to a real service;
/// nothing here is simulated. The server address is configurable at
/// runtime (Settings screen) since it's a local/LAN dev server whose IP
/// changes depending on which network you're on — not something to hard
/// code and rebuild the app for every time.
class OcrService {
  static const _prefsKey = 'ocr_server_base_url';

  /// Sensible default for the Android *emulator* specifically — 10.0.2.2
  /// is the special address the emulator maps back to the host machine's
  /// own localhost. A real tablet on the same Wi-Fi as the PC running the
  /// OCR server needs the PC's actual LAN IP instead (set via Settings).
  static const defaultBaseUrl = 'http://10.0.2.2:8000';

  static Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKey) ?? defaultBaseUrl;
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    // Trim a trailing slash so "http://host:8000/" and "http://host:8000"
    // both work the same when we append a path below.
    final trimmed = url.trim().replaceAll(RegExp(r'/+$'), '');
    await prefs.setString(_prefsKey, trimmed);
  }

  static Dio _client(String baseUrl, {Duration receiveTimeout = const Duration(seconds: 30)}) => Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: receiveTimeout,
      ));

  /// GET /health — used by the Settings screen to confirm the configured
  /// address actually reaches the OCR server before relying on it.
  static Future<bool> checkHealth() async {
    final baseUrl = await getBaseUrl();
    try {
      final res = await _client(baseUrl).get('/health');
      return res.statusCode == 200 && res.data?['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// POST /scan/{imageType} — uploads the photo and returns the readings
  /// the OCR engine found, aligned to that image type's fixed schema.
  /// Throws [OcrServiceException] with a message safe to show directly if
  /// the server is unreachable, the schema doesn't exist yet, or the OCR
  /// engine itself fails on this image.
  static Future<OcrScanResult> scan({required String imageType, required File imageFile}) async {
    final baseUrl = await getBaseUrl();
    // Real OCR (PaddleOCR running on someone's laptop CPU) is genuinely
    // slow compared to a typical API call — especially the first scan
    // after the server starts, which has to load its recognition models
    // into memory before it can even look at the photo. 30s (Dio's
    // default) isn't enough; give it real headroom.
    final dio = _client(baseUrl, receiveTimeout: const Duration(seconds: 120));

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(imageFile.path, filename: imageFile.uri.pathSegments.last),
    });

    Response<dynamic> res;
    try {
      res = await dio.post(
        '/scan/$imageType',
        data: formData,
        options: Options(sendTimeout: const Duration(seconds: 60)),
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.connectionError) {
        throw OcrServiceException(
          'Could not reach the OCR server at $baseUrl. Check it\'s running and the address is correct (Settings).',
        );
      }
      if (e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.sendTimeout) {
        throw const OcrServiceException(
          'The OCR server took too long to respond. It may still be starting up (the first scan after it launches is '
          'always the slowest) — wait a few seconds and try again.',
        );
      }
      if (e.response?.statusCode == 404) {
        throw OcrServiceException(
          'The OCR server has no schema set up for "$imageType" yet — ask whoever runs it to set one up first.',
        );
      }
      throw OcrServiceException('OCR scan failed: ${e.response?.data?['detail'] ?? e.message}');
    }

    // The server sent a normal 200 OK, but its JSON body still has to match
    // the shape this app expects field-for-field. If the server code has
    // changed since this was built against it, a raw cast failure here used
    // to bubble up as an unhandled error the operator never saw anything
    // for. Wrap it so a real mismatch is at least visible and diagnosable.
    try {
      final data = res.data as Map<String, dynamic>;
      final resultMap = data['result'] as Map<String, dynamic>;
      final fields = resultMap.entries
          .map((e) => OcrFieldResult.fromJson(e.key, e.value as Map<String, dynamic>))
          .toList();

      return OcrScanResult(
        imageType: data['image_type'] as String,
        readingCount: data['reading_count'] as int,
        missingCount: data['missing_count'] as int,
        fields: fields,
      );
    } catch (e) {
      throw OcrServiceException(
        'The OCR server responded, but not in the format this app expects (its code may have changed). Raw error: $e',
      );
    }
  }
}
