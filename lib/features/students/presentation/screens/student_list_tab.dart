import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/features/students/presentation/controller/student_controller.dart';
import 'package:gyanshala_app/features/students/presentation/screens/add_student_screen.dart';

class StudentListTab extends ConsumerWidget {
  final String searchQuery; // Add this line

  const StudentListTab({
    super.key,
    required this.searchQuery,
  }); // Update constructor

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: FutureBuilder(
        future: ref.read(studentProvider.notifier).getMyStudents(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          // Filter students based on search query
          final students = snapshot.data!
              .where(
                (s) => s['full_name'].toString().toLowerCase().contains(
                  searchQuery.toLowerCase(),
                ),
              )
              .toList();

          if (students.isEmpty) {
            return const Center(child: Text("No students found."));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: students.length,
            itemBuilder: (context, index) {
              final s = students[index];
              return Card(
                child: ExpansionTile(
                  leading: CircleAvatar(child: Text(s['full_name'][0])),
                  title: Text(
                    s['full_name'],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text("ID: ${s['student_id_custom']}"),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(),
                          Text("Grade: ${s['grade']}"),
                          Text("Gender: ${s['gender']}"),
                          Text("School: ${s['school_name']}"),
                          Text("Village: ${s['village_name']}"),
                          Text("Cluster: ${s['cluster_name']}"),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddStudentScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
