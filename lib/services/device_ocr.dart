import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';

/// Photo readers that run on this tablet itself, inside the app (Python +
/// OpenCV + RapidOCR on onnxruntime, see android/app/src/main/python and
/// MainActivity.kt). No network needed.
///
///  - [readGauge]: gauge-reader (the analog gauge detector) reads a needle
///    gauge photo — value, unit, scale, needle, how sure it is — and draws
///    what it found on a copy of the photo.
///  - [readHmi]: DSR Extract reads an HMI screen photo, used when the DSR
///    Extract server on the PC/ship network can't be reached.
class DeviceOcr {
  static const _channel = MethodChannel('logbridge/ocr');

  // The tablet reads one photo at a time; a reader that hangs must not leave "Scanning…" forever.
  static const _timeout = Duration(minutes: 3);

  static Future<Map<String, dynamic>> _call(String method, Map<String, dynamic> args) async {
    try {
      final json = await _channel.invokeMethod<String>(method, args).timeout(_timeout);
      final data = jsonDecode(json ?? '{}');
      return data is Map<String, dynamic> ? data : {'error': 'The reader on this tablet gave an unexpected answer'};
    } on PlatformException catch (e) {
      return {'error': 'The reader on this tablet failed: ${e.message}'};
    } on MissingPluginException {
      return {'error': 'This build has no on-tablet reader'};
    } on TimeoutException {
      return {'error': 'The reader on this tablet took more than ${_timeout.inMinutes} minutes'};
    } catch (e) {
      return {'error': 'The reader on this tablet gave an answer this app could not read ($e)'};
    }
  }

  static Future<Map<String, dynamic>> readHmi(String path) => _call('readHmi', {'path': path});

  /// [debugPath]: where to write the marked-up picture (needle, dial, numbers read).
  static Future<GaugeReading> readGauge(String path, {String unit = '', String? debugPath}) async {
    return GaugeReading.fromJson(await _call('readGauge', {'path': path, 'unit': unit, 'debug': debugPath ?? ''}));
  }
}

/// What gauge-reader made of one gauge photo.
class GaugeReading {
  final String? error;

  /// The reading in the unit printed on the dial.
  final double? value;
  final String unit;

  /// 'pressure', 'temperature', ... or null when it couldn't tell.
  final String? type;
  final double confidence;
  final String status;
  final List<String> notes;
  final int gaugesFound;

  /// The reading converted to the unit the parameter asked for, when the dial shows another one.
  final double? valueInWantedUnit;
  final String wantedUnit;

  /// Why the reading could not be put in the asked-for unit: the dial's unit was not read, or
  /// the gauge measures something else (a thermometer photographed for a pressure).
  final String? unitNote;

  /// The marked-up copy of the photo, when it was written.
  final String? debugImage;

  /// The lines gauge-reader prints for a reading (label, type, reading, also, scale,
  /// needle, gauge_at, time, status, unit), already formatted.
  final Map<String, String> display;

  const GaugeReading({
    this.error,
    this.value,
    this.unit = '',
    this.type,
    this.confidence = 0,
    this.status = '',
    this.notes = const [],
    this.gaugesFound = 0,
    this.valueInWantedUnit,
    this.wantedUnit = '',
    this.unitNote,
    this.debugImage,
    this.display = const {},
  });

  bool get converted => valueInWantedUnit != null && wantedUnit.isNotEmpty && wantedUnit != unit;

  factory GaugeReading.fromJson(Map<String, dynamic> j) {
    final display = ((j['display'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v'));
    if (j['error'] != null) {
      return GaugeReading(error: j['error'] as String, debugImage: j['debug_image'] as String?);
    }
    return GaugeReading(
      value: double.tryParse('${j['value']}'),
      unit: j['unit'] as String? ?? '',
      type: j['type'] as String?,
      confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
      status: j['status'] as String? ?? '',
      notes: ((j['notes'] as List?) ?? const []).map((e) => '$e').toList(),
      gaugesFound: (j['gauges_found'] as num?)?.toInt() ?? 1,
      valueInWantedUnit: (j['value_in_wanted_unit'] as num?)?.toDouble(),
      wantedUnit: j['wanted_unit'] as String? ?? '',
      unitNote: j['unit_note'] as String?,
      debugImage: j['debug_image'] as String?,
      display: display,
    );
  }
}
