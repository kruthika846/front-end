import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/param_definition.dart';

class ParameterConfig {
  final List<ParamDefinition> remoteParams;
  final List<ParamDefinition> localParams;

  ParameterConfig({required this.remoteParams, required this.localParams});

  static Future<ParameterConfig> load() async {
    final raw = await rootBundle.loadString('assets/config/engine_parameters.json');
    final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;

    final remote = (json['remote'] as List)
        .map((e) => ParamDefinition.fromJson(e as Map<String, dynamic>, ParamCategory.remote))
        .toList();
    final local = (json['local'] as List)
        .map((e) => ParamDefinition.fromJson(e as Map<String, dynamic>, ParamCategory.local))
        .toList();

    return ParameterConfig(remoteParams: remote, localParams: local);
  }
}
