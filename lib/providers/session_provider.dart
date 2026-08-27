import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The signed-in operator's name for this app session. Set once at login,
/// read anywhere a screen wants to show who's currently using the device.
final currentOperatorProvider = StateProvider<String?>((ref) => null);
