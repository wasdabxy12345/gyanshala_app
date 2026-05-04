import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../widgets/attendance_report_tab.dart';

class AttendanceRecordsView extends StatelessWidget {
  final DateTimeRange range;
  final String searchQuery;
  final Function(DateTimeRange) onRangeChanged;

  const AttendanceRecordsView({
    super.key,
    required this.range,
    required this.searchQuery,
    required this.onRangeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            '${_formatDateWithMonth(range.start)} - ${_formatDateWithMonth(range.end)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Expanded(
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_left),
                      onPressed: () {
                        final newEnd = range.start.subtract(
                          const Duration(days: 1),
                        );
                        final newStart = newEnd.subtract(
                          const Duration(days: 6),
                        );
                        onRangeChanged(
                          DateTimeRange(start: newStart, end: newEnd),
                        );
                      },
                      tooltip: 'Previous week',
                    ),
                    Expanded(
                      child: _quickBtn("This Week", () {
                        final start = now.subtract(
                          Duration(days: now.weekday - 1),
                        );
                        final end = start.add(const Duration(days: 6));
                        onRangeChanged(DateTimeRange(start: start, end: end));
                      }),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_right),
                      onPressed: () {
                        final newStart = range.end.add(const Duration(days: 1));
                        final newEnd = newStart.add(const Duration(days: 6));
                        onRangeChanged(
                          DateTimeRange(start: newStart, end: newEnd),
                        );
                      },
                      tooltip: 'Next week',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_left),
                      onPressed: () {
                        final newMonthEnd = DateTime(
                          range.start.year,
                          range.start.month,
                          0,
                        );
                        final newMonthStart = DateTime(
                          newMonthEnd.year,
                          newMonthEnd.month,
                          1,
                        );
                        onRangeChanged(
                          DateTimeRange(start: newMonthStart, end: newMonthEnd),
                        );
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
                      icon: const Icon(Icons.arrow_right),
                      onPressed: () {
                        final newMonthStart = DateTime(
                          range.end.year,
                          range.end.month + 1,
                          1,
                        );
                        final newMonthEnd = DateTime(
                          newMonthStart.year,
                          newMonthStart.month + 1,
                          0,
                        );
                        onRangeChanged(
                          DateTimeRange(start: newMonthStart, end: newMonthEnd),
                        );
                      },
                      tooltip: 'Next month',
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.date_range),
                onPressed: () async {
                  final r = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                  );
                  if (r != null) onRangeChanged(r);
                },
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: AttendanceReportTab(
            searchQuery: searchQuery,
            startDate: range.start,
            endDate: range.end,
          ),
        ),
      ],
    );
  }

  Widget _quickBtn(String label, VoidCallback action) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      onPressed: action,
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  String _formatDateWithMonth(DateTime date) {
    final dayName = DateFormat('EEE').format(date);
    final formatted = DateFormat('dd-MM-yyyy').format(date);
    return '$formatted ($dayName)';
  }
}
