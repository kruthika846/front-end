import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Asks for the 6-digit signing PIN - separate from the password, personal to the signer.
Future<String?> askSigningPin(BuildContext context, {required String title, required String message}) {
  final pin = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 14),
              TextField(
                controller: pin,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 26, letterSpacing: 10, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(labelText: 'Signing PIN', counterText: ''),
                onChanged: (_) => setState(() {}),
                onSubmitted: (v) => RegExp(r'^\d{6}$').hasMatch(v) ? Navigator.pop(ctx, v) : null,
              ),
              const SizedBox(height: 6),
              const Text('Signed logs are final: nothing in them can change afterwards.',
                  style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: RegExp(r'^\d{6}$').hasMatch(pin.text) ? () => Navigator.pop(ctx, pin.text) : null,
            icon: const Icon(Icons.draw),
            label: const Text('Sign'),
          ),
        ],
      ),
    ),
  );
}
