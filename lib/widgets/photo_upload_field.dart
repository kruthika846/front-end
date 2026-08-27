import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/entry_form_provider.dart';

/// "Upload PDF" button (via file_picker). The whole-entry photo capture now
/// lives as the "Capture HMI Screen" button at the top of Remote Parameters
/// instead of here, so this widget only handles PDFs. Files are copied into
/// app storage so they survive even if the picked file gets cleared.
/// Saturday, the PDF path gets handed to Shreya's upload API instead of
/// just sitting on disk — nothing else about this widget should need to
/// change for that.
class PhotoUploadField extends ConsumerWidget {
  final String entryId;
  final bool showLabel;
  const PhotoUploadField({super.key, required this.entryId, this.showLabel = true});

  Future<String> _copyToAppStorage(String sourcePath, String subDir, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final targetDir = Directory('${dir.path}/$subDir');
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final targetPath = '${targetDir.path}/$fileName';
    await File(sourcePath).copy(targetPath);
    return targetPath;
  }

  Future<void> _pickPdf(WidgetRef ref) async {
    final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf']);
    final path = picked?.path;
    if (path == null) return;
    final savedPath = await _copyToAppStorage(path, 'pdfs', '$entryId.pdf');
    ref.read(entryFormProvider.notifier).setPdfPath(savedPath);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pdfPath = ref.watch(entryFormProvider.select((s) => s.pdfPath));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel) ...[
          const Text('Documents', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
        ],
        OutlinedButton.icon(
          onPressed: () => _pickPdf(ref),
          icon: const Icon(Icons.picture_as_pdf),
          label: Text(pdfPath == null ? 'Upload PDF' : 'PDF attached'),
        ),
      ],
    );
  }
}
