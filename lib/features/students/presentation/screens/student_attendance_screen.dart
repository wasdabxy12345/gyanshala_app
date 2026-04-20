import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:gyanshala_app/features/students/presentation/controller/student_controller.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  Map<String, bool> attendanceMap = {}; // StudentId -> IsPresent
  List<Map<String, dynamic>> students = [];

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  void _loadStudents() async {
    final data = await ref.read(studentProvider.notifier).getMyStudents();
    setState(() {
      students = data;
      // Initialize everyone as present by default
      for (var s in data) {
        attendanceMap[s['id']] = true;
      }
    });
  }

  void _saveAttendance() async {
    final mentorId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    final today = DateTime.now().toIso8601String().split('T')[0];

    final records = attendanceMap.entries
        .map(
          (e) => {
            'student_id': e.key,
            'mentor_id': mentorId,
            'status': e.value ? 'present' : 'absent',
            'date': today,
          },
        )
        .toList();

    final success = await ref
        .read(studentProvider.notifier)
        .submitAttendance(records);
    if (success && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Attendance Saved!")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Daily Attendance")),
      body: ListView.builder(
        itemCount: students.length,
        itemBuilder: (context, index) {
          final student = students[index];
          final id = student['id'];
          return CheckboxListTile(
            title: Text(student['full_name']),
            subtitle: Text("ID: ${student['student_id_custom']}"),
            value: attendanceMap[id],
            onChanged: (val) => setState(() => attendanceMap[id] = val!),
          );
        },
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          onPressed: _saveAttendance,
          child: const Text("Submit Today's Attendance"),
        ),
      ),
    );
  }
}
