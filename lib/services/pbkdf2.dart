import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// PBKDF2-HMAC-SHA256 (RFC 8018): the salted check kept on the tablet so a user can
/// sign in with no network after one online sign-in. The password itself is never stored.
Uint8List pbkdf2Sha256(String password, List<int> salt, int iterations, {int length = 32}) {
  final hmac = Hmac(sha256, utf8.encode(password));
  final out = BytesBuilder();
  for (var block = 1; out.length < length; block++) {
    final first = Uint8List(salt.length + 4)
      ..setAll(0, salt)
      ..buffer.asByteData().setUint32(salt.length, block);
    var u = hmac.convert(first).bytes;
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.add(t);
  }
  return Uint8List.fromList(out.toBytes().sublist(0, length));
}

/// Constant-time comparison, so a wrong guess doesn't reveal how close it was.
bool sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
