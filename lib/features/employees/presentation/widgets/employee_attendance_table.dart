import 'dart:io';

import 'package:excel/excel.dart' hide TextSpan, Border;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide TextDirection;
import 'package:flutter/painting.dart' as painting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:gyanshala_app/features/employees/presentation/screens/attendance_details_page.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_html/html.dart' as html;

class EmployeeAttendanceTable extends ConsumerStatefulWidget {
  final String searchQuery;
  final DateTime startDate;
  final DateTime endDate;
  const EmployeeAttendanceTable({super.key, required this.searchQuery, required this.startDate, required this.endDate});

  @override
  ConsumerState<EmployeeAttendanceTable> createState() => EmployeeAttendanceTableState();
}

class EmployeeAttendanceTableState extends ConsumerState<EmployeeAttendanceTable> {
  late Future<Map<String, dynamic>> _attendanceFetchFuture;
  final ScrollController _horizontalHeaderController = ScrollController();
  final ScrollController _horizontalBodyController = ScrollController();

  @override
  void initState() {
    super.initState();
    _attendanceFetchFuture = _loadDataPipeline();
    _horizontalBodyController.addListener(() {
      if (_horizontalHeaderController.hasClients) {
        _horizontalHeaderController.jumpTo(_horizontalBodyController.offset);
      }
    });
  }

  @override
  void dispose() {
    _horizontalHeaderController.dispose();
    _horizontalBodyController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant EmployeeAttendanceTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startDate != widget.startDate || oldWidget.endDate != widget.endDate) {
      setState(() {
        _attendanceFetchFuture = _loadDataPipeline();
      });
    }
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
      return await compute(_processAttendanceData, {'employees': employeesRaw, 'records': attendanceRecordsRaw});
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
        'first_name': employee['first_name'] ?? '',
        'last_name': employee['last_name'] ?? '',
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

  Future<void> exportExcel() async {
    try {
      final data = await _loadDataPipeline();
      final employees =
          ((data['employees'] as Map<String, dynamic>).values.map((e) => Map<String, dynamic>.from(e as Map)).toList())
              .where((m) => m['full_name'].toString().toLowerCase().contains(widget.searchQuery.toLowerCase()))
              .toList();
      final dates = _getDatesInRange(widget.startDate, widget.endDate);
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];
      final headers = ['Employee', ...dates.map((d) => DateFormat('dd-MM-yyyy').format(d))];
      sheet.appendRow(headers.map((e) => TextCellValue(e)).toList());
      for (final employee in employees) {
        final attMap = employee['attendance_map'] as Map<String, dynamic>? ?? {};
        final row = <CellValue>[TextCellValue(employee['full_name'] ?? '')];
        for (final d in dates) {
          final key = DateFormat('yyyy-MM-dd').format(d);
          final record = attMap[key];
          final isPresent = record != null && record['status'] == 'present';
          final location = record != null ? record['location'].toString().toLowerCase() : "";
          String value;
          if (_isHoliday(d)) {
            value = 'Holiday';
          } else if (isPresent) {
            value = location != "off-site" ? 'Present' : 'Present (Off-Site)';
          } else if (DateTime(
            d.year,
            d.month,
            d.day,
          ).isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day))) {
            value = 'Absent';
          } else {
            value = 'Pending';
          }
          row.add(TextCellValue(value));
        }
        sheet.appendRow(row);
      }
      final bytes = excel.encode();
      if (bytes == null) throw Exception('Failed to generate excel file structure payload.');
      final startRange = DateFormat('dd-MM-yy').format(widget.startDate);
      final endRange = DateFormat('dd-MM-yy').format(widget.endDate);
      final fileName = 'Employee_Attendance_[$startRange to $endRange].xlsx';

      if (kIsWeb) {
        final blob = html.Blob([bytes], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement()
          ..href = url
          ..download = fileName
          ..style.display = 'none';
        html.document.body?.children.add(anchor);
        anchor.click();
        anchor.remove();
        html.Url.revokeObjectUrl(url);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attendance exported successfully')));
        }
      } else {
        var status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          status = await Permission.manageExternalStorage.request();
        }
        Directory? downloadsDir;
        downloadsDir = Directory('/storage/emulated/0/Download');
        if (!await downloadsDir.exists()) {
          final List<Directory>? externalDirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
          downloadsDir = externalDirs != null && externalDirs.isNotEmpty
              ? externalDirs.first
              : await getApplicationDocumentsDirectory();
        }
        final file = File('${downloadsDir.path}/$fileName');
        await file.writeAsBytes(bytes);

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    },
                  ),
                  const SizedBox(width: 13),
                  Expanded(child: Text("Saved to Downloads: $fileName", softWrap: true)),
                ],
              ),
              action: SnackBarAction(
                label: "OPEN",
                // textColor: Colors.blueAccent,
                onPressed: () async {
                  await OpenFilex.open(file.path);
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> refresh() async {
    setState(() {
      _attendanceFetchFuture = _loadDataPipeline();
    });
  }

  bool _isHoliday(DateTime date) {
    return date.weekday == DateTime.sunday;
  }

  List<DateTime> _getDatesInRange(DateTime start, DateTime end) {
    return List.generate(end.difference(start).inDays + 1, (i) => start.add(Duration(days: i)));
  }

  Size calcTextSize(BuildContext context, String text, TextStyle style) {
    final TextPainter textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: painting.TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return textPainter.size;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayNormalized = DateTime(now.year, now.month, now.day);
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 600;
    const double dateCellWidth = 50;
    const double totalColumnWidth = 50;
    final double rowHeight = isMobile ? 42 : 31;
    const double headerHeight = 42;
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
        double maxNameWidth = 0;
        const TextStyle nameStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black);
        for (final emp in employees) {
          final String textToMeasure = isMobile
              ? ((emp['first_name']?.toString().length ?? 0) > (emp['last_name']?.toString().length ?? 0)
                    ? (emp['first_name'] ?? '')
                    : (emp['last_name'] ?? ''))
              : (emp['full_name'] ?? 'Unknown');
          final Size size = calcTextSize(context, textToMeasure, nameStyle);
          final double totalNeeded = size.width + 26.0;
          if (totalNeeded > maxNameWidth) {
            maxNameWidth = totalNeeded;
          }
        }
        final dates = _getDatesInRange(widget.startDate, widget.endDate);
        final workingDaysCount = dates.where((d) {
          final cellDateNormalized = DateTime(d.year, d.month, d.day);
          return !_isHoliday(d) && cellDateNormalized.isBefore(todayNormalized);
        }).length;
        List<int> dailyTotals = [];
        double grandTotalPresent = 0;
        for (final d in dates) {
          final cellDateNormalized = DateTime(d.year, d.month, d.day);
          final bool isFutureOrToday =
              cellDateNormalized.isAtSameMomentAs(todayNormalized) || cellDateNormalized.isAfter(todayNormalized);
          if (_isHoliday(d) || isFutureOrToday) {
            dailyTotals.add(-1);
          } else {
            final key = DateFormat('yyyy-MM-dd').format(d);
            int count = 0;
            for (final m in employees) {
              final attMap = m['attendance_map'] as Map<String, dynamic>? ?? {};
              final record = attMap[key];
              final isPresent = record != null && record['status'] == 'present';
              final location = record != null ? record['location'].toString().toLowerCase() : "";
              if (isPresent && location != "off-site") count++;
            }
            dailyTotals.add(count);
            grandTotalPresent += count;
          }
        }
        return Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!)),
          child: Column(
            children: [
              Container(
                height: headerHeight,
                color: Colors.grey[200],
                child: Row(
                  children: [
                    Container(
                      width: maxNameWidth,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 13),
                      decoration: BoxDecoration(
                        border: Border(right: BorderSide(color: Colors.grey[300]!)),
                      ),
                      child: const Text(
                        'Employee',
                        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _horizontalHeaderController,
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        child: Row(
                          children: dates
                              .map(
                                (d) => Container(
                                  width: dateCellWidth,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    border: Border(right: BorderSide(color: Colors.grey[300]!)),
                                  ),
                                  child: Text(
                                    "${DateFormat('dd/MM').format(d)}\n${DateFormat('E').format(d)}",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _isHoliday(d) ? Colors.grey : Colors.black,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                    Container(
                      width: totalColumnWidth,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: Colors.grey[300]!)),
                      ),
                      child: Text(
                        'Total:\n$workingDaysCount',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: Colors.grey[300]),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: maxNameWidth,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          border: Border(right: BorderSide(color: Colors.grey[300]!)),
                        ),
                        child: Column(
                          children: employees
                              .map(
                                (emp) => Container(
                                  height: rowHeight,
                                  padding: const EdgeInsets.symmetric(horizontal: 13),
                                  alignment: Alignment.centerLeft,
                                  decoration: BoxDecoration(
                                    border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      isMobile
                                          ? "${emp['first_name'] ?? ''}\n${emp['last_name'] ?? ''}"
                                          : (emp['full_name'] ?? 'Unknown'),
                                      maxLines: isMobile ? 2 : 1,
                                      style: nameStyle,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _horizontalBodyController,
                          scrollDirection: Axis.horizontal,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: employees.map((employee) {
                              final attMap = employee['attendance_map'] as Map<String, dynamic>? ?? {};
                              final String targetUserId = employee['user_id'] ?? '';
                              return Container(
                                height: rowHeight,
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                                ),
                                child: Row(
                                  children: dates.map((d) {
                                    final key = DateFormat('yyyy-MM-dd').format(d);
                                    final record = attMap[key];
                                    final holiday = _isHoliday(d);
                                    final isPresent = record != null && record['status'] == 'present';
                                    final location = record != null ? record['location'].toString().toLowerCase() : "";
                                    final cellDateNormalized = DateTime(d.year, d.month, d.day);
                                    final bool isFutureOrToday =
                                        cellDateNormalized.isAtSameMomentAs(todayNormalized) ||
                                        cellDateNormalized.isAfter(todayNormalized);
                                    return Container(
                                      width: dateCellWidth,
                                      height: double.infinity,
                                      decoration: BoxDecoration(
                                        color: holiday ? Colors.grey[100] : null,
                                        border: Border(right: BorderSide(color: Colors.grey[200]!)),
                                      ),
                                      child: InkWell(
                                        onTap: isPresent && targetUserId.isNotEmpty
                                            ? () => Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      AttendanceDetailsPage(userId: employee['user_id'] ?? '', dateString: key),
                                                ),
                                              )
                                            : null,
                                        child: Center(
                                          child: holiday
                                              ? const Icon(Icons.remove, color: Colors.grey, size: 13)
                                              : isPresent
                                              ? (location != "off-site"
                                                    ? const Icon(Icons.check, color: Colors.green, size: 37)
                                                    : const Icon(Icons.warning, color: Colors.amber, size: 22))
                                              : isFutureOrToday
                                              ? const SizedBox.shrink()
                                              : const Icon(Icons.close, color: Colors.red, size: 17),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      Container(
                        width: totalColumnWidth,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          border: Border(left: BorderSide(color: Colors.grey[300]!)),
                        ),
                        child: Column(
                          children: employees.map((employee) {
                            final attMap = employee['attendance_map'] as Map<String, dynamic>? ?? {};
                            int presentCount = 0;
                            for (final d in dates) {
                              final cellDateNormalized = DateTime(d.year, d.month, d.day);
                              if (!_isHoliday(d) &&
                                  !cellDateNormalized.isAtSameMomentAs(todayNormalized) &&
                                  !cellDateNormalized.isAfter(todayNormalized)) {
                                final key = DateFormat('yyyy-MM-dd').format(d);
                                final record = attMap[key];
                                final isPresent = record != null && record['status'] == 'present';
                                final location = record != null ? record['location'].toString().toLowerCase() : "";
                                if (isPresent && location != "off-site") {
                                  presentCount++;
                                }
                              }
                            }
                            return Container(
                              height: rowHeight,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                              ),
                              child: Text(
                                "$presentCount\n(${workingDaysCount == 0 ? 0 : ((presentCount / workingDaysCount) * 100).toStringAsFixed(0)}%)",
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Colors.black),
                                textAlign: TextAlign.center,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, thickness: 1, color: Colors.grey[300]),
              Container(
                height: rowHeight,
                color: Colors.blueGrey[50],
                child: Row(
                  children: [
                    Container(
                      width: maxNameWidth,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 13),
                      decoration: BoxDecoration(
                        border: Border(right: BorderSide(color: Colors.grey[300]!)),
                      ),
                      child: const Text(
                        "TOTAL",
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _horizontalHeaderController,
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        child: Row(
                          children: dailyTotals
                              .map(
                                (count) => Container(
                                  width: dateCellWidth,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    border: Border(right: BorderSide(color: Colors.grey[200]!)),
                                  ),
                                  child: Text(
                                    count == -1 ? "-" : "$count",
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                    Container(
                      width: totalColumnWidth,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: Colors.grey[300]!)),
                      ),
                      child: Text(
                        workingDaysCount == 0 || employees.isEmpty
                            ? "0.0\n(0%)"
                            : "${(grandTotalPresent / workingDaysCount).toStringAsFixed(1)}\n(${((grandTotalPresent / (employees.length * workingDaysCount)) * 100).toStringAsFixed(0)}%)",
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static DateTimeRange toUtcRange(DateTimeRange range) {
    final start = DateTime(range.start.year, range.start.month, range.start.day).toUtc();
    final end = DateTime(range.end.year, range.end.month, range.end.day).add(const Duration(days: 1)).toUtc();
    return DateTimeRange(start: start, end: end);
  }
}
