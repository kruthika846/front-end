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

  /// The one place that can actually block Submit — every number field on
  /// the form shares this. Only rejects a reading that can't possibly be
  /// real (missing, or not a number at all). A value outside the
  /// configured min/max is deliberately NOT rejected here: an alarm
  /// condition or an out-of-range reading is exactly the kind of thing a
  /// logbook exists to capture, not hide behind a blocked submit button.
  /// See [rangeWarning] for the separate, non-blocking "flag it" signal.
  String? validateValue(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    if (inputType != ParamInputType.number) return null;
    final n = double.tryParse(v);
    if (n == null) return 'Not a number';
    return null;
  }

  /// Purely informational — non-null when a numeric reading falls outside
  /// the configured min/max. Never blocks submission; used only to flag
  /// the reading visually (a red ring, a small note) so it's easy to spot
  /// and explain with a panel comment, since a real onboard reading can
  /// genuinely exceed the "normal" range.
  String? rangeWarning(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    if (inputType != ParamInputType.number) return null;
    final n = double.tryParse(v);
    if (n == null) return null;
    if (min != null && n < min!) return 'Below min $min';
    if (max != null && n > max!) return 'Above max $max';
    return null;
  }
}
