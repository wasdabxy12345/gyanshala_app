import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/features/students/presentation/screens/daily_attendance_tab.dart';
import 'package:gyanshala_app/features/students/presentation/screens/student_list_tab.dart';

class StudentHubPage extends ConsumerStatefulWidget {
  const StudentHubPage({super.key});

  @override
  ConsumerState<StudentHubPage> createState() => _StudentHubPageState();
}

class _StudentHubPageState extends ConsumerState<StudentHubPage> {
  DateTime _selectedDate = DateTime.now();
  String _searchQuery = "";

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Student Hub"),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(
              110,
            ), // Increased for search bar
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.how_to_reg), text: "Attendance"),
                    Tab(icon: Icon(Icons.people), text: "Students"),
                  ],
                ),
                // Search Bar Row
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.filter_list),
                        onPressed: () {
                          /* Show Filter Dialog */
                        },
                      ),
                      Expanded(
                        child: TextField(
                          onChanged: (val) =>
                              setState(() => _searchQuery = val),
                          decoration: InputDecoration(
                            hintText: "Search students...",
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.all(0),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.calendar_month),
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime(2024),
                            lastDate: DateTime.now(),
                          );
                          if (date != null) {
                            setState(() => _selectedDate = date);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            DailyAttendanceTab(searchQuery: _searchQuery, date: _selectedDate),
            StudentListTab(searchQuery: _searchQuery),
          ],
        ),
      ),
    );
  }
}
