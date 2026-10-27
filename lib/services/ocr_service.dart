import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'device_ocr.dart';

/// One labelled value read off an HMI screen photo, as DSR Extract reports
/// it: e.g. label "Gen 3 - LO press.", value "0.40", unit "MPa".
class OcrValue {
  final String label;
  final String value;
  final String? unit;
  final double confidence;

  const OcrValue({required this.label, required this.value, this.unit, this.confidence = 0});

  factory OcrValue.fromJson(Map<String, dynamic> j) => OcrValue(
        label: '${j['label'] ?? ''}',
        value: '${j['value'] ?? ''}',
        unit: j['unit'] as String?,
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
      );
}

/// Everything read from one HMI photo, and where it was read.
class OcrScanResult {
  /// "DSR Extract" (the OCR server), "DSR Extract on this tablet" (no server needed), or
  /// "this tablet" (the simpler ML Kit reader, if DSR Extract failed on the tablet).
  final String source;
  final List<OcrValue> values;

  /// Why the tablet read it itself, when it did.
  final String? fallbackReason;

  const OcrScanResult({required this.source, required this.values, this.fallbackReason});
}

/// Thrown for anything that stops a scan from completing. Always carries a
/// message safe to show the operator directly.
class OcrServiceException implements Exception {
  final String message;
  const OcrServiceException(this.message);
  @override
  String toString() => message;
}

/// Reads an HMI screen photo with DSR Extract — the offline OCR service from
/// LogBridge-DSR (dsr-extract/, POST /extract/pdf) running on the PC or ship
/// server. If it can't be reached, the photo is read on this tablet instead
/// (DeviceOcr.readHmi), so capture still works with no network. The server
/// address is set at runtime (OCR settings) because its LAN IP changes with
/// the network.
class OcrService {
  // A new key: the old OCR scanner (port 8000) is no longer used, and an address saved for it
  // would point at the wrong service.
  static const _prefsKey = 'dsr_extract_base_url';

  /// The Android emulator's address for the PC it runs on. A real tablet needs
  /// the PC's Wi-Fi address instead, e.g. http://192.168.1.111:8765.
  static const defaultBaseUrl = 'http://10.0.2.2:8765';

  static Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKey) ?? defaultBaseUrl;
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = url.trim().replaceAll(RegExp(r'/+$'), '');
    await prefs.setString(_prefsKey, trimmed);
  }

  static Dio _client(String baseUrl, {Duration receiveTimeout = const Duration(seconds: 30)}) => Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: receiveTimeout,
      ));

  /// GET /health — DSR Extract answers {"status": "ok"}.
  static Future<bool> checkHealth() async {
    final baseUrl = await getBaseUrl();
    try {
      final res = await _client(baseUrl).get('/health');
      return res.statusCode == 200 && res.data?['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  static Future<OcrScanResult> scan({required File imageFile}) async {
    final baseUrl = await getBaseUrl();
    // A photo of a screen takes DSR Extract several seconds (more on a slow PC, and the first one
    // after it starts loads its OCR models).
    final dio = _client(baseUrl, receiveTimeout: const Duration(seconds: 120));
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(imageFile.path, filename: imageFile.uri.pathSegments.last),
    });

    Response<dynamic> res;
    try {
      res = await dio.post('/extract/pdf', data: formData, options: Options(sendTimeout: const Duration(seconds: 60)));
    } on DioException catch (e) {
      final unreachable = e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.unknown;
      if (unreachable) return _onTablet(imageFile, 'DSR Extract could not be reached at $baseUrl');
      if (e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.sendTimeout) {
        return _onTablet(imageFile, 'DSR Extract took too long to answer');
      }
      throw OcrServiceException('DSR Extract could not read this photo: ${e.response?.data?['detail'] ?? e.message}');
    }

    try {
      final data = res.data as Map<String, dynamic>;
      if (data['document_type'] == 'error') {
        throw OcrServiceException('DSR Extract could not read this photo: ${data['error'] ?? 'unknown error'}');
      }
      final values = ((data['extracted_values'] as List?) ?? const [])
          .map((e) => OcrValue.fromJson(e as Map<String, dynamic>))
          .toList();
      return OcrScanResult(source: 'DSR Extract', values: values);
    } on OcrServiceException {
      rethrow;
    } catch (e) {
      throw OcrServiceException('DSR Extract answered, but not in the format this app expects. Raw error: $e');
    }
  }

  static Future<OcrScanResult> _onTablet(File imageFile, String reason) async {
    final data = await DeviceOcr.readHmi(imageFile.path);
    if (data['error'] != null) throw OcrServiceException('$reason, and reading on this tablet failed: ${data['error']}');
    final values = ((data['extracted_values'] as List?) ?? const [])
        .map((e) => OcrValue.fromJson(e as Map<String, dynamic>))
        .toList();
    // DSR Extract runs on the tablet too (dsr_device.py); the simpler ML Kit reader only if that failed
    final onTablet = data['source'] == 'dsr-on-device' ? 'DSR Extract on this tablet' : 'this tablet';
    final note = data['dsr_note'];   // why DSR Extract on the tablet was not used
    return OcrScanResult(source: onTablet, values: values, fallbackReason: note == null ? reason : '$reason; $note');
  }
}
