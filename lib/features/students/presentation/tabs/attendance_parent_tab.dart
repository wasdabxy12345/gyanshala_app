import 'package:flutter/material.dart';
import 'package:gyanshala_app/features/students/presentation/views/attendance_records_view.dart';
import 'package:gyanshala_app/features/students/presentation/views/daily_marking_view.dart';

class AttendanceParentTab extends StatefulWidget {
  final String searchQuery;
  const AttendanceParentTab({super.key, required this.searchQuery});

  @override
  State<AttendanceParentTab> createState() => _AttendanceParentTabState();
}

class _AttendanceParentTabState extends State<AttendanceParentTab> {
  DateTime _selectedDate = DateTime.now();
  DateTimeRange _selectedRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 7)),
    end: DateTime.now(),
  );

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            labelColor: Colors.blue,
            tabs: [
              Tab(text: "Mark Today"),
              Tab(text: "Past Records"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                DailyMarkingView(
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
