import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Placeholder for departments that don't have a logbook built yet.
class ComingSoonScreen extends StatelessWidget {
  final String department;
  const ComingSoonScreen({super.key, required this.department});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(department)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.construction_outlined, size: 56, color: AppColors.textFaint),
            const SizedBox(height: 16),
            Text('$department logbook coming soon', style: const TextStyle(color: AppColors.textMuted, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
