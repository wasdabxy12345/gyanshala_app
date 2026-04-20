import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/features/students/presentation/controller/student_controller.dart';

class DailyAttendanceTab extends StatefulWidget {
  final String searchQuery;
  final DateTime date;
  const DailyAttendanceTab({
    super.key,
    required this.searchQuery,
    required this.date,
  });

  @override
  State<DailyAttendanceTab> createState() => _DailyAttendanceTabState();
}

class _DailyAttendanceTabState extends State<DailyAttendanceTab> {
  // Key: StudentID, Value: 'P', 'A', or null
  Map<String, String?> attendanceStatus = {};

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        return FutureBuilder(
          future: ref.read(studentProvider.notifier).getMyStudents(),
          builder: (context, snapshot) {
            if (!snapshot.hasData)
              return const Center(child: CircularProgressIndicator());

            final filteredStudents = snapshot.data!
                .where(
                  (s) => s['full_name'].toString().toLowerCase().contains(
                    widget.searchQuery.toLowerCase(),
                  ),
                )
                .toList();

            return Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: filteredStudents.length,
                    itemBuilder: (context, index) {
                      final student = filteredStudents[index];
                      final id = student['id'];
                      final status = attendanceStatus[id];

                      return ListTile(
                        title: Text(student['full_name']),
                        trailing: GestureDetector(
                          onTap: () {
                            setState(() {
                              if (status == null)
                                attendanceStatus[id] = 'P';
                              else if (status == 'P')
                                attendanceStatus[id] = 'A';
                              else
                                attendanceStatus[id] = null;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 45,
                            height: 45,
                            decoration: BoxDecoration(
                              color: status == 'P'
                                  ? Colors.green
                                  : (status == 'A'
                                        ? Colors.red
                                        : Colors.grey[200]),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                            child: Center(
                              child: Text(
                                status ?? '',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        /* Logic to submit attendanceStatus map to Supabase */
                      },
                      child: const Text("SAVE ATTENDANCE"),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
