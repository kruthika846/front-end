import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// The signed-in user's session (null when signed out).
final sessionProvider = StateProvider<Session?>((ref) => null);

/// The app is locked: after 10 idle minutes, and when it is reopened (design, section 3).
final lockedProvider = StateProvider<bool>((ref) => false);

/// The signed-in operator's name for this app session. Set at sign-in, read anywhere a
/// screen wants to show who's currently using the device.
final currentOperatorProvider = StateProvider<String?>((ref) => null);
