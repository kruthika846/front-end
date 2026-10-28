import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logbridge/models/logbook_entry.dart';
import 'package:logbridge/services/ocr_service.dart';
import 'package:logbridge/widgets/daily_log_table.dart';

LogbookEntry entry(int day, String slot) => LogbookEntry(
      id: 'e$day$slot',
      engineId: 'Aux Engine 1',
      generatorNumber: 1,
      readingSlot: slot,
      timestamp: DateTime(2026, 10, day, slot == 'noon' ? 12 : 8),
      paramValues: const {'load_kw': '442', 'exh_temp_cyl5': '412'},
      logId: 'L-1-40-2026-10-$day-${slot == 'noon' ? 2 : 1}',
      status: 'approved',
      synced: true,
    );

void main() {
  testWidgets('log book on a phone: the parameter names stay in view after the days scroll to the newest', (tester) async {
    tester.view.physicalSize = const Size(380, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DailyLogTable(
              generatorNumber: 1,
              readOnly: true,
              entries: [for (var d = 20; d <= 26; d++) ...[entry(d, 'time'), entry(d, 'noon')]],
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle(); // the days scroll to the newest

    final label = find.text('Power Kw.');
    expect(label, findsOneWidget);
    final box = tester.getRect(label);
    expect(box.left, greaterThanOrEqualTo(0), reason: 'not pushed off the left edge');
    expect(box.right, lessThan(380));
    expect(find.text('No logs on the server for this generator in the last 7 days.'), findsNothing);
  });

  test('an OCR address typed without http:// or with a slash still works', () {
    expect(OcrService.cleanUrl(' 192.168.1.111:8765/ '), 'http://192.168.1.111:8765');
    expect(OcrService.cleanUrl('http://192.168.1.111:8765'), 'http://192.168.1.111:8765');
    expect(OcrService.cleanUrl('https://ocr.ship.local//'), 'https://ocr.ship.local');
  });
}
