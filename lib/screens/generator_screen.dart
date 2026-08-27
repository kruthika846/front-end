import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/daily_log_table.dart';
import '../widgets/log_type_section.dart';
import '../widgets/records_list.dart';
import 'entry_form_screen.dart';

/// One physical generator's logbook — Daily Logs + Records, scoped to just
/// this generator's entries. Generator 1 carries over everything built so
/// far; Generators 2-4 start empty and fill in the same way as entries get
/// logged against them.
class GeneratorScreen extends StatelessWidget {
  final int generatorNumber;
  const GeneratorScreen({super.key, required this.generatorNumber});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Generator $generatorNumber'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Auxiliary Engine Logbook', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70)),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          LogTypeSection(
            storageKey: 'generator_$generatorNumber::daily_logs',
            title: 'Daily Logs',
            icon: Icons.table_chart_outlined,
            accent: AppColors.cyan,
            child: DailyLogTable(generatorNumber: generatorNumber),
          ),
          LogTypeSection(
            storageKey: 'generator_$generatorNumber::records',
            title: 'Records',
            icon: Icons.folder_open_outlined,
            accent: AppColors.teal,
            child: RecordsList(generatorNumber: generatorNumber),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EntryFormScreen(generatorNumber: generatorNumber)),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New Entry'),
      ),
    );
  }
}
