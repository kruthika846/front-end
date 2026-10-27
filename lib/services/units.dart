// The few unit conversions a gauge reading needs to be saved into a parameter logged
// in another unit (a dial in bar, the log in MPa; a thermometer in °F, the log in °C).

const _toMpa = {'mpa': 1.0, 'kpa': 0.001, 'bar': 0.1, 'psi': 0.00689476, 'kg/cm2': 0.0980665, 'kgcm2': 0.0980665};

String _u(String unit) => unit.toLowerCase().replaceAll(RegExp(r'[\s.°•]'), '').replaceAll('²', '2');

/// 'pressure', 'temperature', or the unit itself for anything else ('a', '%', 'cst', ...).
String unitKind(String unit) {
  final u = _u(unit);
  if (_toMpa.containsKey(u)) return 'pressure';
  if (u == 'c' || u == 'degc' || u == 'f' || u == 'k') return 'temperature';
  if (u == 'amps') return 'a';
  return u;
}

/// [value] in [from] expressed in [to], or null when they aren't the same kind of quantity.
double? convertUnit(double value, String from, String to) {
  final f = _u(from), t = _u(to);
  if (f == t || (unitKind(from) == unitKind(to) && unitKind(from) != 'pressure' && unitKind(from) != 'temperature')) {
    return value;
  }
  if (_toMpa.containsKey(f) && _toMpa.containsKey(t)) return value * _toMpa[f]! / _toMpa[t]!;
  double? toC(double v, String u) => switch (u) { 'c' || 'degc' => v, 'f' => (v - 32) * 5 / 9, 'k' => v - 273.15, _ => null };
  final c = toC(value, f);
  if (c == null) return null;
  return switch (t) { 'c' || 'degc' => c, 'f' => c * 9 / 5 + 32, 'k' => c + 273.15, _ => null };
}
