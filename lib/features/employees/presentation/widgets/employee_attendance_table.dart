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
                    'shikshaMitra38',
                    'shikshaMitra910',
                    'mentorBV8',
                  ]))
                  as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();

      final utcRange = toUtcRange(DateTimeRange(start: widget.startDate, end: widget.endDate));

      // Added attendance_time_variance directly into select block context
      final attendanceRecordsRaw =
          (await supabase
                  .from('employee_attendance')
                  .select(
                    'id, user_id, latitude, longitude, status, recorded_at, school_id, attendance_time_variance, schools(name)',
                  )
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

    // Sort records chronologically so entries build systematically
    final sortedRecords = List.from(attendanceRecords)
      ..sort((a, b) => DateTime.parse(a['recorded_at']).compareTo(DateTime.parse(b['recorded_at'])));

    for (final record in sortedRecords) {
      final userId = record['user_id'];
      if (!employeeData.containsKey(userId)) continue;

      final recordedAt = DateTime.parse(record['recorded_at']).toLocal();
      final dateKey = DateFormat('yyyy-MM-dd').format(recordedAt);

      final schoolData = record['schools'];
      final currentSchoolName = (schoolData != null && schoolData['name'] != null) ? schoolData['name'].toString() : "off-site";
      final currentVariance = record['attendance_time_variance']?.toString() ?? "99:99:99";

      final currentMap = employeeData[userId]!['attendance_map'] as Map<String, dynamic>;

      if (!currentMap.containsKey(dateKey)) {
        // First entry of the day
        currentMap[dateKey] = {'status': 'present', 'location': currentSchoolName, 'variance': currentVariance};
      } else {
        // Cumulative Day Evaluator: If either event fails, poison the flag state for the day
        final existingData = currentMap[dateKey] as Map<String, dynamic>;

        // 1. Location Rule: If check-in OR check-out was off-site, the whole day drops to off-site status
        String finalLocation = existingData['location'];
        if (currentSchoolName == "off-site" || finalLocation == "off-site") {
          finalLocation = "off-site";
        }

        // 2. Timing Rule: If either event is not perfect ("00:00:00"), preserve the violating variance string
        String finalVariance = existingData['variance'];
        bool currentHasError = currentVariance != "00:00:00" && currentVariance != "00:00:00.000";
        bool existingHasError = finalVariance != "00:00:00" && finalVariance != "00:00:00.000";

        if (currentHasError || existingHasError) {
          // If the new record carries an explicit failure message, or if a failure was already registered, prioritize the error string
          finalVariance = currentHasError ? currentVariance : finalVariance;
        }

        currentMap[dateKey] = {'status': 'present', 'location': finalLocation, 'variance': finalVariance};
      }
    }
    return {'employees': employeeData, 'records': attendanceRecords};
  }

  Future<void> exportExcel() async {
    try {
      final data = await _loadDataPipeline();
      final employeeMap = data['employees'] as Map<String, dynamic>;
      final List<dynamic> rawRecords = data['records'];
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];
      final headers = ["User's Name", 'Latitude', 'Longitude', 'Status', 'Recorded At', 'School', 'Time Variance'];
      sheet.appendRow(headers.map((e) => TextCellValue(e)).toList());

      for (final record in rawRecords) {
        final userId = record['user_id'];
        final employee = employeeMap[userId];
        final String fullName = employee != null ? employee['full_name'] : 'Unknown Employee';

        if (widget.searchQuery.isNotEmpty && !fullName.toLowerCase().contains(widget.searchQuery.toLowerCase())) {
          continue;
        }

        final double? lat = record['latitude'] != null ? double.tryParse(record['latitude'].toString()) : null;
        final double? lng = record['longitude'] != null ? double.tryParse(record['longitude'].toString()) : null;
        final String status = record['status'] ?? '';
        final DateTime localRecordedAt = DateTime.parse(record['recorded_at']).toLocal();
        final String formattedDate = DateFormat('dd-MM-yyyy HH:mm:ss').format(localRecordedAt);
        final schoolData = record['schools'];
        final String schoolName = (schoolData != null && schoolData['name'] != null) ? schoolData['name'].toString() : "off-site";
        final String variance = record['attendance_time_variance']?.toString() ?? "99:99:99";

        sheet.appendRow([
          TextCellValue(fullName),
          lat != null ? DoubleCellValue(lat) : TextCellValue(''),
          lng != null ? DoubleCellValue(lng) : TextCellValue(''),
          TextCellValue(status),
          TextCellValue(formattedDate),
          TextCellValue(schoolName),
          TextCellValue(variance),
        ]);
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Failed to generate excel file');
      final startRange = DateFormat('dd-MM-yy').format(widget.startDate);
      final endRange = DateFormat('dd-MM-yy').format(widget.endDate);
      final fileName = 'Employee_Attendance_Details_[$startRange to $endRange].xlsx';

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
        Directory? downloadsDir = Directory('/storage/emulated/0/Download');
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
                    onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
                  ),
                  const SizedBox(width: 13),
                  Expanded(child: Text("Saved to Downloads: $fileName", softWrap: true)),
                ],
              ),
              action: SnackBarAction(label: "OPEN", onPressed: () async => await OpenFilex.open(file.path)),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red));
    }
  }

  bool _isHoliday(DateTime date) => date.weekday == DateTime.sunday;
  List<DateTime> _getDatesInRange(DateTime start, DateTime end) =>
      List.generate(end.difference(start).inDays + 1, (i) => start.add(Duration(days: i)));

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
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text("Error fetching records: ${snapshot.error}"));
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("No attendance data found"));

        final employees =
            ((snapshot.data!['employees'] as Map<String, dynamic>).values
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList())
                .where((m) => m['full_name'].toString().toLowerCase().contains(widget.searchQuery.toLowerCase()))
                .toList();

        if (employees.isEmpty) return const Center(child: Text("No employees found"));

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
          if (totalNeeded > maxNameWidth) maxNameWidth = totalNeeded;
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
              final location = record != null ? record['location'].toString().toLowerCase() : "off-site";
              final variance = record != null ? record['variance'].toString() : "99:99:99";

              // Increment toward total column count only if they are perfectly valid (on-site and on-time)
              if (isPresent && location != "off-site" && (variance == "00:00:00" || variance == "00:00:00.000")) {
                count++;
              }
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

                                    final location = record != null ? record['location'].toString().toLowerCase() : "off-site";
                                    final variance = record != null ? record['variance'].toString() : "99:99:99";

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
                                              ? (() {
                                                  final bool isCorrectLocation = location != "off-site";
                                                  final bool isOnTime = variance == "00:00:00" || variance == "00:00:00.000";

                                                  // IMPLEMENTING SETTLED MATRIX RULE ENGINE RULES
                                                  if (isCorrectLocation && isOnTime) {
                                                    return const Icon(Icons.check, color: Colors.green, size: 28);
                                                  } else if (isCorrectLocation && !isOnTime) {
                                                    return const Icon(Icons.access_time, color: Colors.amber, size: 22);
                                                  } else if (!isCorrectLocation && isOnTime) {
                                                    return const Icon(Icons.wrong_location, color: Colors.amber, size: 22);
                                                  } else {
                                                    return const Icon(
                                                      Icons.warning,
                                                      color: Colors.purple,
                                                      size: 22,
                                                    ); // Deep Purple fallback
                                                  }
                                                }())
                                              : isFutureOrToday
                                              ? const SizedBox.shrink()
                                              : const Icon(Icons.close, color: Colors.red, size: 15),
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
                                final location = record != null ? record['location'].toString().toLowerCase() : "off-site";
                                final variance = record != null ? record['variance'].toString() : "99:99:99";

                                if (isPresent &&
                                    location != "off-site" &&
                                    (variance == "00:00:00" || variance == "00:00:00.000")) {
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
