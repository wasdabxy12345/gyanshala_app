import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:gyanshala_app/features/admin/presentation/tabs/employee_attendance_records_tab.dart';
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

class _EmployeeHubPageState extends ConsumerState<EmployeeHubPage> {
  String _searchQuery = "";
  bool _isExporting = false;

  DateTimeRange _selectedRange = DateTimeRange(start: DateTime.now().subtract(const Duration(days: 7)), end: DateTime.now());

  Future<void> _exportAttendanceToExcel() async {
    setState(() => _isExporting = true);

    try {
      final supabase = ref.read(supabaseClientProvider);

      final String startIso = _selectedRange.start.toIso8601String();
      final String endIso = _selectedRange.end.toIso8601String();

      // 1. Fetch raw attendance records first
      final List<dynamic> attendanceData = await supabase
          .from('employee_attendance')
          .select('recorded_at, status, latitude, longitude, user_id')
          .gte('recorded_at', startIso)
          .lte('recorded_at', endIso)
          .order('recorded_at', ascending: false);

      if (attendanceData.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("No records available in this date range to export.")));
        }
        setState(() => _isExporting = false);
        return;
      }

      // 2. Extract unique user IDs to fetch their corresponding profiles
      final userIds = attendanceData.map((item) => item['user_id']?.toString()).where((id) => id != null).toSet().toList();

      Map<String, Map<String, dynamic>> profileMap = {};

      if (userIds.isNotEmpty) {
        // 3. Query profiles matching those user IDs
        // 3. Query profiles matching those user IDs
        final List<dynamic> profilesData = await supabase
            .from('profiles')
            .select('id, first_name, last_name, role, phone')
            .inFilter('id', userIds); // <-- FIXED: Changed from .in_() to .inFilter()

        // Map them by 'id' for O(1) fast lookup later
        for (final profile in profilesData) {
          if (profile['id'] != null) {
            profileMap[profile['id'].toString()] = profile as Map<String, dynamic>;
          }
        }
      }

      // 4. Initialize Excel generation
      final excel = Excel.createExcel();
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }
      final Sheet sheet = excel['Attendance Report'];

      final headers = ['Employee Name', 'Phone', 'Role', 'Date & Time', 'Status', 'GPS Location'];
      sheet.appendRow(headers.map((e) => TextCellValue(e)).toList());

      // 5. Merge datasets and populate excel sheet rows
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

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Failed to generate excel file package output.');

      final startDateStr = DateFormat('dd-MM-yyyy').format(_selectedRange.start);
      final endDateStr = DateFormat('dd-MM-yyyy').format(_selectedRange.end);
      final String fileName = "Attendance_Report_[${startDateStr}_to_${endDateStr}].xlsx";
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Export failed: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Employees"),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(50),
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: "Employee Attendance"),
                    Tab(text: "Employee List"),
                  ],
                ),
                Padding(padding: const EdgeInsets.all(8.0)),
              ],
            ),
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            EmployeeAttendanceRecordsTab(
              range: _selectedRange,
              searchQuery: _searchQuery,
              onRangeChanged: (r) => setState(() => _selectedRange = r),
            ),
            EmployeeListTab(searchQuery: _searchQuery),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _isExporting ? null : _exportAttendanceToExcel,
          backgroundColor: AppTheme.primaryBlue,
          foregroundColor: Colors.white,
          icon: _isExporting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.file_download),
          label: Text(_isExporting ? "Exporting..." : "Export Excel"),
        ),
      ),
    );
  }
}
