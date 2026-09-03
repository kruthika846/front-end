import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/param_definition.dart';
import '../providers/entry_form_provider.dart';
import '../theme/app_colors.dart';
import 'edit_value_dialog.dart';

/// Renders one form field from a ParamDefinition. Three shapes:
///  - number/text  -> a pill-shaped gauge chip (label on top, big value below)
///  - select       -> a dropdown (used for local params like pass/fail checks)
///  - status       -> a tap-to-toggle LED indicator, defaults to the first
///                    (normal) option automatically so the operator only has
///                    to touch it when something is actually wrong.
/// This is what makes the form "schema-driven": add a parameter to the JSON
/// config and a field shows up here automatically, no new widget needed.
/// A TextFormField that behaves like a normal field for direct typing, but
/// also picks up value changes that come from outside typing — e.g. the OCR
/// auto-fill flow calling notifier.setValue() for a field the operator never
/// touched by hand. Plain `TextFormField(initialValue: ...)` only applies
/// once, when the field is first built, and silently ignores every later
/// change while it stays mounted — which is exactly why OCR-applied values
/// sometimes never showed up on screen (they were set correctly in state,
/// the visible box just never learned about it).
class _SyncedTextField extends StatefulWidget {
  final String value;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final ValueChanged<String> onChanged;
  final InputDecoration decoration;
  final TextStyle? style;
  final TextAlignVertical? textAlignVertical;

  const _SyncedTextField({
    required this.value,
    required this.keyboardType,
    required this.onChanged,
    required this.decoration,
    this.validator,
    this.style,
    this.textAlignVertical,
  });

  @override
  State<_SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<_SyncedTextField> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _SyncedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only resync from an external change (e.g. OCR apply) — never while
    // the operator is actively typing in this exact field, or we'd fight
    // their cursor and undo their own keystrokes.
    if (widget.value != _controller.text && !_focusNode.hasFocus) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: widget.keyboardType,
      style: widget.style,
      textAlignVertical: widget.textAlignVertical,
      decoration: widget.decoration,
      onChanged: widget.onChanged,
      validator: widget.validator,
    );
  }
}

class DynamicParamField extends ConsumerWidget {
  final ParamDefinition definition;

  /// Compact tiles are used for the remote-parameter instrument panel;
  /// non-compact keeps the original full-width stacked look (local params).
  final bool compact;

  /// Tint for the compact gauge chip — lets each parameter group (cooling,
  /// alternator, ...) read as its own color-coded system at a glance.
  final Color accent;

  const DynamicParamField({
    super.key,
    required this.definition,
    this.compact = false,
    this.accent = AppColors.cyan,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formState = ref.watch(entryFormProvider);
    final notifier = ref.read(entryFormProvider.notifier);
    final currentValue = formState.values[definition.key] ?? '';

    if (definition.inputType == ParamInputType.status) {
      return _LedToggle(definition: definition, currentValue: currentValue, notifier: notifier);
    }

    if (definition.inputType == ParamInputType.select) {
      final labelWithUnit =
          definition.unit.isEmpty ? definition.label : '${definition.label} (${definition.unit})';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: DropdownButtonFormField<String>(
          initialValue: currentValue.isEmpty ? null : currentValue,
          decoration: InputDecoration(labelText: labelWithUnit),
          items: (definition.options ?? [])
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: (v) => notifier.setValue(definition.key, v ?? ''),
          validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
        ),
      );
    }

    final validator = definition.validateValue;

    final keyboardType = definition.inputType == ParamInputType.number
        ? const TextInputType.numberWithOptions(decimal: true, signed: true)
        : TextInputType.text;

    if (!compact) {
      final labelWithUnit =
          definition.unit.isEmpty ? definition.label : '${definition.label} (${definition.unit})';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: _SyncedTextField(
          value: currentValue,
          keyboardType: keyboardType,
          decoration: InputDecoration(labelText: labelWithUnit),
          onChanged: (v) => notifier.setValue(definition.key, v),
          validator: validator,
        ),
      );
    }

    return _GaugeChip(
      definition: definition,
      initialValue: currentValue,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: (v) => notifier.setValue(definition.key, v),
      accent: accent,
    );
  }
}

/// A pill-shaped instrument chip: small caps label, big numeric value, unit
/// suffix, a colored left edge marking which system it belongs to, and an
/// edit button that opens a full-size dialog for typing the value instead
/// of the cramped inline field.
class _GaugeChip extends ConsumerWidget {
  final ParamDefinition definition;
  final String initialValue;
  final TextInputType keyboardType;
  final String? Function(String?) validator;
  final ValueChanged<String> onChanged;
  final Color accent;

  const _GaugeChip({
    required this.definition,
    required this.initialValue,
    required this.keyboardType,
    required this.validator,
    required this.onChanged,
    required this.accent,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Non-blocking — a value outside min/max is a real reading a logbook
    // needs to capture (e.g. an alarm condition), not something to reject.
    // This only flags it visually so it's easy to spot and explain with a
    // panel comment; Submit is never blocked by it.
    final rangeWarning = definition.rangeWarning(initialValue);
    final barColor = rangeWarning != null ? AppColors.alarm : accent;

    return SizedBox(
      width: 152,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 10, 6, 6),
        decoration: BoxDecoration(
          color: AppColors.ink800,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: barColor.withValues(alpha: 0.28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 34,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(4)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        definition.label.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              letterSpacing: 0.3,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                              fontSize: 9.5,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: _SyncedTextField(
                              value: initialValue,
                              keyboardType: keyboardType,
                              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
                              textAlignVertical: TextAlignVertical.center,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                errorStyle: TextStyle(fontSize: 9, height: 0.9, color: AppColors.alarm),
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: onChanged,
                              validator: validator,
                            ),
                          ),
                          if (definition.unit.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(definition.unit, style: const TextStyle(color: AppColors.textFaint, fontSize: 11)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 14),
                  color: accent,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => showEditValueDialog(context, ref, definition),
                ),
              ],
            ),
            if (rangeWarning != null)
              Padding(
                padding: const EdgeInsets.only(left: 14, right: 4, top: 3),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    rangeWarning,
                    style: const TextStyle(fontSize: 9, color: AppColors.alarm, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A tap-to-toggle status light — a glowing dot plus label, styled after the
/// "○ Alarm name" indicators on a real engine control panel. Tapping cycles
/// between the two options; auto-fills the "normal" option on first render
/// so the operator only has to touch it to flag something actually wrong.
class _LedToggle extends StatefulWidget {
  final ParamDefinition definition;
  final String currentValue;
  final EntryFormNotifier notifier;

  const _LedToggle({required this.definition, required this.currentValue, required this.notifier});

  @override
  State<_LedToggle> createState() => _LedToggleState();
}

class _LedToggleState extends State<_LedToggle> {
  @override
  void initState() {
    super.initState();
    if (widget.currentValue.isEmpty && (widget.definition.options?.isNotEmpty ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.notifier.setValue(widget.definition.key, widget.definition.options!.first);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.definition.options ?? const ['OK', 'ALARM'];
    final selected = widget.currentValue.isEmpty ? options.first : widget.currentValue;
    final isAbnormal = selected != options.first;
    final color = isAbnormal ? AppColors.alarm : AppColors.good;

    return GestureDetector(
      onTap: () {
        final next = isAbnormal ? options.first : options.last;
        widget.notifier.setValue(widget.definition.key, next);
      },
      child: Container(
        width: 176,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.ink800,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: isAbnormal ? 0.55 : 0.22)),
        ),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 8)],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.definition.label,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    selected,
                    style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
