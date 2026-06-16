import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:gyanshala_app/features/employees/presentation/screens/attendance_details_page.dart';
import 'package:intl/intl.dart';

class EmployeeAttendanceTable extends ConsumerStatefulWidget {
  final String searchQuery;
  final DateTime startDate;
  final DateTime endDate;

  const EmployeeAttendanceTable({super.key, required this.searchQuery, required this.startDate, required this.endDate});

  @override
  ConsumerState<EmployeeAttendanceTable> createState() => _EmployeeAttendanceTableState();
}

class _EmployeeAttendanceTableState extends ConsumerState<EmployeeAttendanceTable> {
  late Future<Map<String, dynamic>> _attendanceFetchFuture;
  @override
  void initState() {
    super.initState();
    _attendanceFetchFuture = _loadDataPipeline();
  }

  @override
  void didUpdateWidget(covariant EmployeeAttendanceTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startDate != widget.startDate || oldWidget.endDate != widget.endDate) {
      setState(() {
        _attendanceFetchFuture = _loadDataPipeline();
      });
    } else if (oldWidget.searchQuery != widget.searchQuery) {}
  }

  Future<Map<String, dynamic>> _loadDataPipeline() async {
    try {
      final supabase = ref.read(supabaseClientProvider);
      final employeesRaw =
          ((await supabase.from('profiles').select('id, first_name, last_name').inFilter('role', [
                    'shikshaMitra',
                    'seniorMentor',
                  ]))
                  as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
      final utcRange = toUtcRange(DateTimeRange(start: widget.startDate, end: widget.endDate));
      final attendanceRecordsRaw =
          (await supabase
                  .from('employee_attendance')
                  .select('id, user_id, status, recorded_at, school_id, schools(name)')
                  .gte('recorded_at', utcRange.start.toIso8601String())
                  .lte('recorded_at', utcRange.end.toIso8601String()))
              as List<dynamic>;
      final processedData = await compute(_processAttendanceData, {'employees': employeesRaw, 'records': attendanceRecordsRaw});
      return processedData;
    } catch (e) {
      rethrow;
    }
  }

  static Map<String, dynamic> _processAttendanceData(Map<String, dynamic> rawPayload) {
    final List<Map<String, dynamic>> employees = List<Map<String, dynamic>>.from(rawPayload['employees']);
    final List<dynamic> attendanceRecords = rawPayload['records'];
    Map<String, Map<String, dynamic>> employeeData = {};
    for (final employee in employees) {
      employeeData[employee['id']] = {
        'user_id': employee['id'],
        'full_name': "${employee['first_name']} ${employee['last_name']}",
        'attendance_map': <String, dynamic>{},
      };
    }
    for (final record in attendanceRecords) {
      final userId = record['user_id'];
      final status = record['status'];
      final recordedAt = DateTime.parse(record['recorded_at']).toLocal();
      final dateKey = DateFormat('yyyy-MM-dd').format(recordedAt);
      final schoolData = record['schools'];
      final schoolName = schoolData != null ? schoolData['name'] : "off-site";
      if (employeeData.containsKey(userId)) {
        final currentMap = employeeData[userId]!['attendance_map'] as Map<String, dynamic>;
        if (status == 'check_in' || !currentMap.containsKey(dateKey)) {
          currentMap[dateKey] = {'status': 'present', 'location': schoolName};
        }
      }
    }
    return {'employees': employeeData, 'records': attendanceRecords};
  }

  bool _isHoliday(DateTime date) {
    return date.weekday == DateTime.sunday;
  }

  List<DateTime> _getDatesInRange(DateTime start, DateTime end) {
    return List.generate(end.difference(start).inDays + 1, (i) => start.add(Duration(days: i)));
  }

  Widget _buildNameCell(String fullName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [Text(fullName)],
    );
  }

  DataRow _buildFooter(List<Map<String, dynamic>> filteredEmployees, List<DateTime> dates, int totalWorkingDays) {
    double grandTotalPresent = 0;
    final row = DataRow(
      color: WidgetStateProperty.all(Colors.blueGrey[50]),
      cells: [
        const DataCell(Text("TOTAL", style: TextStyle(fontWeight: FontWeight.bold))),
        ...dates.map((d) {
          if (_isHoliday(d)) return const DataCell(Center(child: Text("-")));
          final key = DateFormat('yyyy-MM-dd').format(d);
          int count = 0;
          for (final m in filteredEmployees) {
            final attMap = m['attendance_map'] as Map<String, dynamic>? ?? {};
            final statusData = attMap[key];
            if (statusData != null && statusData['status'] == 'present') {
              count++;
            }
          }
          grandTotalPresent += count;
          return DataCell(
            Center(
              child: Text("$count", style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          );
        }),
        DataCell(
          Center(
            child: Text(
              totalWorkingDays == 0 || filteredEmployees.isEmpty
                  ? "0.0 (0%)"
                  : "${(grandTotalPresent / totalWorkingDays).toStringAsFixed(1)} (${((grandTotalPresent / (filteredEmployees.length * totalWorkingDays)) * 100).toStringAsFixed(0)}%)",
              style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
    return row;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayNormalized = DateTime(now.year, now.month, now.day);
    return FutureBuilder<Map<String, dynamic>>(
      future: _attendanceFetchFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text("Error fetching records: ${snapshot.error}"));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text("No attendance data found"));
        }
        final employees =
            ((snapshot.data!['employees'] as Map<String, dynamic>).values
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList())
                .where((m) => m['full_name'].toString().toLowerCase().contains(widget.searchQuery.toLowerCase()))
                .toList();
        if (employees.isEmpty) {
          return const Center(child: Text("No employees found"));
        }
        final dates = _getDatesInRange(widget.startDate, widget.endDate);
        final workingDaysCount = dates.where((d) => !_isHoliday(d)).length;
        final widgetTree = Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    border: TableBorder.all(color: Colors.grey[300]!),
                    headingRowHeight: 70,
                    columnSpacing: 12,
                    horizontalMargin: 10,
                    columns: [
                      const DataColumn(label: Text('Employee')),
                      ...dates.map(
                        (d) => DataColumn(
                          label: SizedBox(
                            width: 37,
                            child: Center(
                              child: Text(
                                "${DateFormat('dd/MM').format(d)}\n${DateFormat('E').format(d)}",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: _isHoliday(d) ? Colors.grey : Colors.black),
                              ),
                            ),
                          ),
                        ),
                      ),
                      DataColumn(label: Text('Total: $workingDaysCount')),
                    ],
                    rows: [
                      ...employees.map((employee) {
                        final attMap = employee['attendance_map'] as Map<String, dynamic>? ?? {};
                        int presentCount = 0;
                        final String targetUserId = employee['user_id'] ?? '';
                        return DataRow(
                          cells: [
                            DataCell(_buildNameCell(employee['full_name'] ?? 'Unknown')),
                            ...dates.map((d) {
                              final key = DateFormat('yyyy-MM-dd').format(d);
                              final record = attMap[key];
                              final holiday = _isHoliday(d);
                              final isPresent = record != null && record['status'] == 'present';
                              final location = record != null ? record['location'].toString().toLowerCase() : "";
                              if (!holiday && isPresent) {
                                presentCount++;
                              }
                              final cellDateNormalized = DateTime(d.year, d.month, d.day);
                              final bool isFutureOrToday =
                                  cellDateNormalized.isAtSameMomentAs(todayNormalized) ||
                                  cellDateNormalized.isAfter(todayNormalized);
                              return DataCell(
                                InkWell(
                                  onTap: isPresent && targetUserId.isNotEmpty
                                      ? () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => AttendanceDetailsPage(userId: targetUserId, dateString: key),
                                            ),
                                          );
                                        }
                                      : null,
                                  child: Container(
                                    width: 37,
                                    height: double.infinity,
                                    color: holiday ? Colors.grey[100] : null,
                                    alignment: Alignment.center,
                                    child: holiday
                                        ? const Icon(Icons.remove, color: Colors.grey, size: 13)
                                        : isPresent
                                        ? (location != "off-site"
                                              ? const Icon(Icons.check, color: Colors.green, size: 37)
                                              : const Icon(Icons.warning, color: Colors.amber, size: 22))
                                        : isFutureOrToday
                                        ? const SizedBox.shrink()
                                        : const Icon(Icons.close, color: Colors.red, size: 13),
                                  ),
                                ),
                              );
                            }),
                            DataCell(
                              Center(
                                child: Text(
                                  "$presentCount (${workingDaysCount == 0 ? 0 : ((presentCount / workingDaysCount) * 100).toStringAsFixed(0)}%)",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                      _buildFooter(employees, dates, workingDaysCount),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
        return widgetTree;
      },
    );
  }

  String snapshotStatus() => _attendanceFetchFuture.toString();
  static DateTimeRange toUtcRange(DateTimeRange range) {
    final start = DateTime(range.start.year, range.start.month, range.start.day).toUtc();
    final end = DateTime(range.end.year, range.end.month, range.end.day).add(const Duration(days: 1)).toUtc();
    return DateTimeRange(start: start, end: end);
  }
}
