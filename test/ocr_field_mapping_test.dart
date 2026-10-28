import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:logbridge/services/ocr_field_mapping.dart';
import 'package:logbridge/services/ocr_service.dart';

// The remote parameters' units, as the app loads them from engine_parameters.json.
Map<String, String> remoteUnits() {
  final j = jsonDecode(File('assets/config/engine_parameters.json').readAsStringSync()) as Map<String, dynamic>;
  return {for (final p in j['remote'] as List) p['key'] as String: (p['unit'] ?? '') as String};
}

OcrValue v(String label, String value, String? unit) => OcrValue(label: label, value: value, unit: unit, confidence: 0.9);

Map<String, String> asMap(List<MappedOcrReading> r) => {for (final m in r) m.paramKey: m.value};

void main() {
  final units = remoteUnits();

  // As DSR Extract reports a photo of two generators: no.2's lower half at the top (unnamed),
  // no.3 below (named "Gen 3 - ...").
  final twoGenerators = OcrScanResult(source: 'DSR Extract', values: [
    v('LO temp.', '44.7', 'degC'),
    v('Start air press.', '0.78', 'MPa'),
    v('W', '28.5', 'degC'),
    v('Gen 3 - Outlet (#2)', '374.8', 'degC'),
    v('Gen 3 - Inlet', '459.8', 'degC'),
    v('Gen 3 - Generator no.', '442', 'kW'),
    v('Gen 3 - Mean temp.', '406.6', 'degC'),
    v('Gen 3 - Mean temp. (CYL 1)', '403.3', 'degC'),
    v('Gen 3 - Dev. (CYL 1)', '-3.0', 'degC'),
    v('Gen 3 - Mean temp. (CYL 6)', '399.0', 'degC'),
    v('Gen 3 - LO press.', '0.40', 'MPa'),
    v('Gen 3 - LO temp.', '60.6', 'degC'),
    v('Gen 3 - FO press.', '0.80', 'MPa'),
    v('Gen 3 - FO temp.', '134.4', 'degC'),
    v('Gen 3 - CFW out.temp.', '78.8', 'degC'),
    v('Gen 3 - CFW in.press.', '0.37', 'MPa'),
    v('Gen 3 - Start air press.', '0.74', 'MPa'),
    v('Gen 3 - W', '64.3', 'degC'),
    v('Gen 3 - V', '64.4', 'degC'),
    v('Gen 3 - U', '64.7', 'degC'),
    v('Gen 3 - Cooling air temp.', '48.5', 'degC'),
    v('Gen 3 - Bearing temp.', '53.1', 'degC'),
  ]);

  test('generator 3 takes only its own block of the photo', () {
    final got = asMap(confidentReadings(twoGenerators, generatorNumber: 3, unitOfParam: units));
    expect(got, {
      'tc_outlet_temp': '374.8',
      'tc_inlet_temp': '459.8',
      'load_kw': '442',
      'exh_temp_mean': '406.6',
      'exh_temp_cyl1': '403.3',
      'exh_temp_cyl6': '399.0',
      'lo_press': '0.40',
      'lo_temp': '60.6',
      'fo_press': '0.80',
      'fo_temp': '134.4',
      'cfw_out_temp': '78.8',
      'cfw_in_press': '0.37',
      'start_air_press': '0.74',
      'winding_temp_w': '64.3',
      'winding_temp_v': '64.4',
      'winding_temp_u': '64.7',
      'cooling_air_temp': '48.5',
      'bearing_temp': '53.1',
    });
  });

  test('generator 2 takes only the unnamed part, never generator 3\'s values', () {
    final got = asMap(confidentReadings(twoGenerators, generatorNumber: 2, unitOfParam: units));
    expect(got, {'lo_temp': '44.7', 'start_air_press': '0.78', 'winding_temp_w': '28.5'});
  });

  test('a photo that only shows another generator: nothing by default, its values only when chosen', () {
    // As the tablet's own photo of Generator no.3's screen came back: every value named "Gen 3",
    // some labels written out in full by DSR Extract.
    final gen3Only = OcrScanResult(source: 'DSR Extract', values: [
      v('Gen 3 - Generator no.', '442', 'kW'),
      v('Gen 3 - LO press.', '0.40', 'MPa'),
      v('Gen 3 - Fuel Oil Pressure', '0.80', 'MPa'),
      v('Gen 3 - Lube Oil Temperature', '60.6', 'degC'),
      v('Gen 3 - Mean temperature (CYL 2)', '416.8', 'degC'),
    ]);
    expect(generatorsInPhoto(gen3Only), {3});
    expect(confidentReadings(gen3Only, generatorNumber: 2, unitOfParam: units), isEmpty);
    final chosen = confidentReadings(gen3Only, generatorNumber: 2, unitOfParam: units, useGeneratorOfPhoto: 3);
    expect(asMap(chosen), {
      'load_kw': '442',
      'lo_press': '0.40',
      'fo_press': '0.80',
      'lo_temp': '60.6',
      'exh_temp_cyl2': '416.8',
    });
  });

  test('an untagged value fills an empty field only as an unticked suggestion, and only if it is the only one', () {
    final r = confidentReadings(
      OcrScanResult(source: 'DSR Extract', values: [
        v('Gen 3 - LO press.', '0.40', 'MPa'),
        v('Cooling air temp.', '48.5', 'degC'),       // no "Gen 3 -": e.g. the alternator box at the edge
        v('CFW in.press.', '0.37', 'MPa'),
        v('CFW in.press.', '0.18', 'MPa'),            // two candidates: could be either generator's
        v('LO press.', '0.33', 'MPa'),                // generator 3's own LO press. is already there
      ]),
      generatorNumber: 3,
      unitOfParam: units,
    );
    expect(asMap(r), {'lo_press': '0.40', 'cooling_air_temp': '48.5'});
    expect(r.firstWhere((m) => m.paramKey == 'lo_press').uncertain, isFalse);
    expect(r.firstWhere((m) => m.paramKey == 'cooling_air_temp').uncertain, isTrue);
  });

  test('bar is converted to the log\'s MPa; a temperature never fills a pressure', () {
    final r = confidentReadings(
      OcrScanResult(source: 'DSR Extract', values: [v('LO press.', '4.2', 'bar'), v('FO press.', '60.6', 'degC')]),
      generatorNumber: 1,
      unitOfParam: units,
    );
    expect(asMap(r), {'lo_press': '0.42'});
    expect(r.single.converted, isTrue);
  });

  test('cylinder columns count when the photo missed the "CYL no." caption (No.k) or spells it otherwise', () {
    final r = confidentReadings(
      OcrScanResult(source: 'DSR Extract on this tablet', values: [
        v('Gen 3 - Mean temp.', '406.6', 'degC'),
        v('Gen 3 - Mean temp. (No.1)', '403.3', 'degC'), // caption missed: DSR Extract tags "No.k"
        v('Gen 3 - Mean temp. (No.2)', '416.8', 'degC'),
        v('Gen 3 - Mean temp. (No. 3)', '398.1', 'degC'),
        v('Gen 3 - Mean temp. (Cyl.4)', '410.2', 'degC'),
        v('Gen 3 - Mean temperature (CYL no. 5)', '405.0', 'degC'),
        v('Gen 3 - Mean exh.gas temp. (CYL6)', '399.0', 'degC'),
        v('Gen 3 - Dev. (No.1)', '-3.0', 'degC'), // the deviation row is not a cylinder temperature
      ]),
      generatorNumber: 3,
      unitOfParam: units,
    );
    expect(asMap(r), {
      'exh_temp_mean': '406.6',
      'exh_temp_cyl1': '403.3',
      'exh_temp_cyl2': '416.8',
      'exh_temp_cyl3': '398.1',
      'exh_temp_cyl4': '410.2',
      'exh_temp_cyl5': '405.0',
      'exh_temp_cyl6': '399.0',
    });
    expect(r.every((m) => !m.uncertain), isTrue);
  });

  test('a bare position or order is not a cylinder number', () {
    final r = confidentReadings(
      OcrScanResult(source: 'DSR Extract', values: [
        v('Mean temp. (col 3)', '398.1', 'degC'),
        v('Mean temp. (No.0)', '1', 'degC'),
      ]),
      generatorNumber: 1,
      unitOfParam: units,
    );
    expect(r.where((m) => m.paramKey.startsWith('exh_temp_cyl')), isEmpty);
  });

  test('degree spellings OCR produces all count as °C', () {
    final r = confidentReadings(
      OcrScanResult(source: 'this tablet', values: [
        v('LO temp.', '60.6', '℃'),
        v('FO temp.', '134.4', 'ºC'),
        v('CFW out.temp.', '78.8', '•C'),
        v('Bearing temp.', '53.1', '˚C'),
      ]),
      generatorNumber: 1,
      unitOfParam: units,
    );
    expect(asMap(r), {'lo_temp': '60.6', 'fo_temp': '134.4', 'cfw_out_temp': '78.8', 'bearing_temp': '53.1'});
  });

  test('a pressure with no unit, or a lone letter with no unit, is offered unticked', () {
    final r = confidentReadings(
      OcrScanResult(source: 'this tablet', values: [
        v('LO press.', '4.2', null), // bar or MPa? the screen didn't say
        v('V', '440', null), // a winding temperature or a voltage?
        v('LO temp.', '60.6', null), // a temperature field: no doubt
      ]),
      generatorNumber: 1,
      unitOfParam: units,
    );
    final byKey = {for (final m in r) m.paramKey: m};
    expect(byKey['lo_press']!.uncertain, isTrue);
    expect(byKey['winding_temp_v']!.uncertain, isTrue);
    expect(byKey['lo_temp']!.uncertain, isFalse);
  });

  test('a field read twice in the same block is offered unticked, never silently the first', () {
    final r = confidentReadings(
      OcrScanResult(source: 'DSR Extract', values: [
        v('Gen 3 - Mean temp.', '403.3', 'degC'), // the cylinder row without its column numbers...
        v('Gen 3 - Mean temp. (#2)', '416.8', 'degC'),
        v('Gen 3 - LO press.', '0.40', 'MPa'),
      ]),
      generatorNumber: 3,
      unitOfParam: units,
    );
    final byKey = {for (final m in r) m.paramKey: m};
    expect(byKey['exh_temp_mean']!.uncertain, isTrue);
    expect(byKey['lo_press']!.uncertain, isFalse);
  });

  test('a thousands comma in kW is not a decimal point', () {
    final r = confidentReadings(
      OcrScanResult(source: 'DSR Extract', values: [v('Load', '1,250', 'kW'), v('LO press.', '0,40', 'MPa')]),
      generatorNumber: 1,
      unitOfParam: units,
    );
    expect(asMap(r), {'load_kw': '1250', 'lo_press': '0.40'});
  });

  test('a photo tagged only with another generator, none of whose values fit: its unnamed values start unticked', () {
    final r = confidentReadings(
      OcrScanResult(source: 'DSR Extract', values: [
        v('Gen 2 - Ready to start', '1', null),
        v('LO press.', '0.40', 'MPa'),
      ]),
      generatorNumber: 3,
      unitOfParam: units,
    );
    expect(asMap(r), {'lo_press': '0.40'});
    expect(r.single.uncertain, isTrue);
  });

  test('labels that name no field, and non-numbers, are left out', () {
    final r = confidentReadings(
      OcrScanResult(source: 'this tablet', values: [v('Ready to start', '1', null), v('LO temp.', 'abc', 'degC')]),
      generatorNumber: 1,
      unitOfParam: units,
    );
    expect(r, isEmpty);
  });
}
