enum ParamCategory { remote, local }

enum ParamInputType { number, text, select, status }

/// Describes one field on the entry form. The full list of fields lives in
/// assets/config/engine_parameters.json — editing that file changes the
/// form without touching any Dart code (schema-driven UI).
class ParamDefinition {
  final String key;
  final String label;
  final String unit;
  final ParamCategory category;
  final ParamInputType inputType;
  final double? min;
  final double? max;
  final List<String>? options;

  /// Groups related fields under one sub-heading on the form (e.g. all
  /// cylinder exhaust temperatures together). Optional — ungrouped fields
  /// just render under the section with no sub-heading.
  final String? group;

  const ParamDefinition({
    required this.key,
    required this.label,
    required this.unit,
    required this.category,
    required this.inputType,
    this.min,
    this.max,
    this.options,
    this.group,
  });

  factory ParamDefinition.fromJson(Map<String, dynamic> json, ParamCategory category) {
    return ParamDefinition(
      key: json['key'] as String,
      label: json['label'] as String,
      unit: json['unit'] as String? ?? '',
      category: category,
      inputType: _inputTypeFromString(json['inputType'] as String? ?? 'number'),
      min: (json['min'] as num?)?.toDouble(),
      max: (json['max'] as num?)?.toDouble(),
      options: (json['options'] as List?)?.cast<String>(),
      group: json['group'] as String?,
    );
  }

  static ParamInputType _inputTypeFromString(String s) {
    switch (s) {
      case 'text':
        return ParamInputType.text;
      case 'select':
        return ParamInputType.select;
      case 'status':
        return ParamInputType.status;
      default:
        return ParamInputType.number;
    }
  }

  /// The one place numeric validation happens — every number field on the
  /// form (remote gauge chips, local gauge dials, the load readout) shares
  /// this so "reject a bad reading" behaves identically everywhere instead
  /// of drifting per-widget. Returns null when the value is acceptable, or
  /// a short message to show the operator when it isn't.
  String? validateValue(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    if (inputType != ParamInputType.number) return null;
    final n = double.tryParse(v);
    if (n == null) return 'Not a number';
    if (min != null && n < min!) return 'Min $min';
    if (max != null && n > max!) return 'Max $max';
    return null;
  }
}
