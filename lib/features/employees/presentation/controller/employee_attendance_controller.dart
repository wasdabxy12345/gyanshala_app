import 'dart:developer' as dev;

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
  EmployeeAttendanceController(this._client) : super(const AsyncLoading<bool>()) {
    checkCurrentServerStatus();
  }
  Future<void> checkCurrentServerStatus() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      state = const AsyncData(false);
      return;
    }
    try {
      final now = DateTime.now().toUtc();
      final start = DateTime.utc(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1));

      final data = await _client
          .from('employee_attendance')
          .select('status')
          .eq('user_id', userId)
          .gte('recorded_at', start.toIso8601String())
          .lt('recorded_at', end.toIso8601String())
          .order('recorded_at', ascending: false)
          .limit(1);
      if (data.isNotEmpty) {
        final String latestStatus = data.first['status'] as String;
        state = AsyncData(latestStatus == 'check_in');
      } else {
        state = const AsyncData(false);
      }
    } catch (e, stack) {
      dev.log("Failed to fetch initial attendance state", error: e, stackTrace: stack);
      state = const AsyncData(false);
    }
  }

  Future<void> processCheckIn() async {
    if (state.isLoading) return;
    final bool currentCheckStatus = state.value ?? false;
    state = const AsyncLoading<bool>();
    try {
      final Position? position = await LocationService.getCurrentPosition();
      if (position == null) {
        throw Exception("Could not fetch location. Ensure GPS and permissions are enabled.");
      }
      final dynamic response = await _client.rpc(
        'get_school_at_location',
        params: {'lat': position.latitude, 'lon': position.longitude},
      );
      String? detectedSchoolId = response?.toString();
      if (detectedSchoolId == null || detectedSchoolId.trim().isEmpty) {
        detectedSchoolId = null;
      }
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception("User is not authenticated.");
      }
      await _client.from('employee_attendance').insert({
        'user_id': userId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'status': !currentCheckStatus ? 'check_in' : 'check_out',
        'school_id': detectedSchoolId,
      });
      state = AsyncData(!currentCheckStatus);
      dev.log("Success: ${!currentCheckStatus ? 'Checked In' : 'Checked Out'} at $detectedSchoolId");
    } catch (e, stack) {
      dev.log("Attendance Error", error: e, stackTrace: stack);
      state = AsyncError(e, stack);
      await Future.delayed(const Duration(seconds: 3));
      state = AsyncData(currentCheckStatus);
    }
  }
}
