import 'package:flutter/material.dart';

/// A TextFormField that behaves like a normal field for direct typing, but
/// also picks up value changes that come from outside typing — e.g. the OCR
/// auto-fill flow, a gauge reading, or the edit dialog calling
/// notifier.setValue() for a field the operator never touched by hand. Plain
/// `TextFormField(initialValue: ...)` only applies once, when the field is
/// first built, and silently ignores every later change while it stays
/// mounted — which is exactly why OCR-applied values sometimes never showed
/// up on screen (they were set correctly in state, the visible box just
/// never learned about it).
class SyncedTextField extends StatefulWidget {
  final String value;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final ValueChanged<String> onChanged;
  final InputDecoration decoration;
  final TextStyle? style;
  final TextAlign textAlign;
  final TextAlignVertical? textAlignVertical;

  const SyncedTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.keyboardType = TextInputType.text,
    this.decoration = const InputDecoration(),
    this.validator,
    this.style,
    this.textAlign = TextAlign.start,
    this.textAlignVertical,
  });

  @override
  State<SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<SyncedTextField> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant SyncedTextField oldWidget) {
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
      textAlign: widget.textAlign,
      textAlignVertical: widget.textAlignVertical,
      decoration: widget.decoration,
      onChanged: widget.onChanged,
      validator: widget.validator,
    );
  }
}
