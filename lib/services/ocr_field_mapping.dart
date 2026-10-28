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

// "Mean temp. (CYL 4)" -> cylinder 4. DSR Extract names the column "CYL k" only when it also
// read the little "CYL no." caption beside the row of cylinder numbers; on a photo that misses
// the caption the same column comes out "No.k" - still the cylinder number row, so both count
// (and "Cyl.4", "CYL no. 4"). A bare position ("col 3") or order ("#3") does not.
final _cylinder = RegExp(
  r'^mean\s*(?:exh\.?\s*(?:air|gas)\s*)?temp(?:erature)?\.?\s*\(\s*(?:cyl(?:inder)?\.?\s*(?:no\.?\s*)?|no\.?\s*)(\d{1,2})\s*\)$',
  caseSensitive: false,
);
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
  // degrees as OCR renders them: °C, ºC, ˚C, •C, *C, oC, the ℃ sign; kg/cm² with a superscript
  final k = (u ?? '').toLowerCase().replaceAll('℃', 'c').replaceAll('²', '2').replaceAll(RegExp(r'[\s.°º˚•*]'), '');
  if (k.isEmpty) return null;
  if (k == 'c' || k == 'degc' || k == 'oc') return 'C';
  if (k == 'kgf/cm2' || k == 'kgfcm2') return 'P:kgcm2';
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

  /// Not marked as this generator's on the photo (see confidentReadings): offered unticked.
  final bool uncertain;

  const MappedOcrReading({
    required this.paramKey,
    required this.ocrLabel,
    required this.value,
    required this.unit,
    this.converted = false,
    this.uncertain = false,
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

  // (parsed value, parameter key) for one candidate, or null when it fits no parameter.
  // unsure: the screen gave no unit for a pressure (MPa and bar differ tenfold), or the label
  // is a single letter (W/V/U) with no unit to tell a winding temperature from a voltage.
  ({String key, String value, bool converted, bool unsure})? fit(({int? group, String label, OcrValue v}) p) {
    final cyl = _cylinder.firstMatch(p.label);
    final key = cyl != null ? 'exh_temp_cyl${cyl.group(1)}' : _labelToParamKey[_canon(p.label)];
    if (key == null || !unitOfParam.containsKey(key)) return null;
    var raw = p.v.value.replaceAll('−', '-').trim();
    // "1,250" kW is a thousands comma; elsewhere a comma is the decimal point ("0,40")
    raw = _unitKind(unitOfParam[key]) == 'kW' && RegExp(r'^\d{1,3}(,\d{3})+$').hasMatch(raw)
        ? raw.replaceAll(',', '')
        : raw.replaceAll(',', '.');
    if (double.tryParse(raw) == null) return null;
    final inUnit = _inParamUnit(raw, p.v.unit, unitOfParam[key]!);
    if (inUnit == null) return null;
    final noUnit = _unitKind(p.v.unit) == null;
    final unsure = noUnit && ((_unitKind(unitOfParam[key]) ?? '').startsWith('P:') || _norm(p.label).length == 1);
    return (key: key, value: inUnit.value, converted: inUnit.converted, unsure: unsure);
  }

  // Values of this generator's block that name the same field more than once (e.g. the cylinder
  // row read without its column numbers comes out "Mean temp.", "Mean temp. (#2)", ...): the
  // first is offered, unticked, as the photo doesn't say which one is right.
  final keyCount = <String, int>{};
  for (final p in mine) {
    final f = fit(p);
    if (f != null) keyCount[f.key] = (keyCount[f.key] ?? 0) + 1;
  }
  // The photo names only other generators, and none of their values fits a field (e.g. only a
  // status line carries "Gen 2 -"): its unnamed values may well be that generator's too.
  final otherGeneratorsOnly =
      useGeneratorOfPhoto == null && named.isNotEmpty && !named.any((p) => p.group == generatorNumber) && !named.any((p) => fit(p) != null);

  final out = <MappedOcrReading>[];
  final taken = <String>{};
  for (final p in mine) {
    final f = fit(p);
    if (f == null || taken.contains(f.key)) continue;
    taken.add(f.key);
    out.add(MappedOcrReading(
      paramKey: f.key,
      ocrLabel: p.v.label,
      value: f.value,
      unit: unitOfParam[f.key]!,
      converted: f.converted,
      uncertain: f.unsure || keyCount[f.key]! > 1 || otherGeneratorsOnly,
    ));
  }

  // A value the OCR didn't tag with a generator can still be this generator's (e.g. its
  // alternator box at the screen's edge). It may only fill a field this generator's block left
  // empty, only when it is the single such candidate, and it is offered unticked: it could also
  // be another generator's, half-visible on the photo.
  if (useGeneratorOfPhoto == null && named.any((p) => p.group == generatorNumber)) {
    final byKey = <String, List<(({int? group, String label, OcrValue v}), ({String key, String value, bool converted, bool unsure}))>>{};
    for (final p in parsed.where((p) => p.group == null)) {
      final f = fit(p);
      if (f != null && !taken.contains(f.key)) byKey.putIfAbsent(f.key, () => []).add((p, f));
    }
    for (final e in byKey.entries) {
      if (e.value.length != 1) continue;
      final (p, f) = e.value.single;
      out.add(MappedOcrReading(
        paramKey: f.key,
        ocrLabel: p.v.label,
        value: f.value,
        unit: unitOfParam[f.key]!,
        converted: f.converted,
        uncertain: true,
      ));
    }
  }
  return out;
}

/// The generator numbers the photo names (DSR Extract's "Gen 3 - ..." labels), e.g. {3}.
Set<int> generatorsInPhoto(OcrScanResult result) => {
      for (final v in result.values)
        if (_group.firstMatch(v.label.trim()) case final g?) int.parse(g.group(1)!),
    };
