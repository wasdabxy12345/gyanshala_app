import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/features/students/presentation/tabs/attendance_parent_tab.dart';
import 'package:gyanshala_app/features/students/presentation/tabs/student_list_tab.dart';

class StudentHubPage extends ConsumerStatefulWidget {
  const StudentHubPage({super.key});

  @override
  ConsumerState<StudentHubPage> createState() => _StudentHubPageState();
}

class _StudentHubPageState extends ConsumerState<StudentHubPage> {
  String _searchQuery = "";

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Students"),
          actions: [
            IconButton(onPressed: () {}, icon: const Icon(Icons.filter_list)),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(100),
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.how_to_reg), text: "Attendance"),
                    Tab(
                      icon: Icon(Icons.people_outline),
                      text: "Students List",
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: "Search students...",
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            AttendanceParentTab(searchQuery: _searchQuery), // The complex tab
            StudentListTab(searchQuery: _searchQuery), // The simple list
          ],
        ),
      ),
    );
  }
}
