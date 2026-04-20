import 'dart:developer' as dev;

import 'package:flutter_riverpod/legacy.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/providers/supabase_provider.dart';

class AttendanceController extends StateNotifier<bool> {
  final SupabaseClient _client;
  bool _isLoading = false; // Add a private loading flag

  AttendanceController(this._client) : super(false);

  Future<void> processCheckIn() async {
    if (_isLoading) return; // Prevent double-taps
    _isLoading = true;

    try {
      // 1. Service/Permission Check
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.deniedForever) {
          // Permissions are denied forever, handle appropriately.
          return;
        }
      }

      // 2. Get Current Location
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter:
            10, // Minimum distance (in meters) before an update is fired
      );

      // Use the 'locationSettings' parameter instead of 'desiredAccuracy'
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

      // 3. Simple Toggle (For testing UI stability)
      state = !state;

      dev.log(
        "Check-in success at: ${position.latitude}, ${position.longitude}",
      );
    } catch (e, stack) {
      dev.log("Attendance Error", error: e, stackTrace: stack);
    } finally {
      _isLoading = false; // Always reset loading
    }
  }
}

final attendanceProvider = StateNotifierProvider<AttendanceController, bool>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  return AttendanceController(client);
});
