import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

final inactivityLogoutProvider = StateProvider<bool>((ref) => false);

final resetInactivityFlagProvider = Provider<void>((ref) {
  ref.read(inactivityLogoutProvider.notifier).state = false;
});

final inactivityTimeoutProvider = FutureProvider<int>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt('inactivity_timeout_minutes') ?? 15;
});

final setInactivityTimeoutProvider = FutureProvider.family<void, int>((ref, minutes) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('inactivity_timeout_minutes', minutes);
  ref.invalidate(inactivityTimeoutProvider);
});
