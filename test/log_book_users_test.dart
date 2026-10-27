import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:logbridge/services/auth_service.dart';
import 'package:logbridge/services/log_book_service.dart';
import 'package:logbridge/services/users_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // LOGBRIDGE_TEST_SERVER=http://127.0.0.1:8091 (a freshly seeded server)
  final server = Platform.environment['LOGBRIDGE_TEST_SERVER'];
  const skip = 'set LOGBRIDGE_TEST_SERVER to run against a LogBridge server';

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });

  test('the log book comes from the server; a viewer sees signed logs only', () async {
    final chief = await AuthService(store: MemorySecretStore()).signIn(server!, 'demo.chief', 'LogBridge-demo-1');
    final book = await LogBookService(chief).load();
    expect(book.fromServer, isTrue);
    expect(book.byGenerator.keys, containsAll([1, 2, 3]));
    final all = book.byGenerator.values.expand((e) => e).toList();
    expect(all, isNotEmpty);
    expect(all.every((e) => e.paramValues.isNotEmpty && e.logId!.startsWith('L-')), isTrue);
    expect(all.map((e) => e.readingSlot).toSet(), containsAll(['time', 'noon']));

    final owner = await AuthService(store: MemorySecretStore()).signIn(server, 'demo.owner', 'LogBridge-demo-1');
    final signedOnly = await LogBookService(owner).load();
    final seen = signedOnly.byGenerator.values.expand((e) => e).toList();
    expect(seen, isNotEmpty);
    expect(seen.every((e) => e.status == 'approved'), isTrue);
  }, skip: server == null ? skip : false);

  test('the administrator adds a user, resets the password, deactivates them', () async {
    final admin = await AuthService(store: MemorySecretStore()).signIn(server!, 'demo.admin', 'LogBridge-demo-1');
    final users = UsersService(admin);
    final name = 'test.${DateTime.now().millisecondsSinceEpoch % 100000000}';

    // the server's rules come back as plain messages
    await expectLater(users.add(username: name, displayName: 'T', role: Roles.duty, password: 'short'),
        throwsA(isA<UsersException>().having((e) => e.message, 'message', contains('8 characters'))));

    final added = await users.add(username: name, displayName: 'Test Engineer', role: Roles.chief, password: 'first-pass-1', pin: '246810');
    expect(added.role, Roles.chief);
    expect(added.hasPin, isTrue);
    expect((await users.list()).any((u) => u.username == name), isTrue);

    final auth = AuthService(store: MemorySecretStore());
    expect((await auth.signIn(server, name, 'first-pass-1')).user.role, Roles.chief);

    await users.update(added.id, {'password': 'second-pass-2', 'role': Roles.duty});
    await expectLater(AuthService(store: MemorySecretStore()).signIn(server, name, 'first-pass-1'), throwsA(anything));
    expect((await AuthService(store: MemorySecretStore()).signIn(server, name, 'second-pass-2')).user.role, Roles.duty);

    final off = await users.update(added.id, {'active': false});
    expect(off.active, isFalse);
    await expectLater(AuthService(store: MemorySecretStore()).signIn(server, name, 'second-pass-2'), throwsA(anything));

    // the administrator cannot deactivate themself
    await expectLater(users.update(admin.user.id, {'active': false}), throwsA(isA<UsersException>()));
  }, skip: server == null ? skip : false);
}
