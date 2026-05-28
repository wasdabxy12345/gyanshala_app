import 'dart:developer' as dev; // Imported for logging errors

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gyanshala_app/core/services/location_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/providers/supabase_provider.dart';

final employeeAttendanceProvider = StateNotifierProvider<EmployeeAttendanceController, AsyncValue<bool>>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return EmployeeAttendanceController(client);
});

class EmployeeAttendanceController extends StateNotifier<AsyncValue<bool>> {
  final SupabaseClient _client;

  EmployeeAttendanceController(this._client) : super(const AsyncData(false));

  Future<void> processCheckIn() async {
    if (state.isLoading) return;

    final bool currentCheckStatus = state.value ?? false;
    state = const AsyncLoading<bool>();

    try {
      // Call our unified location utility service layer
      final Position? position = await LocationService.getCurrentPosition();

      if (position == null) {
        // Handle scenario where GPS service or permissions are disabled
        state = AsyncData(currentCheckStatus);
        return;
      }

      final dynamic response = await _client.rpc(
        'get_school_at_location',
        params: {'lat': position.latitude, 'lon': position.longitude},
      );
      String? detectedSchoolId = response?.toString();

      final userId = _client.auth.currentUser?.id;
      if (userId != null) {
        await _client.from('attendance').insert({
          'user_id': userId,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'status': !currentCheckStatus ? 'check_in' : 'check_out',
          'school_id': detectedSchoolId,
          'recorded_at': DateTime.now().toIso8601String(),
        });
      }

      state = AsyncData(!currentCheckStatus);
      dev.log("Success: ${!currentCheckStatus ? 'Checked In' : 'Checked Out'} at $detectedSchoolId");
    } catch (e, stack) {
      // FIXED: Actually utilizing 'e' and 'stack' variables to satisfy the analyzer
      dev.log("Attendance Error", error: e, stackTrace: stack);
      state = AsyncError(e, stack);

      // Briefly pause so the user can see the error, then revert back to previous status
      await Future.delayed(const Duration(seconds: 2));
      state = AsyncData(currentCheckStatus);
    }
  }
}
