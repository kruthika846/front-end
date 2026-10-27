import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/daily_log_table.dart';

/// The Log book tab: each generator's daily log sheet, day columns with the Time and Noon
/// readings, like the paper log. (From Phase 2 it also holds the logs synced with the server;
/// dashboard viewers will see signed values only.)
class LogBookScreen extends StatelessWidget {
  const LogBookScreen({super.key});

  static const generators = [1, 2, 3];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log book')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          for (final g in generators) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4),
              child: Text('GENERATOR $g',
                  style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w800, letterSpacing: 0.8, fontSize: 13)),
            ),
            DailyLogTable(generatorNumber: g),
            const SizedBox(height: 22),
          ],
        ],
      ),
    );
  }
}
