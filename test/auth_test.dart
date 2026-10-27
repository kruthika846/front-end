import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:logbridge/services/auth_service.dart';
import 'package:logbridge/services/pbkdf2.dart';

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('PBKDF2-HMAC-SHA256 matches the published test vectors', () {
    final salt = utf8.encode('salt');
    expect(hex(pbkdf2Sha256('password', salt, 1)), '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
    expect(hex(pbkdf2Sha256('password', salt, 2)), 'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
    expect(hex(pbkdf2Sha256('password', salt, 4096)), 'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a');
  });

  test('the role of each user decides what it may do', () {
    SessionUser u(String role) => SessionUser(id: 1, username: 'x', displayName: 'X', role: role);
    expect(u(Roles.duty).canCapture, isTrue);
    expect(u(Roles.duty).canSign, isFalse);
    expect(u(Roles.chief).canSign, isTrue);
    expect(u(Roles.viewer).canCapture, isFalse);
    expect(u(Roles.admin).canCapture, isFalse);
  });

  // Against a real LogBridge server: LOGBRIDGE_TEST_SERVER=http://127.0.0.1:8091 (demo users seeded).
  final server = Platform.environment['LOGBRIDGE_TEST_SERVER'];
  group('sign-in against the LogBridge server', () {
    test('online, wrong password, then offline with the check kept on the tablet', () async {
      final store = MemorySecretStore();
      final auth = AuthService(store: store);

      final s = await auth.signIn(server!, 'demo.duty', 'LogBridge-demo-1');
      expect(s.offline, isFalse);
      expect(s.user.role, Roles.duty);
      expect(s.token, isNotEmpty);
      expect(store.data.values.any((v) => v.contains('LogBridge-demo-1')), isFalse, reason: 'the password itself is never stored');
      expect(await auth.cachedConfig('demo.duty'), isNotNull);

      await expectLater(auth.signIn(server, 'demo.duty', 'wrong-password'), throwsA(isA<AuthException>()));

      // the server can't be reached
      const nowhere = 'http://127.0.0.1:9';
      final off = await auth.signIn(nowhere, 'demo.duty', 'LogBridge-demo-1');
      expect(off.offline, isTrue);
      expect(off.user.username, 'demo.duty');
      await expectLater(auth.signIn(nowhere, 'demo.duty', 'not-it'), throwsA(isA<AuthException>()));
      await expectLater(auth.signIn(nowhere, 'demo.chief', 'LogBridge-demo-1'), throwsA(isA<AuthException>()),
          reason: 'a user who never signed in here cannot sign in offline');

      expect(await auth.restore(), isNotNull);
      await auth.signOut();
      expect(await auth.restore(), isNull);
    });

    test('a signer sets the signing PIN', () async {
      final auth = AuthService(store: MemorySecretStore());
      final s = await auth.signIn(server!, 'demo.chief', 'LogBridge-demo-1');
      expect(s.user.canSign, isTrue);
      await expectLater(auth.setPin(s, 'wrong-password', '123456'), throwsA(isA<AuthException>()));
      final after = await auth.setPin(s, 'LogBridge-demo-1', '123456');
      expect(after.user.hasPin, isTrue);
    });
  }, skip: server == null ? 'set LOGBRIDGE_TEST_SERVER to run against a LogBridge server' : false);
}
