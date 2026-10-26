import 'ocr_service.dart';

/// Maps what DSR Extract read off the generator's HMI screen (e.g.
/// "Gen 3 - LO press." = 0.40 MPa) to LogBridge's remote-parameter keys.
///
/// Labels are compared without case, spaces or punctuation ("CFW out.temp."
/// = "CFW out temp"), so small reading differences don't matter, but the
/// label itself must still name the field: anything not listed here stays
/// manual-entry-only. Values are also checked for the right kind of unit
/// (a temperature never fills a pressure) and converted when the screen
/// shows another pressure unit than the log (bar -> MPa).
const Map<String, String> _labelToParamKey = {
  'outlet': 'tc_outlet_temp',
  'outet': 'tc_outlet_temp', // as the panel's own (misspelt) label reads
  'inlet': 'tc_inlet_temp',
  'meantemp': 'exh_temp_mean',
  'meanexhairtemp': 'exh_temp_mean',
  'lopress': 'lo_press',
  'lotemp': 'lo_temp',
  'cfwouttemp': 'cfw_out_temp',
  'cfwoutlettemp': 'cfw_out_temp',
  'cfwinpress': 'cfw_in_press',
  'cfwinletpress': 'cfw_in_press',
  'fopress': 'fo_press',
  'fotemp': 'fo_temp',
  'startairpress': 'start_air_press',
  'w': 'winding_temp_w',
  'v': 'winding_temp_v',
  'u': 'winding_temp_u',
  'coolingairtemp': 'cooling_air_temp',
  'bearingtemp': 'bearing_temp',
  // the kW figure printed beside the "Generator no.3" title is the load
  'generatorno': 'load_kw',
  'load': 'load_kw',
};

// "Mean temp. (CYL 4)" -> cylinder 4
final _cylinder = RegExp(r'^mean\s*(?:exh\.?\s*air\s*)?temp(?:erature)?\.?\s*\(\s*cyl\s*(\d+)\s*\)$', caseSensitive: false);
// DSR Extract names the generator a value belongs to when the photo shows more than one.
final _group = RegExp(r'^(?:gen(?:erator)?|g/?e|d/?g|no\.?)\s*(\d+)\s*[-–:]\s*', caseSensitive: false);
final _repeat = RegExp(r'\s*\(#\d+\)\s*$');

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

// DSR Extract sometimes writes a label out in full ("Fuel Oil Pressure" for the screen's "FO press."):
// both forms are brought to the screen's short one before looking it up.
final _longToShort = [
  (RegExp(r'lub(?:e|ricating)?\.?\s*oil\.?'), 'lo '),
  (RegExp(r'fuel\s*oil\.?'), 'fo '),
  (RegExp(r'cooling\s*fresh\s*water'), 'cfw '),
  (RegExp(r'starting\s*air'), 'start air'),
  (RegExp(r'pressure'), 'press'),
  (RegExp(r'temperature'), 'temp'),
];

String _canon(String label) {
  var t = label.toLowerCase();
  for (final (re, to) in _longToShort) {
    t = t.replaceAll(re, to);
  }
  return _norm(t);
}

String? _unitKind(String? u) {
  final k = (u ?? '').toLowerCase().replaceAll(RegExp(r'[\s.°•]'), '');
  if (k.isEmpty) return null;
  if (k == 'c' || k == 'degc') return 'C';
  if (const {'mpa', 'kpa', 'bar', 'psi', 'kg/cm2', 'kgcm2'}.contains(k)) return 'P:$k';
  if (k == 'kw') return 'kW';
  if (k == 'mw') return 'MW';
  if (k == 'a' || k == 'amps') return 'A';
  if (k == '%') return '%';
  return k;
}

const _toMpa = {'mpa': 1.0, 'kpa': 0.001, 'bar': 0.1, 'psi': 0.00689476, 'kg/cm2': 0.0980665, 'kgcm2': 0.0980665};

/// [value] in the parameter's unit, or null when the units are of different kinds.
({String value, bool converted})? _inParamUnit(String value, String? fromUnit, String paramUnit) {
  final from = _unitKind(fromUnit);
  final to = _unitKind(paramUnit);
  if (from == null || to == null || from == to) return (value: value, converted: false);
  if (from.startsWith('P:') && to.startsWith('P:')) {
    final v = double.parse(value) * _toMpa[from.substring(2)]! / _toMpa[to.substring(2)]!;
    return (value: double.parse(v.toStringAsFixed(3)).toString(), converted: true);
  }
  if (from == 'MW' && to == 'kW') return (value: (double.parse(value) * 1000).toString(), converted: true);
  return null;
}

/// One field the scan produced that maps to a known LogBridge parameter —
/// what the review screen actually shows and lets the operator apply.
class MappedOcrReading {
  final String paramKey;
  final String ocrLabel;
  final String value;
  final String unit;
  final bool converted;

  const MappedOcrReading({
    required this.paramKey,
    required this.ocrLabel,
    required this.value,
    required this.unit,
    this.converted = false,
  });
}

/// The readings for this generator that map to a known parameter, found a
/// value, parse as a real number and have a fitting unit. A photo can show
/// two generators (no.2's lower half above no.3): only [generatorNumber]'s
/// values are used, and if the photo names other generators but not this
/// one, only its unnamed values are tried.
List<MappedOcrReading> confidentReadings(
  OcrScanResult result, {
  required int generatorNumber,
  required Map<String, String> unitOfParam,
  int? useGeneratorOfPhoto,
}) {
  final parsed = <({int? group, String label, OcrValue v})>[];
  for (final v in result.values) {
    var label = v.label.trim();
    int? group;
    final g = _group.firstMatch(label);
    if (g != null) {
      group = int.parse(g.group(1)!);
      label = label.substring(g.end);
    }
    parsed.add((group: group, label: label.replaceAll(_repeat, '').trim(), v: v));
  }
  final named = parsed.where((p) => p.group != null);
  // useGeneratorOfPhoto: the operator chose another generator's block of the photo (generatorsInPhoto).
  final mine = useGeneratorOfPhoto != null
      ? parsed.where((p) => p.group == useGeneratorOfPhoto)
      : named.any((p) => p.group == generatorNumber)
          ? parsed.where((p) => p.group == generatorNumber)
          : named.isEmpty
              ? parsed
              : parsed.where((p) => p.group == null);

  final out = <MappedOcrReading>[];
  final taken = <String>{};
  for (final p in mine) {
    final cyl = _cylinder.firstMatch(p.label);
    final key = cyl != null ? 'exh_temp_cyl${cyl.group(1)}' : _labelToParamKey[_canon(p.label)];
    if (key == null || taken.contains(key) || !unitOfParam.containsKey(key)) continue;
    final raw = p.v.value.replaceAll('−', '-').replaceAll(',', '.').trim();
    if (double.tryParse(raw) == null) continue;
    final inUnit = _inParamUnit(raw, p.v.unit, unitOfParam[key]!);
    if (inUnit == null) continue;
    taken.add(key);
    out.add(MappedOcrReading(
      paramKey: key,
      ocrLabel: p.v.label,
      value: inUnit.value,
      unit: unitOfParam[key]!,
      converted: inUnit.converted,
    ));
  }
  return out;
}

/// The generator numbers the photo names (DSR Extract's "Gen 3 - ..." labels), e.g. {3}.
Set<int> generatorsInPhoto(OcrScanResult result) => {
      for (final v in result.values)
        if (_group.firstMatch(v.label.trim()) case final g?) int.parse(g.group(1)!),
    };
