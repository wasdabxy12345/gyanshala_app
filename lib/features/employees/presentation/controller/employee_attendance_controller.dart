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

  int _parseTimeToMinutes(String? timeStr) {
    if (timeStr == null) return 0;
    try {
      final parts = timeStr.split(':');
      return (int.parse(parts[0]) * 60) + int.parse(parts[1]);
    } catch (_) {
      return 0;
    }
  }

  String _formatIntervalString(int totalMinutes) {
    final bool isNegative = totalMinutes < 0;
    final int absoluteMinutes = totalMinutes.abs();
    final int hours = absoluteMinutes ~/ 60;
    final int minutes = absoluteMinutes % 60;

    final String hh = hours.toString().padLeft(2, '0');
    final String mm = minutes.toString().padLeft(2, '0');

    return "${isNegative ? '-' : ''}$hh:$mm:00";
  }

  Future<String?> _calculateDeviation(String userId, bool isCheckingIn) async {
    try {
      final profile = await _client.from('profiles').select('role').eq('id', userId).maybeSingle();
      if (profile == null || profile['role'] == null) return null;
      final String userRole = profile['role'].toString();

      String dbRoleKey = userRole;
      if (userRole == 'shikshaMitra38') dbRoleKey = 'Shiksha Mitra (3-8)';
      if (userRole == 'shikshaMitra910') dbRoleKey = 'Shiksha Mitra (9-10)';
      if (userRole == 'mentorBV8') dbRoleKey = 'Mentor (BV-8)';

      final policy = await _client.from('role_work_policies').select().eq('role', dbRoleKey).maybeSingle();
      if (policy == null) {
        dev.log("Warning: Policy record not found for matched key: $dbRoleKey");
        return null;
      }

      final nowLocal = DateTime.now();
      final int actualMinutes = (nowLocal.hour * 60) + nowLocal.minute;

      if (isCheckingIn) {
        final int targetStart = _parseTimeToMinutes(policy['start_time']?.toString());
        final int lateLeeway = (policy['leeway_late_minutes'] as num?)?.toInt() ?? 0;
        final int lateness = actualMinutes - targetStart;
        if (lateness > lateLeeway) {
          return _formatIntervalString(lateness - lateLeeway);
        }
      } else {
        final int targetEnd = _parseTimeToMinutes(policy['end_time']?.toString());
        final int earlyLeeway = (policy['leeway_early_minutes'] as num?)?.toInt() ?? 0;
        final int earlyDeparture = targetEnd - actualMinutes;

        if (earlyDeparture > earlyLeeway) {
          return _formatIntervalString(-(earlyDeparture - earlyLeeway));
        }
      }
      return "00:00:00";
    } catch (e) {
      dev.log("Policy calculation bypass:", error: e);
      return null;
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

      final bool checkingInThisAction = !currentCheckStatus;
      final String? deviationInterval = await _calculateDeviation(userId, checkingInThisAction);

      await _client.from('employee_attendance').insert({
        'user_id': userId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'status': checkingInThisAction ? 'check_in' : 'check_out',
        'school_id': detectedSchoolId,
        'attendance_time_variance': deviationInterval,
      });

      state = AsyncData(checkingInThisAction);
      dev.log("Success: ${checkingInThisAction ? 'Checked In' : 'Checked Out'} at $detectedSchoolId");
    } catch (e, stack) {
      dev.log("Attendance Error", error: e, stackTrace: stack);
      state = AsyncError(e, stack);
      await Future.delayed(const Duration(seconds: 3));
      state = AsyncData(currentCheckStatus);
    }
  }
}
