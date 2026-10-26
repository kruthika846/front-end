import 'package:flutter/material.dart';
import '../services/ocr_service.dart';
import '../theme/app_colors.dart';

/// Lets the operator set (and test) the OCR server's address without
/// needing a new app build every time it changes — it's a local/LAN dev
/// server, so its address depends on whatever network you're on right
/// now. Defaults to the Android emulator's special host-loopback address;
/// a real tablet on the same Wi-Fi as the PC running the server needs
/// that PC's actual LAN IP instead (shown in the hint text below).
Future<void> showOcrSettingsDialog(BuildContext context) async {
  final controller = TextEditingController(text: await OcrService.getBaseUrl());
  String? statusMessage;
  bool checking = false;

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Future<void> testConnection() async {
          setState(() {
            checking = true;
            statusMessage = null;
          });
          await OcrService.setBaseUrl(controller.text);
          final ok = await OcrService.checkHealth();
          setState(() {
            checking = false;
            statusMessage = ok
                ? 'Connected — DSR Extract is reachable.'
                : 'Could not reach DSR Extract at that address. Photos will be read on this tablet instead.';
          });
        }

        return AlertDialog(
          title: const Text('DSR Extract (OCR) Address'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Where DSR Extract, the HMI screen reader, is running (port 8765). On the emulator, the default already '
                'points back to this PC. On a real tablet, use this PC\'s LAN IP address instead (e.g. http://192.168.1.111:8765) '
                '— both devices need to be on the same Wi-Fi.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Server address', hintText: 'http://10.0.2.2:8765'),
              ),
              if (statusMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  statusMessage!,
                  style: TextStyle(
                    color: statusMessage!.startsWith('Connected') ? AppColors.good : AppColors.alarm,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: checking ? null : testConnection,
              child: checking
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Test'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                await OcrService.setBaseUrl(controller.text);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
}
