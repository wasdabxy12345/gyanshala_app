import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/providers/supabase_provider.dart';

final attendanceProvider = StateNotifierProvider<AttendanceController, AsyncValue<bool>>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return AttendanceController(client);
});

class AttendanceController extends StateNotifier<AsyncValue<bool>> {
  final SupabaseClient _client;

  AttendanceController(this._client) : super(const AsyncData(false));

  Future<void> processCheckIn() async {
    // Prevent overlapping calls
    if (state.isLoading) return;

    final bool currentCheckStatus = state.value ?? false;

    state = const AsyncLoading<bool>().copyWithPrevious(AsyncData(currentCheckStatus));

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        state = AsyncData(currentCheckStatus);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.deniedForever) {
          state = AsyncData(currentCheckStatus);
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      final userId = _client.auth.currentUser?.id;
      if (userId != null) {
        await _client.from('attendance').insert({
          'user_id': userId,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'status': !currentCheckStatus ? 'check_in' : 'check_out',
          'recorded_at': DateTime.now().toIso8601String(),
        });
      }

      state = AsyncData(!currentCheckStatus);

      dev.log("Success: ${!currentCheckStatus ? 'Checked In' : 'Checked Out'}");
    } catch (e, stack) {
      dev.log("Attendance Error", error: e, stackTrace: stack);
      state = AsyncError(e, stack);
      await Future.delayed(const Duration(seconds: 2));
      state = AsyncData(currentCheckStatus);
    }
  }
}
