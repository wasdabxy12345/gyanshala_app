import 'dart:developer' as dev;

import 'package:flutter_riverpod/legacy.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/providers/supabase_provider.dart';

class AttendanceController extends StateNotifier<bool> {
  final SupabaseClient _client;
  bool _isLoading = false;

  AttendanceController(this._client) : super(false);

  Future<void> processCheckIn() async {
    if (_isLoading) return;
    _isLoading = true;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.deniedForever) {
          return;
        }
      }

      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      );

      final userId = _client.auth.currentUser?.id;

      if (userId != null) {
        await _client.from('attendance').insert({
          'user_id': userId,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'status': !state ? 'check_in' : 'check_out',
          'recorded_at': DateTime.now().toIso8601String(),
        });
      }

      state = !state;

      dev.log(
        "Check-in success at: ${position.latitude}, ${position.longitude}",
      );
    } catch (e, stack) {
      dev.log("Attendance Error", error: e, stackTrace: stack);
    } finally {
      _isLoading = false;
    }
  }
}

final attendanceProvider = StateNotifierProvider<AttendanceController, bool>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  return AttendanceController(client);
});
