import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logbridge/main.dart';
import 'package:logbridge/providers/session_provider.dart';
import 'package:logbridge/services/auth_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

Session sessionAs(String role) => Session(
      user: SessionUser(id: 1, username: 'demo.x', displayName: 'Demo X', role: role),
      token: 't',
      offline: false,
      serverUrl: 'http://127.0.0.1:8080',
    );

// A new key each time: a rebuilt ProviderScope would keep its first overrides.
Widget app({Session? session, bool locked = false}) => ProviderScope(
      key: UniqueKey(),
      overrides: [
        authServiceProvider.overrideWithValue(AuthService(store: MemorySecretStore())),
        if (session != null) sessionProvider.overrideWith((ref) => session),
        if (locked) lockedProvider.overrideWith((ref) => true),
      ],
      child: const LogBridgeApp(),
    );

List<String> tabLabels(WidgetTester tester) =>
    tester.widgetList<NavigationDestination>(find.byType(NavigationDestination)).map((d) => d.label).toList();

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'LogBridge', packageName: 'com.logbridge.logbridge', version: '0.1.0', buildNumber: '1', buildSignature: '');
  });

  testWidgets('signed out: the sign-in screen', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('LogBridge'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
  });

  testWidgets('the tabs follow the role', (tester) async {
    await tester.pumpWidget(app(session: sessionAs(Roles.duty)));
    await tester.pumpAndSettle();
    expect(tabLabels(tester), ['Capture', 'Log book', 'Sync', 'Me']);

    await tester.pumpWidget(app(session: sessionAs(Roles.chief)));
    await tester.pumpAndSettle();
    expect(tabLabels(tester), ['Capture', 'Log book', 'Sync', 'Sign', 'Me']);

    await tester.pumpWidget(app(session: sessionAs(Roles.viewer)));
    await tester.pumpAndSettle();
    expect(tabLabels(tester), ['Log book', 'Dashboard', 'Me']);

    await tester.pumpWidget(app(session: sessionAs(Roles.admin)));
    await tester.pumpAndSettle();
    expect(tabLabels(tester), ['Users', 'Me']);
  });

  testWidgets('locked: the lock screen covers the app', (tester) async {
    await tester.pumpWidget(app(session: sessionAs(Roles.duty), locked: true));
    await tester.pumpAndSettle();
    expect(find.text('Locked'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
  });
}
