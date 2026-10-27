import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logbridge/widgets/synced_text_field.dart';

// An HMI scan (or a gauge reading, or the edit dialog) sets a value while the box is already on
// screen: it has to show the new value, which a plain TextFormField(initialValue:) never did.
void main() {
  testWidgets('a value set from outside shows up in the box', (tester) async {
    final value = ValueNotifier('');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<String>(
          valueListenable: value,
          builder: (_, v, __) => SyncedTextField(value: v, onChanged: (_) {}),
        ),
      ),
    ));
    expect(find.text('442'), findsNothing);

    value.value = '442'; // e.g. "Apply Selected" after an HMI scan
    await tester.pump();
    expect(find.text('442'), findsOneWidget);
  });

  testWidgets('typing is not overwritten while the box has focus', (tester) async {
    final value = ValueNotifier('1');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<String>(
          valueListenable: value,
          builder: (_, v, __) => SyncedTextField(value: v, onChanged: (_) {}),
        ),
      ),
    ));
    await tester.enterText(find.byType(TextFormField), '12');
    value.value = '99';
    await tester.pump();
    expect(find.text('12'), findsOneWidget);
  });
}
