import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/features/students/controller/student_controller.dart';
import 'package:intl/intl.dart';

class AttendanceReportTab extends ConsumerStatefulWidget {
  final String searchQuery;
  final DateTime startDate;
  final DateTime endDate;

  const AttendanceReportTab({
    super.key,
    required this.searchQuery,
    required this.startDate,
    required this.endDate,
  });

  @override
  ConsumerState<AttendanceReportTab> createState() =>
      _AttendanceReportTabState();
}

class _AttendanceReportTabState extends ConsumerState<AttendanceReportTab> {
  List<DateTime> _holidays = [];

  @override
  void initState() {
    super.initState();
    _loadHolidays();
  }

  Future<void> _loadHolidays() async {
    final list = await ref.read(studentProvider.notifier).getHolidays();
    if (mounted) setState(() => _holidays = list);
  }

  bool _isHoliday(DateTime date) {
    if (date.weekday == DateTime.sunday) return true;
    return _holidays.any(
      (h) => h.year == date.year && h.month == date.month && h.day == date.day,
    );
  }

  // --- Helper Methods (Moved INSIDE the class) ---

  List<DateTime> _getDatesInRange(DateTime start, DateTime end) {
    return List.generate(
      end.difference(start).inDays + 1,
      (i) => start.add(Duration(days: i)),
    );
  }

  Widget _buildNameCell(String fullName) {
    final parts = fullName.split(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          parts[0],
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        if (parts.length > 1)
          Text(
            parts.sublist(1).join(' '),
            style: const TextStyle(fontSize: 10, color: Colors.grey),
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  DataRow _buildFooter(
    List<Map<String, dynamic>> students,
    List<DateTime> dates,
    int totalWorkingDays,
  ) {
    double grandTotalPresent = 0;

    return DataRow(
      color: WidgetStateProperty.all(Colors.blueGrey[50]),
      cells: [
        const DataCell(
          Text("TOTAL", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        ...dates.map((d) {
          if (_isHoliday(d)) return const DataCell(Center(child: Text("-")));

          final key = DateFormat('yyyy-MM-dd').format(d);
          int count = students
              .where((s) => s['attendance_map']?[key] == 'present')
              .length;
          grandTotalPresent += count;
          return DataCell(
            Center(
              child: Text(
                "$count",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          );
        }),
        DataCell(
          Center(
            child: Text(
              totalWorkingDays == 0
                  ? "0.0\n0%"
                  : "${(grandTotalPresent / totalWorkingDays).toStringAsFixed(1)}\n"
                        "${((grandTotalPresent / (students.length * totalWorkingDays)) * 100).toStringAsFixed(0)}%",
              style: const TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ref
          .read(studentProvider.notifier)
          .getAttendanceRangeReport(widget.startDate, widget.endDate),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());

        final students = snapshot.data!
            .where(
              (s) => s['full_name'].toString().toLowerCase().contains(
                widget.searchQuery.toLowerCase(),
              ),
            )
            .toList();

        final dates = _getDatesInRange(widget.startDate, widget.endDate);
        final workingDaysCount = dates.where((d) => !_isHoliday(d)).length;

        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    border: TableBorder.all(color: Colors.grey[300]!),
                    headingRowHeight: 80,
                    columnSpacing: 15,
                    columns: [
                      const DataColumn(label: Text('Student\nName')),
                      ...dates.map(
                        (d) => DataColumn(
                          label: Container(
                            width: 40,
                            color: _isHoliday(d) ? Colors.grey[200] : null,
                            child: Center(
                              child: Text(
                                "${DateFormat('MM/dd').format(d)}\n${DateFormat('E').format(d)}",
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ),
                      DataColumn(label: Text('Total\n($workingDaysCount)')),
                    ],
                    rows: [
                      ...students.map((student) {
                        final attMap =
                            student['attendance_map']
                                as Map<String, dynamic>? ??
                            {};
                        int presentCount = 0;

                        return DataRow(
                          cells: [
                            DataCell(_buildNameCell(student['full_name'])),
                            ...dates.map((d) {
                              final key = DateFormat('yyyy-MM-dd').format(d);
                              final status = attMap[key];
                              final holiday = _isHoliday(d);

                              if (!holiday && status == 'present')
                                presentCount++;

                              return DataCell(
                                Container(
                                  color: holiday ? Colors.grey[200] : null,
                                  child: Center(
                                    child: holiday
                                        ? const Text(
                                            "-",
                                            style: TextStyle(
                                              color: Colors.grey,
                                            ),
                                          )
                                        : Text(
                                            status == 'present'
                                                ? 'P'
                                                : (status == 'absent'
                                                      ? 'A'
                                                      : ''),
                                            style: TextStyle(
                                              color: status == 'present'
                                                  ? Colors.green
                                                  : Colors.red,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                  ),
                                ),
                              );
                            }),
                            DataCell(
                              Center(
                                child: Text(
                                  "$presentCount\n${workingDaysCount == 0 ? 0 : ((presentCount / workingDaysCount) * 100).toStringAsFixed(0)}%",
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                      _buildFooter(students, dates, workingDaysCount),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
} // <--- End of _AttendanceReportTabState
