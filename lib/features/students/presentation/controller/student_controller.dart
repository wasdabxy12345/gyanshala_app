import 'dart:developer' as dev;

// Updated from legacy
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/providers/supabase_provider.dart';

class StudentController extends StateNotifier<bool> {
  final SupabaseClient _client;

  StudentController(this._client) : super(false);

  // --- REGISTER STUDENT ---
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

  // --- FETCH STUDENTS (Fixes 'getMyStudents' error) ---
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

  // --- SUBMIT ATTENDANCE (Fixes 'submitAttendance' error) ---
  Future<bool> submitAttendance(
    List<Map<String, dynamic>> attendanceData,
  ) async {
    state = true;
    try {
      // upsert handles both insert and update if a record for that day exists
      await _client.from('student_attendance').upsert(attendanceData);
      state = false;
      return true;
    } catch (e) {
      dev.log("Attendance submission failed", error: e);
      state = false;
      return false;
    }
  }
}

// The provider
final studentProvider = StateNotifierProvider<StudentController, bool>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return StudentController(client);
});
