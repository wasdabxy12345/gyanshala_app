import 'package:flutter/material.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:gyanshala_app/features/admin/presentation/widgets/form_attendance_table.dart';
import 'package:intl/intl.dart';

class FormAttendanceTab extends StatefulWidget {
  final String formId;
  final String formTitle;
  final String searchQuery;
  final DateTimeRange range;
  final Function(DateTimeRange) onRangeChanged;

  FormAttendanceTab({
    super.key,
    required this.formId,
    required this.formTitle,
    required this.searchQuery,
    required this.range,
    required this.onRangeChanged,
  });

  @override
  State<FormAttendanceTab> createState() => FormAttendanceTabState();
}

class FormAttendanceTabState extends State<FormAttendanceTab> {
  final attendanceTableKey = GlobalKey<FormAttendanceTableState>();

  Future<void> refresh() async {
    await attendanceTableKey.currentState?.refresh();
  }

  Future<void> exportExcel() async {
    await attendanceTableKey.currentState?.exportExcel();
  }

  Future<void> _selectSingleDate(BuildContext context, {required bool isStart}) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? widget.range.start : widget.range.end,
      firstDate: DateTime(2025),
      lastDate: isStart ? widget.range.end : DateTime.now(),
    );

    if (picked != null) {
      if (isStart) {
        widget.onRangeChanged(DateTimeRange(start: picked, end: widget.range.end));
      } else {
        widget.onRangeChanged(DateTimeRange(start: widget.range.start, end: picked));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.arrow_left, size: 32),
                      onPressed: () {
                        final newEnd = widget.range.start.subtract(const Duration(days: 1));
                        final newStart = newEnd.subtract(const Duration(days: 6));
                        widget.onRangeChanged(DateTimeRange(start: newStart, end: newEnd));
                      },
                      tooltip: 'Previous week',
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _quickBtn("This Week", () {
                        final start = now.subtract(Duration(days: now.weekday - 1));
                        final end = start.add(const Duration(days: 6));
                        widget.onRangeChanged(DateTimeRange(start: start, end: end));
                      }),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.arrow_right, size: 32),
                      onPressed: () {
                        final newStart = widget.range.end.add(const Duration(days: 1));
                        final newEnd = newStart.add(const Duration(days: 6));
                        widget.onRangeChanged(DateTimeRange(start: newStart, end: newEnd));
                      },
                      tooltip: 'Next week',
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _dateInkWell(context: context, date: widget.range.start, isStart: true),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text("to")),
                    _dateInkWell(context: context, date: widget.range.end, isStart: false),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.arrow_left, size: 32),
                      onPressed: () {
                        final newMonthEnd = DateTime(widget.range.start.year, widget.range.start.month, 0);
                        final newMonthStart = DateTime(newMonthEnd.year, newMonthEnd.month, 1);
                        widget.onRangeChanged(DateTimeRange(start: newMonthStart, end: newMonthEnd));
                      },
                      tooltip: 'Previous month',
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _quickBtn("This Month", () {
                        final start = DateTime(now.year, now.month, 1);
                        final end = DateTime(now.year, now.month + 1, 0);
                        widget.onRangeChanged(DateTimeRange(start: start, end: end));
                      }),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.arrow_right, size: 32),
                      onPressed: () {
                        final newMonthStart = DateTime(widget.range.end.year, widget.range.end.month + 1, 1);
                        final newMonthEnd = DateTime(newMonthStart.year, newMonthStart.month + 1, 0);
                        widget.onRangeChanged(DateTimeRange(start: newMonthStart, end: newMonthEnd));
                      },
                      tooltip: 'Next month',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FormAttendanceTable(
            key: attendanceTableKey,
            formId: widget.formId,
            formTitle: widget.formTitle,
            searchQuery: widget.searchQuery,
            startDate: widget.range.start,
            endDate: widget.range.end,
          ),
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
      child: Text(label, textAlign: TextAlign.center),
    );
  }

  Widget _dateInkWell({required BuildContext context, required DateTime date, required bool isStart}) {
    return InkWell(
      onTap: () => _selectSingleDate(context, isStart: isStart),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.primaryBlue, width: 1),
          color: Colors.white,
        ),
        child: Text(_formatDateWithMonth(date), textAlign: TextAlign.center, maxLines: 1),
      ),
    );
  }

  String _formatDateWithMonth(DateTime date) {
    final dayName = DateFormat('EEE').format(date);
    final formatted = DateFormat('dd-MM-yyyy').format(date);
    return '$formatted ($dayName)';
  }
}
