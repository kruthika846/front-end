import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logbridge/main.dart';

void main() {
  testWidgets('Login screen shows the app title and Sign In button', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: LogBridgeApp()));
    await tester.pumpAndSettle();

    expect(find.text('LogBridge'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });
}
