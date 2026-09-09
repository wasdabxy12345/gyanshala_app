// modified to accomodate special dates

import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gyanshala_app/core/models/user_role.dart';
import 'package:gyanshala_app/core/services/location_service.dart';
import 'package:intl/intl.dart';
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
      } else
        state = const AsyncData(false);
    } catch (e, stack) {
      dev.log("Failed to fetch initial attendance state", error: e, stackTrace: stack);
      state = const AsyncData(false);
    }
  }

  int _parseTimeToMinutes(String? timeStr) {
    if (timeStr == null) return 0;
    try {
      final String timeWithoutOffset = timeStr.split('+')[0].split('-')[0].trim();
      final parts = timeWithoutOffset.split(':');

      final int hours = int.parse(parts[0]);
      final int minutes = int.parse(parts[1]);
      return (hours * 60) + minutes;
    } catch (e) {
      dev.log("Error parsing time string '$timeStr': $e");
      return 0;
    }
  }

  String _formatIntervalString(int totalMinutes) {
    final int absoluteMinutes = totalMinutes.abs();
    final int hours = absoluteMinutes ~/ 60;
    final int minutes = absoluteMinutes % 60;
    final String hh = hours.toString().padLeft(2, '0');
    final String mm = minutes.toString().padLeft(2, '0');
    return "$hh:$mm:00";
  }

  Future<String?> _calculateDeviation(String userId, bool isCheckingIn) async {
    try {
      final profile = await _client.from('profiles').select('role').eq('id', userId).maybeSingle();
      if (profile == null || profile['role'] == null) return "00:00:00";

      final String rawRole = profile['role'].toString();
      final String dbRoleKey = UserRole.fromString(rawRole).label;

      final profileSchool = await _client.from('profile_schools').select('school_id').eq('user_id', userId).maybeSingle();
      final String? assignedSchoolId = profileSchool?['school_id']?.toString();

      var query = _client.from('work_hours').select().eq('role', dbRoleKey);
      query = assignedSchoolId != null
          ? query.or('school_id.eq.$assignedSchoolId,school_id.is.null')
          : query.isFilter('school_id', null);

      final List<dynamic> workHours = await query.order('school_id', ascending: false);
      if (workHours.isEmpty) {
        dev.log("Warning: No work hours found for role: $dbRoleKey");
        return "00:00:00";
      }

      final workHour = workHours.first;
      final nowLocal = DateTime.now();
      final int actualMinutes = (nowLocal.hour * 60) + nowLocal.minute;

      if (isCheckingIn) {
        final int lateLeeway = (workHour['leeway_late_minutes'] as num?)?.toInt() ?? 0;
        final int lateness = actualMinutes - _parseTimeToMinutes(workHour['start_time']?.toString());

        if (lateness > lateLeeway) return _formatIntervalString(lateness - lateLeeway);
      } else {
        final int earlyLeeway = (workHour['leeway_early_minutes'] as num?)?.toInt() ?? 0;
        final int earlyDeparture = _parseTimeToMinutes(workHour['end_time']?.toString()) - actualMinutes;

        if (earlyDeparture > earlyLeeway) return _formatIntervalString(earlyDeparture - earlyLeeway);
      }

      return "00:00:00";
    } catch (e, stack) {
      dev.log("Work hours calculation bypass error:", error: e, stackTrace: stack);
      return "00:00:00";
    }
  }

  Future<void> processCheckIn(BuildContext context) async {
    if (state.isLoading) return;

    final bool currentCheckStatus = state.value ?? false;
    state = const AsyncLoading<bool>();

    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception("User is not authenticated.");

      // 1. Fetch user role
      final profileData = await _client.from('profiles').select('role').eq('id', userId).maybeSingle();
      final String? userRole = profileData?['role']?.toString();

      // 2. Fetch user's assigned schools from profile_schools
      final profileSchoolsData = await _client.from('profile_schools').select('school_id').eq('user_id', userId);
      final List<String> assignedSchoolIds = profileSchoolsData.map((e) => e['school_id'].toString()).toList();

      // 3. Fetch school hierarchy details for location scope validation
      final schoolsInfoData = await _client.from('schools').select('id, village_id, villages(cluster_id)');
      final Map<String, Map<String, dynamic>> schoolDetailsMap = {};
      for (var s in schoolsInfoData) {
        schoolDetailsMap[s['id'].toString()] = s;
      }

      // 4. Fetch active special dates for today
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final List<dynamic> activeSpecialDates = await _client
          .from('special_dates')
          .select('''
        id,
        type,
        roles,
        special_dates_locations(cluster_id, village_id, school_id)
      ''')
          .lte('start_date', todayStr)
          .gte('end_date', todayStr);

      // Helper function to check if a special date applies to a specific school and user role
      bool doesSpecialDateApplyToSchool(Map<String, dynamic> specialDate, String targetSchoolId) {
        final roles = specialDate['roles'] as List<dynamic>?;
        if (roles != null && roles.isNotEmpty) {
          if (userRole == null || !roles.contains(userRole)) {
            return false;
          }
        }

        final locations = specialDate['special_dates_locations'] as List<dynamic>?;
        if (locations == null || locations.isEmpty) {
          return true; // Global scope
        }

        final schoolInfo = schoolDetailsMap[targetSchoolId];
        final villageId = schoolInfo?['village_id']?.toString();
        final clusterId = schoolInfo?['villages']?['cluster_id']?.toString();

        for (var loc in locations) {
          final locClusterId = loc['cluster_id']?.toString();
          final locVillageId = loc['village_id']?.toString();
          final locSchoolId = loc['school_id']?.toString();

          if (locClusterId == null && locVillageId == null && locSchoolId == null) {
            return true; // Global scope row
          }
          if (locSchoolId != null && locSchoolId == targetSchoolId) {
            return true;
          }
          if (locVillageId != null && locVillageId == villageId) {
            return true;
          }
          if (locClusterId != null && locClusterId == clusterId) {
            return true;
          }
        }
        return false;
      }

      // 5. Get current GPS position
      final Position? position = await LocationService.getCurrentPosition();
      if (position == null) {
        throw Exception("Could not fetch location. Ensure GPS and permissions are enabled.");
      }

      // 6. Detect school at location via RPC
      final dynamic response = await _client.rpc(
        'get_school_at_location',
        params: {'lat': position.latitude, 'lon': position.longitude},
      );
      String? detectedSchoolId = response?.toString();

      if (detectedSchoolId != null && detectedSchoolId.trim().isEmpty) detectedSchoolId = null;

      // 7. Evaluate Holiday condition when user is within a school geofence
      if (detectedSchoolId != null) {
        final holidayMatch =
            activeSpecialDates.where((sd) {
                  return sd['type'] == 'holiday' && doesSpecialDateApplyToSchool(sd, detectedSchoolId!);
                }).firstOrNull
                as Map<String, dynamic>?;

        if (holidayMatch != null) {
          if (context.mounted) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text("Holiday Notice"),
                  content: const Text(
                    "Today is a holiday for your role at this location. Attendance cannot be marked.\n"
                    "આજે આ સ્થળે તમારી ભૂમિકા માટે રજા છે. હાજરી નોંધી શકાતી નથી.",
                  ),
                  actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("OK"))],
                );
              },
            );
          }
          state = AsyncData(currentCheckStatus);
          return;
        }
      }

      // 8. Evaluate Atypical Working Day condition if detectedSchoolId is null (outside school premises)
      bool isAllowedAtypicalWork = false;
      if (detectedSchoolId == null) {
        for (var sd in activeSpecialDates) {
          if (sd['type'] == 'atypical_work_day') {
            final roles = sd['roles'] as List<dynamic>?;
            bool roleMatches = roles == null || roles.isEmpty || (userRole != null && roles.contains(userRole));
            if (!roleMatches) continue;

            final locations = sd['special_dates_locations'] as List<dynamic>?;
            if (locations == null || locations.isEmpty) {
              isAllowedAtypicalWork = true;
              break;
            }

            for (var schoolId in assignedSchoolIds) {
              if (doesSpecialDateApplyToSchool(sd, schoolId)) {
                isAllowedAtypicalWork = true;
                break;
              }
            }
            if (isAllowedAtypicalWork) break;
          }
        }

        if (!isAllowedAtypicalWork) {
          if (context.mounted) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text("Attendance Error"),
                  content: const Text(
                    "You are not within the vicinity of any registered school. \n"
                    "તમે કોઈપણ રજિસ્ટર્ડ શાળાની નજીકમાં નથી.",
                  ),
                  actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("OK"))],
                );
              },
            );
          }
          state = AsyncData(currentCheckStatus);
          return;
        }
      }

      // 9. Process Check-in / Check-out
      final bool checkingInThisAction = !currentCheckStatus;
      final String? deviationInterval = await _calculateDeviation(userId, checkingInThisAction);

      await _client.from('employee_attendance').insert({
        'user_id': userId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'status': checkingInThisAction ? 'check_in' : 'check_out',
        'school_id': detectedSchoolId, // Can be null during atypical working days outside school premises
        'attendance_time_variance': deviationInterval,
      });

      state = AsyncData(checkingInThisAction);
    } catch (e, stack) {
      dev.log("Attendance Error", error: e, stackTrace: stack);
      state = AsyncError(e, stack);
      await Future.delayed(const Duration(seconds: 3));
      state = AsyncData(currentCheckStatus);
    }
  }
}
