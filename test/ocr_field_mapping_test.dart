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

  test('bar is converted to the log\'s MPa; a temperature never fills a pressure', () {
    final r = confidentReadings(
      OcrScanResult(source: 'DSR Extract', values: [v('LO press.', '4.2', 'bar'), v('FO press.', '60.6', 'degC')]),
      generatorNumber: 1,
      unitOfParam: units,
    );
    expect(asMap(r), {'lo_press': '0.42'});
    expect(r.single.converted, isTrue);
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
