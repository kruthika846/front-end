import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:signature/signature.dart';
import '../providers/entry_form_provider.dart';

/// Touch-to-draw signature pad. "Save Signature" exports the drawing as a
/// PNG into app storage and stores the file path in EntryFormState —
/// the actual bytes never touch SQLite, only the path does.
class SignaturePadField extends ConsumerStatefulWidget {
  final String entryId;
  final bool showLabel;
  const SignaturePadField({super.key, required this.entryId, this.showLabel = true});

  @override
  ConsumerState<SignaturePadField> createState() => _SignaturePadFieldState();
}

class _SignaturePadFieldState extends ConsumerState<SignaturePadField> {
  late final SignatureController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveSignature() async {
    if (_controller.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign before saving')),
      );
      return;
    }
    final bytes = await _controller.toPngBytes();
    if (bytes == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final signaturesDir = Directory('${dir.path}/signatures');
    if (!await signaturesDir.exists()) {
      await signaturesDir.create(recursive: true);
    }
    final file = File('${signaturesDir.path}/${widget.entryId}.png');
    await file.writeAsBytes(bytes);

    ref.read(entryFormProvider.notifier).setSignaturePath(file.path);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signature saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final signaturePath = ref.watch(entryFormProvider.select((s) => s.signaturePath));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showLabel) ...[
          const Text('Operator Signature', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
        ],
        Container(
          height: 180,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Signature(controller: _controller, backgroundColor: Colors.white),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            TextButton.icon(
              onPressed: () {
                _controller.clear();
                ref.read(entryFormProvider.notifier).setSignaturePath(null);
              },
              icon: const Icon(Icons.clear),
              label: const Text('Clear'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _saveSignature,
              icon: const Icon(Icons.save),
              label: const Text('Save Signature'),
            ),
            if (signaturePath != null) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check_circle, color: Colors.green),
            ],
          ],
        ),
      ],
    );
  }
}
