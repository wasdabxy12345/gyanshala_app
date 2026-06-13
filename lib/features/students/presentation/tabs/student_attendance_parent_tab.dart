import 'package:flutter/material.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:gyanshala_app/features/students/presentation/views/attendance_records_view.dart';
import 'package:gyanshala_app/features/students/presentation/views/attendance_taking_view.dart';

class StudentAttendanceParentTab extends StatefulWidget {
  final String searchQuery;
  const StudentAttendanceParentTab({super.key, required this.searchQuery});

  @override
  State<StudentAttendanceParentTab> createState() => _StudentAttendanceParentTabState();
}

class _StudentAttendanceParentTabState extends State<StudentAttendanceParentTab> {
  DateTime _selectedDate = DateTime.now();
  DateTimeRange _selectedRange = DateTimeRange(start: DateTime.now().subtract(const Duration(days: 7)), end: DateTime.now());

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            labelColor: AppTheme.primaryBlue,
            tabs: [
              Tab(text: "Mark Today"),
              Tab(text: "Past Records"),
            ],
          ),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                AttendanceTakingView(
                  date: _selectedDate,
                  searchQuery: widget.searchQuery,
                  onDateChanged: (d) => setState(() => _selectedDate = d),
                ),
                AttendanceRecordsView(
                  range: _selectedRange,
                  searchQuery: widget.searchQuery,
                  onRangeChanged: (r) => setState(() => _selectedRange = r),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
