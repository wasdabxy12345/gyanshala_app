import 'dart:developer' as dev;

import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/providers/supabase_provider.dart';

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
    state = true; // Loading state
    try {
      await _client.from('students').insert({
        'full_name': name,
        'student_id_custom': studentId,
        'gender': gender,
        'grade': grade,
        'village_name': village,
        'cluster_name': cluster,
        'school_name': school,
        'mentor_id': _client.auth.currentUser!.id,
      });
      state = false;
      return true;
    } catch (e, stack) {
      dev.log("Student registration failed", error: e, stackTrace: stack);
      state = false;
      return false;
    }
  }
}

final studentProvider = StateNotifierProvider<StudentController, bool>((ref) {
  return StudentController(ref.watch(supabaseClientProvider));
});
