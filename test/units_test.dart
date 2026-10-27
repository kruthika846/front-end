import 'package:flutter_test/flutter_test.dart';
import 'package:logbridge/services/units.dart';

void main() {
  test('a gauge reading converts into the parameter\'s unit', () {
    expect(convertUnit(10.89, 'bar', 'MPa'), closeTo(1.089, 1e-9));
    expect(convertUnit(1.089, 'MPa', 'MPa'), 1.089);
    expect(convertUnit(212, 'F', '°C'), closeTo(100, 1e-9));
    expect(convertUnit(40.5, 'C', '°C'), 40.5);
    expect(convertUnit(48, 'A', 'Amps'), 48);
  });

  test('different kinds of quantity are never converted into each other', () {
    expect(convertUnit(60, 'C', 'MPa'), isNull);
    expect(unitKind('MPa'), unitKind('bar'));
    expect(unitKind('°C'), unitKind('C'));
    expect(unitKind('°C') == unitKind('MPa'), isFalse);
  });
}
