import 'dart:convert';
import 'package:flutter/services.dart';

/// Photo readers that run on this tablet itself, inside the app (Python +
/// OpenCV + ML Kit text recognition, see android/app/src/main/python and
/// MainActivity.kt). No network needed.
///
///  - [readGauge]: gauge-reader (the analog gauge detector) reads a needle
///    gauge photo — value, unit, how sure it is.
///  - [readHmi]: a simpler HMI screen reader, used only when DSR Extract
///    (the OCR server on the PC/ship network) can't be reached.
class DeviceOcr {
  static const _channel = MethodChannel('logbridge/ocr');

  static Future<Map<String, dynamic>> _call(String method, Map<String, dynamic> args) async {
    try {
      final json = await _channel.invokeMethod<String>(method, args);
      return jsonDecode(json ?? '{}') as Map<String, dynamic>;
    } on PlatformException catch (e) {
      return {'error': 'The reader on this tablet failed: ${e.message}'};
    } on MissingPluginException {
      return {'error': 'This build has no on-tablet reader'};
    }
  }

  static Future<Map<String, dynamic>> readHmi(String path) => _call('readHmi', {'path': path});

  static Future<GaugeReading> readGauge(String path, String unit) async {
    return GaugeReading.fromJson(await _call('readGauge', {'path': path, 'unit': unit}));
  }
}

/// What gauge-reader made of one gauge photo. [value] is already in the
/// parameter's own unit when the dial shows another one (e.g. bar -> MPa).
class GaugeReading {
  final String? error;
  final double? value;
  final String unit;
  final String dialValue;
  final String dialUnit;
  final double confidence;
  final String status;
  final List<String> notes;
  final int gaugesFound;

  const GaugeReading({
    this.error,
    this.value,
    this.unit = '',
    this.dialValue = '',
    this.dialUnit = '',
    this.confidence = 0,
    this.status = '',
    this.notes = const [],
    this.gaugesFound = 0,
  });

  bool get converted => dialUnit.isNotEmpty && unit.isNotEmpty && dialUnit != unit;

  factory GaugeReading.fromJson(Map<String, dynamic> j) {
    if (j['error'] != null) return GaugeReading(error: j['error'] as String);
    final dial = double.tryParse('${j['value']}');
    final inWanted = j['value_in_wanted_unit'] as num?;
    return GaugeReading(
      value: inWanted?.toDouble() ?? dial,
      unit: (j['wanted_unit'] as String?) ?? (j['unit'] as String? ?? ''),
      dialValue: '${j['value'] ?? ''}',
      dialUnit: j['unit'] as String? ?? '',
      confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
      status: j['status'] as String? ?? '',
      notes: ((j['notes'] as List?) ?? const []).map((e) => '$e').toList(),
      gaugesFound: (j['gauges_found'] as num?)?.toInt() ?? 1,
    );
  }
}
