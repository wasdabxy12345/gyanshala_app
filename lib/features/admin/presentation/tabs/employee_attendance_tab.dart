import 'package:flutter/material.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:gyanshala_app/features/employees/presentation/widgets/employee_attendance_table.dart';
import 'package:intl/intl.dart';

class EmployeeAttendanceTab extends StatelessWidget {
  final DateTimeRange range;
  final String searchQuery;
  final Function(DateTimeRange) onRangeChanged;

  const EmployeeAttendanceTab({super.key, required this.range, required this.searchQuery, required this.onRangeChanged});

  Future<void> _selectSingleDate(BuildContext context, {required bool isStart}) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? range.start : range.end,
      firstDate: DateTime(2025),
      lastDate: isStart ? range.end : DateTime.now(),
    );

    if (picked != null) {
      if (isStart) {
        onRangeChanged(DateTimeRange(start: picked, end: range.end));
      } else {
        onRangeChanged(DateTimeRange(start: range.start, end: picked));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3.0, vertical: 1),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.arrow_left, size: 37),
                      onPressed: () {
                        final newEnd = range.start.subtract(const Duration(days: 1));
                        final newStart = newEnd.subtract(const Duration(days: 6));
                        onRangeChanged(DateTimeRange(start: newStart, end: newEnd));
                      },
                      tooltip: 'Previous week',
                    ),
                    Expanded(
                      child: _quickBtn("This Week", () {
                        final start = now.subtract(Duration(days: now.weekday - 1));
                        final end = start.add(const Duration(days: 6));
                        onRangeChanged(DateTimeRange(start: start, end: end));
                      }),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.arrow_right, size: 37),
                      onPressed: () {
                        final newStart = range.end.add(const Duration(days: 1));
                        final newEnd = newStart.add(const Duration(days: 6));
                        onRangeChanged(DateTimeRange(start: newStart, end: newEnd));
                      },
                      tooltip: 'Next week',
                    ),
                  ],
                ),
              ),
              Center(
                child: Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    child: Row(
                      children: [
                        const SizedBox(width: 37),
                        _dateInkWell(context: context, date: range.start, isStart: true),
                        const SizedBox(width: 13),
                        Text("to"),
                        const SizedBox(width: 13),
                        _dateInkWell(context: context, date: range.end, isStart: false),
                        const SizedBox(width: 37),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.arrow_left, size: 37),
                      onPressed: () {
                        final newMonthEnd = DateTime(range.start.year, range.start.month, 0);
                        final newMonthStart = DateTime(newMonthEnd.year, newMonthEnd.month, 1);
                        onRangeChanged(DateTimeRange(start: newMonthStart, end: newMonthEnd));
                      },
                      tooltip: 'Previous month',
                    ),
                    Expanded(
                      child: _quickBtn("This Month", () {
                        final start = DateTime(now.year, now.month, 1);
                        final end = DateTime(now.year, now.month + 1, 0);
                        onRangeChanged(DateTimeRange(start: start, end: end));
                      }),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.arrow_right, size: 37),
                      onPressed: () {
                        final newMonthStart = DateTime(range.end.year, range.end.month + 1, 1);
                        final newMonthEnd = DateTime(newMonthStart.year, newMonthStart.month + 1, 0);
                        onRangeChanged(DateTimeRange(start: newMonthStart, end: newMonthEnd));
                      },
                      tooltip: 'Next month',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: EmployeeAttendanceTable(searchQuery: searchQuery, startDate: range.start, endDate: range.end),
        ),
      ],
    );
  }

  Widget _quickBtn(String label, VoidCallback action) {
    return TextButton(
      style: TextButton.styleFrom(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 37),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: action,
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _dateInkWell({required BuildContext context, required DateTime date, required bool isStart}) {
    return InkWell(
      onTap: () => _selectSingleDate(context, isStart: isStart),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 13),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.primaryBlue, width: 1),
          color: Colors.white,
        ),
        child: Text(
          _formatDateWithMonth(date),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
          textAlign: TextAlign.center,
          maxLines: 1,
        ),
      ),
    );
  }

  String _formatDateWithMonth(DateTime date) {
    final dayName = DateFormat('EEE').format(date);
    final formatted = DateFormat('dd-MM-yyyy').format(date);
    return '$formatted ($dayName)';
  }
}
