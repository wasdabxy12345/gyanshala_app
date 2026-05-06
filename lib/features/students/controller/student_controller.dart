import 'dart:developer' as dev;
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';

class StudentController extends StateNotifier<bool> {
  final SupabaseClient _client;

  StudentController(this._client) : super(false);

  Future<List<Map<String, dynamic>>> getGlobalAttendanceReport(DateTime start, DateTime end, {String? schoolFilter}) async {
    try {
      final response = await _client.rpc(
        'get_global_stats',
        params: {
          'p_start_date': start.toIso8601String().split('T')[0],
          'p_end_date': end.toIso8601String().split('T')[0],
          'p_school_filter': schoolFilter ?? 'all',
        },
      );
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      dev.log("Global report fetch failed", error: e);
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getAttendanceRangeReport(DateTime start, DateTime end) async {
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

  Future<bool> registerStudent({
    required String firstName,
    required String lastName,
    required String studentId,
    required String gender,
    required int grade,
  }) async {
    state = true;
    try {
      final user = _client.auth.currentUser;
      if (user == null) return false;

      final mentorData = await _client
          .from('profiles')
          .select('cluster, village, school, cluster_id, village_id, school_id')
          .eq('id', user.id)
          .single();

      await _client.from('students').insert({
        'first_name': firstName,
        'last_name': lastName,
        'student_id_custom': studentId,
        'gender': gender,
        'grade': grade,
        'mentor_id': user.id,
        'cluster': mentorData['cluster'],
        'village': mentorData['village'],
        'school': mentorData['school'],
        'cluster_id': mentorData['cluster_id'],
        'village_id': mentorData['village_id'],
        'school_id': mentorData['school_id'],
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
          .select('*')
          .eq('mentor_id', user?.id ?? '')
          .order('first_name', ascending: true);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      dev.log("Error fetching students", error: e);
      return [];
    }
  }

  Future<bool> submitAttendance(List<Map<String, dynamic>> attendanceData) async {
    state = true;
    try {
      await _client.from('student_attendance').upsert(attendanceData, onConflict: 'student_id, date');

      state = false;
      return true;
    } catch (e, stack) {
      dev.log("Attendance submission failed", error: e, stackTrace: stack);
      state = false;
      return false;
    }
  }

  Future<List<DateTime>> getHolidays() async {
    try {
      final List<dynamic> data = await _client.from('holidays').select('holiday_date');

      return data.map((row) {
        final parsed = DateTime.parse(row['holiday_date'] as String);
        return DateTime(parsed.year, parsed.month, parsed.day);
      }).toList();
    } catch (e, stack) {
      dev.log("Holiday fetch failed", error: e, stackTrace: stack);
      return [];
    }
  }

  Future<void> updateStudentField(String studentId, Map<String, dynamic> updates) async {
    try {
      await _client.from('students').update(updates).eq('id', studentId);
    } catch (e) {
      dev.log("Update failed", error: e);
    }
  }

  Future<List<Map<String, dynamic>>> getClusters() async {
    final data = await _client.from('clusters').select().order('name');
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> getVillages(String? clusterId) async {
    if (clusterId == null) return [];
    final data = await _client.from('villages').select().eq('cluster_id', clusterId).order('name');
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> getSchools(String? villageId) async {
    if (villageId == null) return [];
    final data = await _client.from('schools').select().eq('village_id', villageId).order('name');
    return List<Map<String, dynamic>>.from(data);
  }

  Future<bool> updateStudent(String id, Map<String, dynamic> updates) async {
    try {
      final response = await _client.from('students').update(updates).eq('id', id).select();

      if (response.isEmpty) {
        dev.log("Update successful but 0 rows affected. Check your RLS policy 'using' clause.");
        return false;
      }

      dev.log("Update Success: $response");
      return true;
    } catch (e, stack) {
      dev.log("Update failed in Controller", error: e, stackTrace: stack);
      return false;
    }
  }

  Future<void> importStudentsFromExcel() async {
    // 1. Pick File
    FilePickerResult? result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls']);

    if (result == null) return;

    try {
      final bytes = File(result.files.first.path!).readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);

      // 2. Fetch current Mentor's default location data
      final user = _client.auth.currentUser;
      if (user == null) return;

      final mentorData = await _client
          .from('profiles')
          .select('cluster, village, school, cluster_id, village_id, school_id')
          .eq('id', user.id)
          .single();

      List<Map<String, dynamic>> studentsToInsert = [];

      for (var table in excel.tables.keys) {
        var sheet = excel.tables[table];
        if (sheet == null) continue;

        // Assume row 0 is header: [First Name, Last Name, Gender, Grade, Cluster, Village, School]
        for (int i = 1; i < sheet.maxRows; i++) {
          var row = sheet.rows[i];
          if (row.length < 2) continue; // Skip empty rows

          // Helper to get string value safely
          String? val(int index) =>
              (index < row.length && row[index]?.value != null) ? row[index]!.value.toString().trim() : null;

          // Extract values from Excel
          final fName = val(0);
          final lName = val(1);
          final gender = val(2);
          final gradeStr = val(3);

          // Optional location overrides from Excel
          final excelCluster = val(4);
          final excelVillage = val(5);
          final excelSchool = val(6);

          if (fName == null || fName.isEmpty) continue;

          studentsToInsert.add({
            'first_name': fName,
            'last_name': lName ?? '',
            'gender': gender ?? 'Other',
            'grade': int.tryParse(gradeStr ?? '') ?? 1,
            'mentor_id': user.id,
            // If Excel has location name, use it; otherwise use mentor's name
            'cluster': excelCluster ?? mentorData['cluster'],
            'village': excelVillage ?? mentorData['village'],
            'school': excelSchool ?? mentorData['school'],
            // Note: cluster_id/village_id/school_id are harder to "fallback"
            // because names in Excel might not match DB IDs.
            // We default to the Mentor's assigned IDs.
            'cluster_id': mentorData['cluster_id'],
            'village_id': mentorData['village_id'],
            'school_id': mentorData['school_id'],
          });
        }
      }

      // 3. Bulk Insert into Supabase
      if (studentsToInsert.isNotEmpty) {
        await _client.from('students').insert(studentsToInsert);
      }
    } catch (e) {
      dev.log("Excel Import Error", error: e);
      rethrow;
    }
  }
}

final studentProvider = StateNotifierProvider<StudentController, bool>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return StudentController(client);
});
