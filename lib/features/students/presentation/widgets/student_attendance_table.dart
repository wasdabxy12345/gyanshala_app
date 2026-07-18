import 'dart:io';

import 'package:excel/excel.dart' hide TextSpan, Border;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide TextDirection;
import 'package:flutter/painting.dart' as painting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_html/html.dart' as html;

class StudentAttendanceTable extends ConsumerStatefulWidget {
  final String searchQuery;
  final DateTime startDate;
  final DateTime endDate;

  const StudentAttendanceTable({super.key, required this.searchQuery, required this.startDate, required this.endDate});

  @override
  ConsumerState<StudentAttendanceTable> createState() => StudentAttendanceTableState();
}

class StudentAttendanceTableState extends ConsumerState<StudentAttendanceTable> {
  late Future<Map<String, dynamic>> _attendanceFetchFuture;
  final ScrollController _horizontalHeaderController = ScrollController();
  final ScrollController _horizontalBodyController = ScrollController();
  final ScrollController _horizontalFooterController = ScrollController();

  // Pagination parameters
  int _currentPage = 0;
  int _rowsPerPage = 50;
  final List<int> _availableRowsPerPage = [25, 50, 100, 200];

  @override
  void initState() {
    super.initState();
    _attendanceFetchFuture = _loadDataPipeline();
    _horizontalBodyController.addListener(() {
      if (_horizontalHeaderController.hasClients) {
        _horizontalHeaderController.jumpTo(_horizontalBodyController.offset);
      }
      if (_horizontalFooterController.hasClients) {
        _horizontalFooterController.jumpTo(_horizontalBodyController.offset);
      }
    });
  }

  @override
  void dispose() {
    _horizontalHeaderController.dispose();
    _horizontalBodyController.dispose();
    _horizontalFooterController.dispose();
    super.dispose();
  }

  void refreshData() {
    setState(() {
      _attendanceFetchFuture = _loadDataPipeline();
    });
  }

  @override
  void didUpdateWidget(covariant StudentAttendanceTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startDate != widget.startDate || oldWidget.endDate != widget.endDate) {
      setState(() {
        _attendanceFetchFuture = _loadDataPipeline();
        _currentPage = 0; // Reset pagination when dates change
      });
    }
    if (oldWidget.searchQuery != widget.searchQuery) {
      setState(() {
        _currentPage = 0; // Reset pagination when search changes
      });
    }
  }

  Future<Map<String, dynamic>> _loadDataPipeline() async {
    try {
      final supabase = ref.read(supabaseClientProvider);

      // 1. Paginated loop to fetch ALL students from DB completely bypassing 1k limit
      List<Map<String, dynamic>> completeStudentList = [];
      bool hasMoreStudents = true;
      int fromIndex = 0;
      const int studentBatchSize = 1000;

      while (hasMoreStudents) {
        final studentsRaw = await supabase
            .from('students')
            .select('id, student_id_local, grade, gender')
            .range(fromIndex, fromIndex + studentBatchSize - 1);

        final List<Map<String, dynamic>> chunk = List<Map<String, dynamic>>.from(studentsRaw as List);
        completeStudentList.addAll(chunk);

        if (chunk.length < studentBatchSize) {
          hasMoreStudents = false;
        } else {
          fromIndex += studentBatchSize;
        }
      }

      // 2. Fetch all attendance records for the window range
      final utcRange = toUtcRange(DateTimeRange(start: widget.startDate, end: widget.endDate));
      final attendanceRecordsRaw =
          (await supabase
                  .from('student_attendance')
                  .select('id, student_id, status, created_at')
                  .gte('created_at', utcRange.start.toIso8601String())
                  .lte('created_at', utcRange.end.toIso8601String()))
              as List<dynamic>;

      return await compute(_processAttendanceData, {'students': completeStudentList, 'records': attendanceRecordsRaw});
    } catch (e) {
      rethrow;
    }
  }

  static Map<String, dynamic> _processAttendanceData(Map<String, dynamic> rawPayload) {
    final List<Map<String, dynamic>> students = List<Map<String, dynamic>>.from(rawPayload['students']);
    final List<dynamic> attendanceRecords = rawPayload['records'];

    Map<String, Map<String, dynamic>> studentData = {};
    for (final student in students) {
      studentData[student['id']] = {
        'student_id': student['id'],
        'student_id_local': student['student_id_local'] ?? 'Unknown ID',
        'attendance_map': <String, dynamic>{},
      };
    }

    final sortedRecords = List.from(attendanceRecords)
      ..sort((a, b) => DateTime.parse(a['created_at']).compareTo(DateTime.parse(b['created_at'])));

    for (final record in sortedRecords) {
      final studentId = record['student_id'];
      if (!studentData.containsKey(studentId)) continue;
      final createdAt = DateTime.parse(record['created_at']).toLocal();
      final dateKey = DateFormat('yyyy-MM-dd').format(createdAt);
      final status = record['status']?.toString().toLowerCase() ?? 'absent';

      final currentMap = studentData[studentId]!['attendance_map'] as Map<String, dynamic>;
      currentMap[dateKey] = {'status': status};
    }

    return {'students': studentData, 'records': attendanceRecords};
  }

  Future<void> exportExcel() async {
    try {
      final data = await _loadDataPipeline();
      final studentMap = data['students'] as Map<String, dynamic>;
      final List<dynamic> rawRecords = data['records'];

      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];
      final headers = ["Student Local ID", "Date", "Attendance Status"];
      sheet.appendRow(headers.map((e) => TextCellValue(e)).toList());

      final sortedRecords = List.from(rawRecords)
        ..sort((a, b) => DateTime.parse(a['created_at']).compareTo(DateTime.parse(b['created_at'])));

      final CellStyle absentStyle = CellStyle(backgroundColorHex: ExcelColor.redAccent);
      final CellStyle lateStyle = CellStyle(backgroundColorHex: ExcelColor.amberAccent);

      int currentExcelRowIndex = 1;
      for (final record in sortedRecords) {
        final studentId = record['student_id'];
        final student = studentMap[studentId];
        final String localId = student != null ? student['student_id_local'] : 'Unknown';

        if (widget.searchQuery.isNotEmpty && !localId.toLowerCase().contains(widget.searchQuery.toLowerCase())) {
          continue;
        }

        final DateTime localTime = DateTime.parse(record['created_at']).toLocal();
        final String dateStr = DateFormat('dd-MM-yyyy').format(localTime);
        final String status = record['status'] ?? 'absent';

        sheet.appendRow([TextCellValue(localId), TextCellValue(dateStr), TextCellValue(status.toUpperCase())]);

        if (status == 'absent') {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: currentExcelRowIndex)).cellStyle = absentStyle;
        } else if (status == 'late') {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: currentExcelRowIndex)).cellStyle = lateStyle;
        }
        currentExcelRowIndex++;
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Failed to generate excel file');

      final startRange = DateFormat('dd-MM-yy').format(widget.startDate);
      final endRange = DateFormat('dd-MM-yy').format(widget.endDate);
      final fileName = 'Student_Attendance_Summary_[$startRange to $endRange].xlsx';

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

    // Stable, reliable calculation for the ID column width based on the longest format pattern
    const TextStyle idStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black);
    const String longestPossibleIdFormat = 'WWWWmmmm 888888'; // Matches 'AAAAaaaa nnnnnn' using wide characters
    final Size calculatedSample = calcTextSize(context, longestPossibleIdFormat, idStyle);
    final double maxNameWidth = calculatedSample.width + 32.0; // Added explicit side-padding safety margin

    return FutureBuilder<Map<String, dynamic>>(
      future: _attendanceFetchFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text("Error fetching records: ${snapshot.error}"));
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("No attendance data found"));

        // Global dataset filtered globally by text search match queries
        final allFilteredStudents =
            ((snapshot.data!['students'] as Map<String, dynamic>).values.map((e) => Map<String, dynamic>.from(e as Map)).toList())
                .where((m) => m['student_id_local'].toString().toLowerCase().contains(widget.searchQuery.toLowerCase()))
                .toList();

        if (allFilteredStudents.isEmpty) return const Center(child: Text("No students found"));

        // Evaluate Pagination Parameters dynamically
        final totalRows = allFilteredStudents.length;
        final maxPages = (totalRows / _rowsPerPage).ceil();
        if (_currentPage >= maxPages && maxPages > 0) {
          _currentPage = maxPages - 1;
        }
        final int startIdx = _currentPage * _rowsPerPage;
        final int endIdx = (startIdx + _rowsPerPage) > totalRows ? totalRows : (startIdx + _rowsPerPage);

        // Sliced subset chunk strictly handled inside memory for the rendering layer
        final paginatedStudents = allFilteredStudents.sublist(startIdx, endIdx);

        // (Removed previous dynamic loop for maxNameWidth to maintain layout stability)

        final dates = _getDatesInRange(widget.startDate, widget.endDate);
        final workingDaysCount = dates.where((d) {
          final cellDateNormalized = DateTime(d.year, d.month, d.day);
          return !_isHoliday(d) && cellDateNormalized.isBefore(todayNormalized);
        }).length;

        // Note: Footers metrics (daily summary calculations) computed strictly on the current page slice for precision data tracking
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
            for (final m in paginatedStudents) {
              final attMap = m['attendance_map'] as Map<String, dynamic>? ?? {};
              final record = attMap[key];
              if (record != null && (record['status'] == 'present' || record['status'] == 'late')) {
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
              // Header
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
                        'Student ID',
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

              // Body (Slices)
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
                          children: paginatedStudents
                              .map(
                                (std) => Container(
                                  height: rowHeight,
                                  padding: const EdgeInsets.symmetric(horizontal: 13),
                                  alignment: Alignment.centerLeft,
                                  decoration: BoxDecoration(
                                    border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                                  ),
                                  child: Text(std['student_id_local'] ?? 'Unknown', maxLines: 1, style: idStyle),
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
                            children: paginatedStudents.map((student) {
                              final attMap = student['attendance_map'] as Map<String, dynamic>? ?? {};
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
                                    final String status = record != null ? record['status'].toString().toLowerCase() : '';
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
                                      child: Center(
                                        child: holiday
                                            ? const Icon(Icons.remove, color: Colors.grey, size: 13)
                                            : isFutureOrToday && status.isEmpty
                                            ? const SizedBox.shrink()
                                            : (() {
                                                if (status == 'present') {
                                                  return const Text(
                                                    'P',
                                                    style: TextStyle(
                                                      color: Colors.green,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                  );
                                                } else if (status == 'late') {
                                                  return const Text(
                                                    'L',
                                                    style: TextStyle(
                                                      color: Colors.amber,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                  );
                                                } else {
                                                  return const Text(
                                                    'A',
                                                    style: TextStyle(
                                                      color: Colors.red,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                  );
                                                }
                                              }()),
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
                          children: paginatedStudents.map((student) {
                            final attMap = student['attendance_map'] as Map<String, dynamic>? ?? {};
                            int attendedCount = 0;
                            for (final d in dates) {
                              final cellDateNormalized = DateTime(d.year, d.month, d.day);
                              if (!_isHoliday(d) &&
                                  !cellDateNormalized.isAtSameMomentAs(todayNormalized) &&
                                  !cellDateNormalized.isAfter(todayNormalized)) {
                                final key = DateFormat('yyyy-MM-dd').format(d);
                                final record = attMap[key];
                                final String status = record != null ? record['status'].toString().toLowerCase() : '';
                                if (status == 'present' || status == 'late') {
                                  attendedCount++;
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
                                "$attendedCount\n(${workingDaysCount == 0 ? 0 : ((attendedCount / workingDaysCount) * 100).toStringAsFixed(0)}%)",
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

              // Total Footer Row
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
                        controller: _horizontalFooterController,
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
                        workingDaysCount == 0 || paginatedStudents.isEmpty
                            ? "0.0\n(0%)"
                            : "${(grandTotalPresent / workingDaysCount).toStringAsFixed(1)}\n(${((grandTotalPresent / (paginatedStudents.length * workingDaysCount)) * 100).toStringAsFixed(0)}%)",
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: Colors.grey[300]),

              // UI Centered Pagination Control Bar
              Container(
                color: Colors.grey.shade100,
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Left: Rows Selection Selection dropdown
                    Row(
                      children: [
                        const Text("Rows per page: ", style: TextStyle(fontSize: 13)),
                        DropdownButton<int>(
                          value: _rowsPerPage,
                          isDense: true,
                          items: _availableRowsPerPage.map((e) => DropdownMenuItem<int>(value: e, child: Text("$e"))).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _rowsPerPage = val;
                                _currentPage = 0;
                              });
                            }
                          },
                        ),
                      ],
                    ),

                    // Center: Synchronized Tracking and Navigation Arrows
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Page ${_currentPage + 1} of ${maxPages == 0 ? 1 : maxPages}  •  "
                          "Students: ${totalRows == 0 ? 0 : startIdx + 1}-$endIdx of $totalRows",
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: _currentPage < maxPages - 1 ? () => setState(() => _currentPage++) : null,
                        ),
                      ],
                    ),

                    // Balanced Anchor right Spacer layout setup
                    const SizedBox(width: 120),
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
