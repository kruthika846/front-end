import 'package:local_auth/local_auth.dart';

/// Thin wrapper around the device's real fingerprint/face hardware via
/// `local_auth` — this is a genuine OS-level BiometricPrompt (Android) /
/// Face ID/Touch ID (iOS) check, not a simulated pass/fail. Used to gate
/// entry submission and record deletion, in place of a drawn signature.
class BiometricAuth {
  static final _auth = LocalAuthentication();

  /// Returns why biometric auth can't be used right now, or null if it's
  /// available. Checked before showing any biometric UI so a device with no
  /// fingerprint/face hardware (or nothing enrolled) gets an honest message
  /// instead of a check that can never succeed.
  static Future<String?> unavailableReason() async {
    final supported = await _auth.isDeviceSupported();
    if (!supported) return 'This device does not support biometric authentication.';

    final canCheck = await _auth.canCheckBiometrics;
    if (!canCheck) return 'Biometric hardware is not available on this device.';

    final enrolled = await _auth.getAvailableBiometrics();
    if (enrolled.isEmpty) {
      return 'No fingerprint or face is enrolled on this device. Add one in system settings first.';
    }
    return null;
  }

  /// Prompts the real OS biometric dialog. Returns true only on an actual
  /// successful fingerprint/face match — cancelling, failing, or the
  /// hardware being unavailable all return false.
  static Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
