import 'dart:developer' as dev;

import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';

class StudentController extends StateNotifier<bool> {
  final SupabaseClient _client;

  StudentController(this._client) : super(false);

  Future<bool> registerStudent({
    required String name,
    required String studentId,
    required String gender,
    required int grade,
    required String village,
    required String cluster,
    required String school,
  }) async {
    state = true;
    try {
      final user = _client.auth.currentUser;

      await _client.from('students').insert({
        'full_name': name,
        'student_id_custom': studentId,
        'gender': gender,
        'grade': grade,
        'village_name': village,
        'cluster_name': cluster,
        'school_name': school,
        'mentor_id': user?.id,
      });

      state = false;
      return true;
    } catch (e, stack) {
      dev.log("Student registration failed", error: e, stackTrace: stack);
      state = false;
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getMyStudents() async {
    try {
      final user = _client.auth.currentUser;
      final data = await _client
          .from('students')
          .select()
          .eq('mentor_id', user?.id ?? '')
          .order('full_name', ascending: true);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      dev.log("Error fetching students", error: e);
      return [];
    }
  }

  Future<bool> submitAttendance(
    List<Map<String, dynamic>> attendanceData,
  ) async {
    state = true;
    try {
      await _client
          .from('student_attendance')
          .upsert(attendanceData, onConflict: 'student_id, date');

      state = false;
      return true;
    } catch (e, stack) {
      dev.log("Attendance submission failed", error: e, stackTrace: stack);
      state = false;
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getAttendanceRangeReport(
    DateTime start,
    DateTime end,
  ) async {
    try {
      final response = await _client.rpc(
        'get_student_stats',
        params: {
          'p_start_date': start.toIso8601String().split('T')[0],
          'p_end_date': end.toIso8601String().split('T')[0],
          'p_mentor_id': _client.auth.currentUser?.id,
        },
      );
      return List<Map<String, dynamic>>.from(response);
    } catch (e, stack) {
      dev.log("Range report fetch failed", error: e, stackTrace: stack);
      return [];
    }
  }

  Future<List<DateTime>> getHolidays() async {
    try {
      dev.log('Fetching holidays from database...');
      final data = await _client.from('holidays').select('holiday_date');
      dev.log('Raw data returned: $data (type: ${data.runtimeType})');

      if (data.isEmpty) {
        dev.log('Database returned empty list');
        return [];
      }

      final holidays = (data as List).map((row) {
        dev.log('Processing row: $row (type: ${row.runtimeType})');
        final dateStr = row['holiday_date'] as String;
        final parsed = DateTime.parse(dateStr);
        final normalized = DateTime(parsed.year, parsed.month, parsed.day);
        dev.log('Holiday loaded: $dateStr -> $parsed -> $normalized');
        return normalized;
      }).toList();
      dev.log('Total holidays loaded: ${holidays.length}');
      return holidays;
    } catch (e, stack) {
      dev.log("Holiday fetch failed", error: e, stackTrace: stack);
      return [];
    }
  }
}

final studentProvider = StateNotifierProvider<StudentController, bool>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return StudentController(client);
});
