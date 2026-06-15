import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:gyanshala_app/features/admin/presentation/tabs/employee_attendance_tab.dart';
import 'package:gyanshala_app/features/admin/presentation/tabs/employees_list_tab.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;

class EmployeeHubPage extends ConsumerStatefulWidget {
  const EmployeeHubPage({super.key});
  @override
  ConsumerState<EmployeeHubPage> createState() => _EmployeeHubPageState();
}

class _EmployeeHubPageState extends ConsumerState<EmployeeHubPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = "";
  bool _isExporting = false;
  DateTimeRange _selectedRange = DateTimeRange(
    start: DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1)),
    end: DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1)).add(const Duration(days: 6)),
  );
  final GlobalKey<EmployeeListTabState> _employeeListKey = GlobalKey<EmployeeListTabState>();
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _exportAttendanceToExcel() async {
    setState(() => _isExporting = true);
    try {
      final supabase = ref.read(supabaseClientProvider);
      final utcRange = toUtcRange(_selectedRange);

      final attendanceData = await supabase
          .from('employee_attendance')
          .select('recorded_at, status, latitude, longitude, user_id')
          .gte('recorded_at', utcRange.start.toIso8601String())
          .lte('recorded_at', utcRange.end.toIso8601String())
          .order('recorded_at', ascending: false);
      if (attendanceData.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("No records available in this date range to export.")));
        }
        return;
      }
      final userIds = attendanceData.map((item) => item['user_id']?.toString()).where((id) => id != null).toSet().toList();
      Map<String, Map<String, dynamic>> profileMap = {};
      if (userIds.isNotEmpty) {
        final List<dynamic> profilesData = await supabase
            .from('profiles')
            .select('id, first_name, last_name, role, phone')
            .inFilter('id', userIds);
        for (final profile in profilesData) {
          if (profile['id'] != null) {
            profileMap[profile['id'].toString()] = profile as Map<String, dynamic>;
          }
        }
      }
      final excel = Excel.createExcel();
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }
      final Sheet sheet = excel['Attendance Report'];
      final headers = ['Employee Name', 'Phone', 'Role', 'Date & Time', 'Status', 'GPS Location'];
      sheet.appendRow(headers.map((e) => TextCellValue(e)).toList());
      for (final row in attendanceData) {
        final String? userId = row['user_id']?.toString();
        final profile = userId != null ? profileMap[userId] : null;
        final employeeName = profile != null
            ? "${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}".trim()
            : "Unknown Employee ($userId)";
        final phone = profile?['phone']?.toString() ?? "-";
        final role = profile?['role']?.toString() ?? "-";
        final rawRecordedAt = row['recorded_at'] != null ? DateTime.parse(row['recorded_at']) : DateTime.now();
        final formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(rawRecordedAt);
        final status = row['status']?.toString() ?? "-";
        final lat = row['latitude'];
        final lon = row['longitude'];
        final gps = lat != null && lon != null
            ? "${(lat as num).toStringAsFixed(5)}, ${(lon as num).toStringAsFixed(5)}"
            : "No GPS Data";
        sheet.appendRow([
          TextCellValue(employeeName),
          TextCellValue(phone),
          TextCellValue(role),
          TextCellValue(formattedDate),
          TextCellValue(status),
          TextCellValue(gps),
        ]);
      }
      await _saveAndOpenFile(excel, "Attendance_Report");
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Export failed: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportEmployeeListToExcel() async {
    setState(() => _isExporting = true);
    try {
      final listState = _employeeListKey.currentState;
      if (listState == null || listState.filteredEmployees.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No employee profiles available to export.")));
        return;
      }
      final targetedEmployees = listState.selectedEmployeeIds.isNotEmpty
          ? listState.filteredEmployees.where((e) => listState.selectedEmployeeIds.contains(e['id'].toString())).toList()
          : listState.filteredEmployees;
      final excel = Excel.createExcel();
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }
      final Sheet sheet = excel['Employee Profiles'];
      final headers = ['First Name', 'Last Name', 'Phone', 'Role', 'Cluster', 'Village', 'School'];
      sheet.appendRow(headers.map((e) => TextCellValue(e)).toList());
      for (final emp in targetedEmployees) {
        sheet.appendRow([
          TextCellValue(emp['first_name']?.toString() ?? "-"),
          TextCellValue(emp['last_name']?.toString() ?? "-"),
          TextCellValue(emp['phone']?.toString() ?? "-"),
          TextCellValue(emp['role']?.toString() ?? "-"),
          TextCellValue(emp['cluster']?.toString() ?? "-"),
          TextCellValue(emp['village']?.toString() ?? "-"),
          TextCellValue(emp['school']?.toString() ?? "-"),
        ]);
      }
      await _saveAndOpenFile(excel, "Employee_List");
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Export failed: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _saveAndOpenFile(Excel excel, String baseName) async {
    final bytes = excel.encode();
    if (bytes == null) throw Exception('Failed to generate excel file payload package.');
    final dateSuffix = DateFormat('dd-MM-yyyy').format(DateTime.now());
    final String fileName = "${baseName}_$dateSuffix.xlsx";
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Excel download started.")));
      }
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      await OpenFilex.open(file.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Excel exported successfully: $fileName")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isEmployeeListTabActive = _tabController.index == 1;
    final String labelText = _isExporting ? "Exporting..." : (isEmployeeListTabActive ? "Export Employees" : "Export Attendance");
    return Scaffold(
      appBar: AppBar(
        title: const Text("Employees"),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Column(
            children: [
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: "Employee Attendance"),
                  Tab(text: "Employee List"),
                ],
              ),
              const Padding(padding: EdgeInsets.all(3)),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          EmployeeAttendanceTab(
            range: _selectedRange,
            searchQuery: _searchQuery,
            onRangeChanged: (r) => setState(() => _selectedRange = r),
          ),
          EmployeeListTab(key: _employeeListKey, searchQuery: _searchQuery),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isExporting ? null : (isEmployeeListTabActive ? _exportEmployeeListToExcel : _exportAttendanceToExcel),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        icon: _isExporting
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.file_download),
        label: Text(labelText),
      ),
    );
  }

  DateTimeRange toUtcRange(DateTimeRange range) {
    final start = DateTime(range.start.year, range.start.month, range.start.day).toUtc();

    final end = DateTime(range.end.year, range.end.month, range.end.day).add(const Duration(days: 1)).toUtc();

    return DateTimeRange(start: start, end: end);
  }
}
