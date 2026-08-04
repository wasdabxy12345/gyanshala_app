import 'dart:io';

import 'package:excel/excel.dart' hide TextSpan, Border;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide TextDirection;
import 'package:flutter/painting.dart' as painting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:gyanshala_app/features/employees/presentation/screens/employee_attendance_details_page.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_html/html.dart' as html;

class EmployeeAttendanceTable extends ConsumerStatefulWidget {
  final String searchQuery;
  final DateTime startDate;
  final DateTime endDate;
  final Set<String>? roleFilter;
  final Set<String>? genderFilter;
  final Set<String>? clusterFilter;
  final Set<String>? villageFilter;
  final Set<String>? schoolFilter;

  const EmployeeAttendanceTable({
    super.key,
    required this.searchQuery,
    required this.startDate,
    required this.endDate,
    this.roleFilter,
    this.genderFilter,
    this.clusterFilter,
    this.villageFilter,
    this.schoolFilter,
  });

  @override
  ConsumerState<EmployeeAttendanceTable> createState() => EmployeeAttendanceTableState();
}

class EmployeeAttendanceTableState extends ConsumerState<EmployeeAttendanceTable> {
  late Future<Map<String, dynamic>> _attendanceFetchFuture;
  final ScrollController _horizontalHeaderController = ScrollController();
  final ScrollController _horizontalBodyController = ScrollController();

  bool _isAscending = true;
  Set<String>? _selectedEmployeeNameFilters;

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
          ((await supabase.from('profiles').select('id, first_name, last_name, role, gender').inFilter('role', [
                    'shikshaMitra38',
                    'shikshaMitra910',
                    'mentorBV8',
                    'designTeamSS',
                    'designTeamGS',
                    'fieldCoordinator',
                  ]))
                  as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();

      // Fetch school assignments with full hierarchy
      final profileSchoolsRaw =
          ((await supabase
                      .from('profile_schools')
                      .select('user_id, school_id, schools(id, name, villages(id, name, clusters(id, name)))'))
                  as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();

      final utcRange = toUtcRange(DateTimeRange(start: widget.startDate, end: widget.endDate));
      final attendanceRecordsRaw =
          (await supabase
                  .from('employee_attendance')
                  .select(
                    'id, user_id, latitude, longitude, status, recorded_at, school_id, attendance_time_variance, schools(name)',
                  )
                  .gte('recorded_at', utcRange.start.toIso8601String())
                  .lte('recorded_at', utcRange.end.toIso8601String()))
              as List<dynamic>;

      return await compute(_processAttendanceData, {
        'employees': employeesRaw,
        'records': attendanceRecordsRaw,
        'profileSchools': profileSchoolsRaw,
      });
    } catch (e) {
      rethrow;
    }
  }

  static Map<String, dynamic> _processAttendanceData(Map<String, dynamic> rawPayload) {
    final List<Map<String, dynamic>> employees = List<Map<String, dynamic>>.from(rawPayload['employees']);
    final List<dynamic> attendanceRecords = rawPayload['records'];
    final List<Map<String, dynamic>> profileSchools = List<Map<String, dynamic>>.from(rawPayload['profileSchools']);

    // Build per-user school/village/cluster sets
    Map<String, Set<String>> userSchools = {};
    Map<String, Set<String>> userVillages = {};
    Map<String, Set<String>> userClusters = {};

    for (final ps in profileSchools) {
      final uid = ps['user_id'] as String;
      final school = ps['schools'] as Map?;
      if (school == null) continue;
      final schoolName = school['name']?.toString() ?? '';
      final village = school['villages'] as Map?;
      final villageName = village?['name']?.toString() ?? '';
      final cluster = village?['clusters'] as Map?;
      final clusterName = cluster?['name']?.toString() ?? '';

      userSchools.putIfAbsent(uid, () => {}).add(schoolName);
      if (villageName.isNotEmpty) userVillages.putIfAbsent(uid, () => {}).add(villageName);
      if (clusterName.isNotEmpty) userClusters.putIfAbsent(uid, () => {}).add(clusterName);
    }

    Map<String, Map<String, dynamic>> employeeData = {};
    for (final employee in employees) {
      final uid = employee['id'] as String;
      employeeData[uid] = {
        'user_id': uid,
        'full_name': "${employee['first_name']} ${employee['last_name']}",
        'first_name': employee['first_name'] ?? '',
        'last_name': employee['last_name'] ?? '',
        'role': employee['role'] ?? '',
        'gender': employee['gender'] ?? '',
        'schools': userSchools[uid]?.toList() ?? [],
        'villages': userVillages[uid]?.toList() ?? [],
        'clusters': userClusters[uid]?.toList() ?? [],
        'attendance_map': <String, dynamic>{},
      };
    }

    // ... rest of attendance processing unchanged
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
        currentMap[dateKey] = {'status': 'present', 'location': currentSchoolName, 'variance': currentVariance};
      } else {
        final existingData = currentMap[dateKey] as Map<String, dynamic>;
        String finalLocation = existingData['location'];
        if (currentSchoolName == "off-site" || finalLocation == "off-site") finalLocation = "off-site";
        String finalVariance = existingData['variance'];
        bool currentHasError = currentVariance != "00:00:00" && currentVariance != "00:00:00.000";
        bool existingHasError = finalVariance != "00:00:00" && finalVariance != "00:00:00.000";
        if (currentHasError || existingHasError) finalVariance = currentHasError ? currentVariance : finalVariance;
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

      final headers = [
        "Name",
        "Date",
        "Check In Time",
        "Check Out Time",
        "Check In Location",
        "Check Out Location",
        "Check In Coordinates",
        "Check Out Coordinates",
      ];
      sheet.appendRow(headers.map((e) => TextCellValue(e)).toList());

      Map<String, Map<String, dynamic>> structuredRows = {};
      final sortedRecords = List.from(rawRecords)
        ..sort((a, b) => DateTime.parse(a['recorded_at']).compareTo(DateTime.parse(b['recorded_at'])));

      for (final record in sortedRecords) {
        final userId = record['user_id'];
        final employee = employeeMap[userId];
        final String fullName = employee != null ? employee['full_name'] : 'Unknown Employee';
        if (widget.searchQuery.isNotEmpty && !fullName.toLowerCase().contains(widget.searchQuery.toLowerCase())) {
          continue;
        }
        if (_selectedEmployeeNameFilters != null && !_selectedEmployeeNameFilters!.contains(fullName)) {
          continue;
        }
        final DateTime localTime = DateTime.parse(record['recorded_at']).toLocal();
        final String dateKey = DateFormat('dd-MM-yyyy').format(localTime);
        final String timeStr = DateFormat('HH:mm:ss').format(localTime);
        final String status = record['status'] ?? '';

        final schoolData = record['schools'];
        final String schoolName = (schoolData != null && schoolData['name'] != null) ? schoolData['name'].toString() : "off-site";
        final String variance = record['attendance_time_variance']?.toString() ?? "99:99:99";

        final lat = record['latitude'];
        final lon = record['longitude'];
        final String coordinatesStr = (lat != null && lon != null) ? "$lat, $lon" : '';

        final String rowCompositeKey = "${userId}_$dateKey";
        if (!structuredRows.containsKey(rowCompositeKey)) {
          structuredRows[rowCompositeKey] = {
            'name': fullName,
            'date': dateKey,
            'check_in_time': '',
            'check_in_variance': '99:99:99',
            'check_in_loc': 'off-site',
            'check_in_coords': '',
            'check_out_time': '',
            'check_out_variance': '99:99:99',
            'check_out_loc': 'off-site',
            'check_out_coords': '',
          };
        }

        if (status == 'check_in') {
          structuredRows[rowCompositeKey]!['check_in_time'] = timeStr;
          structuredRows[rowCompositeKey]!['check_in_variance'] = variance;
          structuredRows[rowCompositeKey]!['check_in_loc'] = schoolName;
          structuredRows[rowCompositeKey]!['check_in_coords'] = coordinatesStr;
        } else if (status == 'check_out') {
          structuredRows[rowCompositeKey]!['check_out_time'] = timeStr;
          structuredRows[rowCompositeKey]!['check_out_variance'] = variance;
          structuredRows[rowCompositeKey]!['check_out_loc'] = schoolName;
          structuredRows[rowCompositeKey]!['check_out_coords'] = coordinatesStr;
        }
      }

      final CellStyle offSiteAlertStyle = CellStyle(backgroundColorHex: ExcelColor.redAccent);
      final CellStyle varianceAlertStyle = CellStyle(backgroundColorHex: ExcelColor.redAccent);
      int currentExcelRowIndex = 1;

      for (final rowKey in structuredRows.keys) {
        final r = structuredRows[rowKey]!;

        sheet.appendRow([
          TextCellValue(r['name']),
          TextCellValue(r['date']),
          TextCellValue(r['check_in_time']),
          TextCellValue(r['check_out_time']),
          TextCellValue(r['check_in_loc']),
          TextCellValue(r['check_out_loc']),
          TextCellValue(r['check_in_coords']),
          TextCellValue(r['check_out_coords']),
        ]);

        final String checkInVar = r['check_in_variance'];
        final String checkOutVar = r['check_out_variance'];
        final String checkInLoc = r['check_in_loc'].toString().toLowerCase();
        final String checkOutLoc = r['check_out_loc'].toString().toLowerCase();

        bool isCheckInLate = checkInVar != "00:00:00" && checkInVar != "00:00:00.000";
        bool isCheckOutEarly = checkOutVar != "00:00:00" && checkOutVar != "00:00:00.000";

        if (isCheckInLate && r['check_in_time'].isNotEmpty) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: currentExcelRowIndex)).cellStyle = varianceAlertStyle;
        }
        if (isCheckOutEarly && r['check_out_time'].isNotEmpty) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: currentExcelRowIndex)).cellStyle = varianceAlertStyle;
        }
        if (checkInLoc == "off-site") {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: currentExcelRowIndex)).cellStyle = offSiteAlertStyle;
        }
        if (checkOutLoc == "off-site") {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: currentExcelRowIndex)).cellStyle = offSiteAlertStyle;
        }

        currentExcelRowIndex++;
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Failed to generate excel file');

      final startRange = DateFormat('dd-MM-yy').format(widget.startDate);
      final endRange = DateFormat('dd-MM-yy').format(widget.endDate);
      final fileName = 'Employee_Attendance_Summary_[$startRange to $endRange].xlsx';

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

  Future<void> _showFilterMenu(List<String> allEmployeeNames) async {
    Set<String> currentSelection = _selectedEmployeeNameFilters != null
        ? Set.from(_selectedEmployeeNameFilters!)
        : Set.from(allEmployeeNames);

    final dialogSearchController = TextEditingController();
    List<String> filteredValues = List.from(allEmployeeNames);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text("Filter by Employee Name"),
          content: SizedBox(
            width: 320,
            height: 450,
            child: Column(
              children: [
                TextField(
                  controller: dialogSearchController,
                  decoration: const InputDecoration(hintText: "Search names...", prefixIcon: Icon(Icons.search)),
                  onChanged: (value) {
                    setStateDialog(() {
                      filteredValues = allEmployeeNames.where((e) => e.toLowerCase().contains(value.toLowerCase())).toList();
                    });
                  },
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  dense: true,
                  value: currentSelection.length == allEmployeeNames.length,
                  title: const Text("Select All"),
                  onChanged: (checked) {
                    setStateDialog(() {
                      currentSelection = checked == true ? Set.from(allEmployeeNames) : {};
                    });
                  },
                ),
                const Divider(),
                Expanded(
                  child: ListView(
                    children: filteredValues.map((value) {
                      return CheckboxListTile(
                        dense: true,
                        value: currentSelection.contains(value),
                        title: Text(value),
                        onChanged: (checked) {
                          setStateDialog(() {
                            checked == true ? currentSelection.add(value) : currentSelection.remove(value);
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  final isAllSelected = currentSelection.length == allEmployeeNames.length;
                  _selectedEmployeeNameFilters = isAllSelected ? null : Set.from(currentSelection);
                });
                Navigator.pop(ctx);
              },
              child: const Text("Apply"),
            ),
          ],
        ),
      ),
    );
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

        final allEmployees = ((snapshot.data!['employees'] as Map<String, dynamic>).values
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList());

        final allEmployeeNames = allEmployees.map((e) => e['full_name']?.toString() ?? 'Unknown').toSet().toList()..sort();

        var employees = allEmployees.where((m) {
          final fullName = m['full_name'].toString();
          if (widget.searchQuery.isNotEmpty && !fullName.toLowerCase().contains(widget.searchQuery.toLowerCase())) return false;
          if (_selectedEmployeeNameFilters != null && !_selectedEmployeeNameFilters!.contains(fullName)) return false;
          // NEW filters
          if (widget.roleFilter != null && !widget.roleFilter!.contains(m['role'])) return false;
          if (widget.genderFilter != null && !widget.genderFilter!.contains(m['gender'])) return false;
          if (widget.clusterFilter != null) {
            final userClusters = Set<String>.from(m['clusters'] as List);
            if (userClusters.intersection(widget.clusterFilter!).isEmpty) return false;
          }
          if (widget.villageFilter != null) {
            final userVillages = Set<String>.from(m['villages'] as List);
            if (userVillages.intersection(widget.villageFilter!).isEmpty) return false;
          }
          if (widget.schoolFilter != null) {
            final userSchools = Set<String>.from(m['schools'] as List);
            if (userSchools.intersection(widget.schoolFilter!).isEmpty) return false;
          }
          return true;
        }).toList();

        employees.sort((a, b) {
          final valA = (a['full_name'] ?? '').toString().toLowerCase();
          final valB = (b['full_name'] ?? '').toString().toLowerCase();
          int compare = valA.compareTo(valB);
          return _isAscending ? compare : -compare;
        });

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
          final double totalNeeded = size.width + 48.0; // Added padding for sort/filter icons in header
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
              if (_selectedEmployeeNameFilters != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  color: Colors.blue.shade50,
                  child: Row(
                    children: [
                      Text(
                        'Filtered by ${_selectedEmployeeNameFilters!.length} Employee(s)',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 13),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => setState(() => _selectedEmployeeNameFilters = null),
                        icon: const Icon(Icons.filter_alt_off, size: 16),
                        label: const Text('Clear Table Filters'),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                      ),
                    ],
                  ),
                ),
              Container(
                height: headerHeight,
                color: Colors.grey[200],
                child: Row(
                  children: [
                    Container(
                      width: maxNameWidth,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border(right: BorderSide(color: Colors.grey[300]!)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _isAscending = !_isAscending;
                                });
                              },
                              child: Row(
                                children: [
                                  const Flexible(
                                    child: Text(
                                      'Employee',
                                      style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(
                                    _isAscending ? Icons.arrow_upward : Icons.arrow_downward,
                                    size: 13,
                                    color: AppTheme.primaryBlue,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => _showFilterMenu(allEmployeeNames),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: _selectedEmployeeNameFilters != null
                                    ? AppTheme.primaryBlue.withAlpha(33)
                                    : Colors.transparent,
                              ),
                              child: Icon(
                                Icons.filter_alt,
                                size: 13,
                                color: _selectedEmployeeNameFilters != null ? AppTheme.primaryBlue : Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
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
                                                  builder: (context) => EmployeeAttendanceDetailsPage(
                                                    userId: employee['user_id'] ?? '',
                                                    dateString: key,
                                                  ),
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
                                                  if (isCorrectLocation && isOnTime) {
                                                    return const Icon(Icons.check, color: Colors.green, size: 28);
                                                  } else if (isCorrectLocation && !isOnTime) {
                                                    return const Icon(Icons.access_time, color: Colors.amber, size: 22);
                                                  } else if (!isCorrectLocation && isOnTime) {
                                                    return const Icon(Icons.wrong_location, color: Colors.amber, size: 22);
                                                  } else {
                                                    return const Icon(Icons.warning, color: Colors.purple, size: 22);
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
