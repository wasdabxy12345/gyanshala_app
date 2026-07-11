import 'package:flutter/material.dart';
import 'package:gyanshala_app/features/students/presentation/tabs/student_attendance_records_tab.dart';
import 'package:gyanshala_app/features/students/presentation/tabs/student_list_tab.dart';

class StudentHubPage extends StatefulWidget {
  const StudentHubPage({super.key});

  @override
  State<StudentHubPage> createState() => _StudentHubPage();
}

class _StudentHubPage extends State<StudentHubPage> {
  String _searchQuery = "";

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text("Students"),
          bottom: TabBar(
            tabs: [
              Tab(text: "Student Attendance"),
              Tab(text: "Student List"),
            ],
          ),
        ),
        body: TabBarView(
          physics: NeverScrollableScrollPhysics(),
          children: [
            StudentAttendanceRecordsTab(searchQuery: _searchQuery),
            StudentListTab(searchQuery: _searchQuery),
          ],
        ),
      ),
    );
  }
}
