import 'dart:developer' as dev; // Use this for professional logging

import 'package:flutter_riverpod/legacy.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/providers/supabase_provider.dart';

class AttendanceController extends StateNotifier<bool> {
  final SupabaseClient _client;

  AttendanceController(this._client) : super(false);

  Future<void> processCheckIn() async {
    try {
      // 1. Handle Permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.deniedForever) return;
      }

      // 2. Get Location (Using the standard getCurrentPosition)
      Position position = await Geolocator.getCurrentPosition(
        // ignore: deprecated_member_use
        desiredAccuracy: LocationAccuracy.high,
      );

      // 3. Save to Supabase
      await _client.from('attendance_logs').insert({
        'user_id': _client.auth.currentUser!.id,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'check_in': DateTime.now().toIso8601String(),
      });

      state = true;
    } catch (e, stackTrace) {
      // Professional logging instead of print
      dev.log("Check-in failed", error: e, stackTrace: stackTrace);
    }
  }
}

final attendanceProvider = StateNotifierProvider<AttendanceController, bool>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  return AttendanceController(client);
});
