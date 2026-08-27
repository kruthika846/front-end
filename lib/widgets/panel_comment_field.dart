import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/entry_form_provider.dart';
import '../theme/app_colors.dart';

/// One comment box per parameter group/panel (e.g. "Turbocharger",
/// "Lubrication & Cooling") — not one per individual reading. Saved under
/// groupKey (e.g. "remote::Turbocharger") so remote and local groups with
/// similar names never collide.
class PanelCommentField extends ConsumerStatefulWidget {
  final String groupKey;
  const PanelCommentField({super.key, required this.groupKey});

  @override
  ConsumerState<PanelCommentField> createState() => _PanelCommentFieldState();
}

class _PanelCommentFieldState extends ConsumerState<PanelCommentField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(entryFormProvider).groupComments[widget.groupKey] ?? '';
    _controller = TextEditingController(text: existing);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      minLines: 1,
      maxLines: 3,
      style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.comment_outlined, size: 16, color: AppColors.textFaint),
        hintText: 'Comment for this panel...',
        hintStyle: TextStyle(color: AppColors.textFaint, fontSize: 13),
        isDense: true,
        border: OutlineInputBorder(),
      ),
      onChanged: (v) => ref.read(entryFormProvider.notifier).setGroupComment(widget.groupKey, v),
    );
  }
}
