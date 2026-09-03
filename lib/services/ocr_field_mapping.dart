import 'ocr_service.dart';

/// Maps an exact OCR schema label (from OCR/schemas/engine_dashboard.json,
/// built from the reference "Generator no.1" panel photo) to the matching
/// LogBridge remote-parameter key. Only fields the OCR label text
/// identifies unambiguously are listed here — several panel fields
/// (bearing temp, cooling air temp, U winding temp, all the alarm/status
/// indicators) come through as garbled, merged OCR text in the real
/// schema (e.g. "F.W.INLETVALVE  OFAIL  U") that isn't safe to auto-parse
/// without real risk of writing the wrong value into the wrong field —
/// those stay manual-entry-only, same as before this integration existed.
///
/// If the OCR side re-teaches its schema (POST /schema/engine_dashboard
/// again) and the labels change, this map needs updating to match —
/// it deliberately isn't "smart"/fuzzy, so a mismatch fails safe (nothing
/// gets auto-filled) rather than silently mapping to the wrong field.
const Map<String, String> engineDashboardLabelToParamKey = {
  'Outet': 'tc_outlet_temp',
  'Inlet': 'tc_inlet_temp',
  'Mean exh.air temp': 'exh_temp_cyl1',
  'Mean exh.air temp (#2)': 'exh_temp_cyl2',
  'Mean exh.air temp (#3)': 'exh_temp_cyl3',
  'Mean exh.air temp (#4)': 'exh_temp_cyl4',
  'Mean exh.air temp (#5)': 'exh_temp_cyl5',
  'Mean exh.air temp (#6)': 'exh_temp_cyl6',
  'LO press.': 'lo_press',
  'FO press.': 'fo_press',
  'LO temp.': 'lo_temp',
  'FOtemp.': 'fo_temp',
  'CFW out.temp': 'cfw_out_temp',
  'Start air press.': 'start_air_press',
  'W': 'winding_temp_w',
  'V': 'winding_temp_v',
  'CFWin.press.': 'cfw_in_press',
};

/// One field the scan produced that maps to a known LogBridge parameter —
/// what the review screen actually shows and lets the operator apply.
class MappedOcrReading {
  final String paramKey;
  final String ocrLabel;
  final String value;
  final String unit;

  const MappedOcrReading({required this.paramKey, required this.ocrLabel, required this.value, required this.unit});
}

/// Filters a raw scan down to just the fields we have a confident,
/// explicit mapping for, that OCR actually found a value for, and that
/// parse as a real number (never trust OCR text as numeric without
/// checking — a misread digit here would go straight into a ship's
/// engine log).
List<MappedOcrReading> confidentReadings(OcrScanResult result) {
  final out = <MappedOcrReading>[];
  for (final field in result.fields) {
    final paramKey = engineDashboardLabelToParamKey[field.label];
    if (paramKey == null || !field.found || field.value == null) continue;
    if (double.tryParse(field.value!) == null) continue;
    out.add(MappedOcrReading(paramKey: paramKey, ocrLabel: field.label, value: field.value!, unit: field.unit));
  }
  return out;
}
