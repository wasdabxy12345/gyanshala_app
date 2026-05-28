import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:collection/collection.dart';
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
          'p_shiksha_mitra_id': _client.auth.currentUser?.id,
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
    required String clusterId,
    required String clusterName,
    required String villageId,
    required String villageName,
    required String schoolId,
    required String schoolName,
  }) async {
    state = true;
    try {
      final user = _client.auth.currentUser;
      if (user == null) return false;

      await _client
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
        'shiksha_mitra_id': user.id,
        'cluster': clusterName,
        'village': villageName,
        'school': schoolName,
        'cluster_id': clusterId,
        'village_id': villageId,
        'school_id': schoolId,
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
          .eq('shiksha_mitra_id', user?.id ?? '')
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
    FilePickerResult? result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls']);
    if (result == null) return;
    try {
      final bytes = File(result.files.first.path!).readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);
      final user = _client.auth.currentUser;
      if (user == null) return;

      final List<dynamic> dbClusters = await _client.from('clusters').select('id, name');
      final List<dynamic> dbVillages = await _client.from('villages').select('id, name');
      final List<dynamic> dbSchools = await _client.from('schools').select('id, name');

      final existingStudents = await _client
          .from('students')
          .select('student_id_custom, first_name, last_name, gender, grade, cluster, village, school')
          .eq('shiksha_mitra_id', user.id);

      List<Map<String, dynamic>> newStudents = [];
      List<Map<String, dynamic>> conflictingStudents = [];
      List<String> errorMessages = [];

      for (var table in excel.tables.keys) {
        var sheet = excel.tables[table];
        if (sheet == null) continue;

        for (int i = 1; i < sheet.maxRows; i++) {
          var row = sheet.rows[i];
          if (row.isEmpty || row.every((cell) => cell == null)) continue;
          String? val(int index) =>
              (index < row.length && row[index]?.value != null) ? row[index]!.value.toString().trim() : null;

          final customId = val(0);
          final fName = val(1);
          final lName = val(2);
          final genderRaw = val(3);
          final gradeRaw = val(4);
          final excelCluster = val(5);
          final excelVillage = val(6);
          final excelSchool = val(7);

          List<String> rowErrors = [];

          if (customId == null || customId.isEmpty) rowErrors.add("ID");
          if (fName == null || fName.isEmpty) rowErrors.add("First Name");
          if (lName == null || lName.isEmpty) rowErrors.add("Last Name");
          int? finalGrade;
          if (gradeRaw == null || gradeRaw.isEmpty) {
            rowErrors.add("Grade");
          } else if (gradeRaw.toUpperCase() == 'BV') {
            finalGrade = 0;
          } else {
            finalGrade = int.tryParse(gradeRaw);
            if (finalGrade == null || finalGrade < 1 || finalGrade > 10) {
              rowErrors.add("Grade (must be BV or 1-10)");
            }
          }
          String? finalGender;
          if (genderRaw == null || genderRaw.isEmpty) {
            rowErrors.add("Gender");
          } else {
            finalGender = genderRaw.substring(0, 1).toUpperCase() + genderRaw.substring(1).toLowerCase();
            if (!['Male', 'Female', 'Other'].contains(finalGender)) {
              rowErrors.add("Gender (must be Male, Female, or Other)");
            }
          }

          String? clusterId, villageId, schoolId;

          if (excelCluster != null && excelCluster.isNotEmpty) {
            final matchC = dbClusters.firstWhereOrNull((c) => c['name'].toString().toLowerCase() == excelCluster.toLowerCase());
            if (matchC != null)
              clusterId = matchC['id'];
            else
              rowErrors.add("Cluster '$excelCluster' not found");
          } else {
            rowErrors.add("Cluster is missing");
          }

          if (excelVillage != null && excelVillage.isNotEmpty) {
            final matchV = dbVillages.firstWhereOrNull((v) => v['name'].toString().toLowerCase() == excelVillage.toLowerCase());
            if (matchV != null)
              villageId = matchV['id'];
            else
              rowErrors.add("Village '$excelVillage' not found");
          } else {
            rowErrors.add("Village is missing");
          }

          if (excelSchool != null && excelSchool.isNotEmpty) {
            final matchS = dbSchools.firstWhereOrNull((s) => s['name'].toString().toLowerCase() == excelSchool.toLowerCase());
            if (matchS != null)
              schoolId = matchS['id'];
            else
              rowErrors.add("School '$excelSchool' not found");
          } else {
            rowErrors.add("School is missing");
          }

          if (rowErrors.isNotEmpty) {
            errorMessages.add("Row ${i + 1}: Missing ${rowErrors.join(', ')}");
            continue;
          }

          final incomingData = {
            'student_id_custom': customId,
            'first_name': fName,
            'last_name': lName,
            'gender': finalGender,
            'grade': finalGrade,
            'shiksha_mitra_id': user.id,
            'cluster': excelCluster,
            'village': excelVillage,
            'school': excelSchool,
            'cluster_id': clusterId,
            'village_id': villageId,
            'school_id': schoolId,
          };

          final existingMatch = existingStudents.firstWhereOrNull((s) => s['student_id_custom'] == customId);
          if (existingMatch == null) {
            newStudents.add(incomingData);
          } else {
            bool isIdentical =
                existingMatch['first_name'] == fName &&
                existingMatch['last_name'] == lName &&
                existingMatch['gender'] == finalGender &&
                existingMatch['grade'] == finalGrade;

            if (!isIdentical) {
              conflictingStudents.add({'current': existingMatch, 'incoming': incomingData});
            }
          }
        }
      }

      if (newStudents.isNotEmpty) {
        await _client.from('students').insert(newStudents);
      }

      String partialSuffix = errorMessages.isNotEmpty ? "&&PARTIAL:${errorMessages.join('\n')}" : "";

      if (conflictingStudents.isNotEmpty) {
        throw Exception(
          "CONFLICT:${newStudents.length}|${conflictingStudents.length}|${jsonEncode(conflictingStudents)}$partialSuffix",
        );
      }

      if (errorMessages.isNotEmpty) {
        throw Exception("PARTIAL:${errorMessages.join('\n')}");
      }
    } catch (e) {
      dev.log("Excel Import Error", error: e);
      rethrow;
    }
  }

  Future<void> processUpsert(List<Map<String, dynamic>> students) async {
    await _client.from('students').upsert(students, onConflict: 'student_id_custom');
  }

  Future<bool> deleteStudents(List<String> ids) async {
    state = true;
    try {
      final response = await _client.from('students').delete().inFilter('id', ids).select();

      if (response.isEmpty) {
        dev.log("Delete called, but no rows were affected. Check RLS or IDs.");
        return false;
      }
      dev.log("Delete Success: $response");
      return true;
    } catch (e, stack) {
      dev.log("Delete failed in Controller", error: e, stackTrace: stack);
      return false;
    } finally {
      state = false;
    }
  }
}

class StudentImportException implements Exception {
  final int newCount;
  final int conflictCount;
  final List<Map<String, dynamic>> conflictData;
  StudentImportException(this.newCount, this.conflictCount, this.conflictData);
}

final studentProvider = StateNotifierProvider<StudentController, bool>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return StudentController(client);
});
