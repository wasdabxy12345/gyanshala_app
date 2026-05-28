import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/features/employees/presentation/tabs/employee_attendance_records_tab.dart';
import 'package:gyanshala_app/features/employees/presentation/tabs/employees_list_tab.dart';

class EmployeeHubPage extends ConsumerStatefulWidget {
  const EmployeeHubPage({super.key});

  @override
  ConsumerState<EmployeeHubPage> createState() => _EmployeeHubPageState();
}

class _EmployeeHubPageState extends ConsumerState<EmployeeHubPage> {
  String _searchQuery = "";

  DateTimeRange _selectedRange = DateTimeRange(start: DateTime.now().subtract(const Duration(days: 7)), end: DateTime.now());

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Employees"),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(110),
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.history), text: "Employee Attendance"),
                    Tab(icon: Icon(Icons.people_outline), text: "Employee List"),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: "Search Employees...",
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            EmployeeAttendanceRecordsTab(
              range: _selectedRange,
              searchQuery: _searchQuery,
              onRangeChanged: (r) => setState(() => _selectedRange = r),
            ),
            EmployeeListTab(searchQuery: _searchQuery),
          ],
        ),
      ),
    );
  }
}
