import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:gyanshala_app/features/admin/presentation/tabs/employee_attendance_tab.dart';
import 'package:gyanshala_app/features/admin/presentation/tabs/employees_list_tab.dart';
import 'package:intl/intl.dart';

class EmployeeHubPage extends ConsumerStatefulWidget {
  const EmployeeHubPage({super.key});
  @override
  ConsumerState<EmployeeHubPage> createState() => _EmployeeHubPageState();
}

class _EmployeeHubPageState extends ConsumerState<EmployeeHubPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final String _searchQuery = "";
  bool _isExporting = false;

  DateTimeRange _selectedRange = DateTimeRange(
    start: DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1)),
    end: DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1)).add(const Duration(days: 6)),
  );

  final GlobalKey<EmployeeAttendanceTabState> _attendanceTabKey = GlobalKey<EmployeeAttendanceTabState>();
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

  Future<void> _triggerExportPipeline() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    try {
      if (_tabController.index == 0) {
        await _attendanceTabKey.currentState?.exportCurrentTable();
      } else {
        await _employeeListKey.currentState?.exportExcel();
      }
    } catch (e) {
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showTimingSettingsDialog() {
    showDialog(context: context, builder: (context) => const _TimingSettingsOverlay());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Employees"),
        actions: [
          if (_isExporting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(color: AppTheme.primaryBlue, strokeWidth: 2),
              ),
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'export') {
                  _triggerExportPipeline();
                } else if (value == 'timing_settings') {
                  _showTimingSettingsDialog();
                }
              },
              itemBuilder: (BuildContext context) => [
                const PopupMenuItem<String>(
                  value: 'export',
                  child: Row(
                    children: [
                      Icon(Icons.download, size: 20, color: Colors.black54),
                      SizedBox(width: 10),
                      Text("Export to excel"),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'timing_settings',
                  child: Row(
                    children: [
                      Icon(Icons.access_time_filled, size: 20, color: Colors.black54),
                      SizedBox(width: 10),
                      Text("Work Timing Settings"),
                    ],
                  ),
                ),
              ],
            ),
        ],
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
            key: _attendanceTabKey,
            range: _selectedRange,
            searchQuery: _searchQuery,
            onRangeChanged: (r) => setState(() => _selectedRange = r),
          ),
          EmployeeListTab(key: _employeeListKey, searchQuery: _searchQuery),
        ],
      ),
    );
  }
}

class _PolicyRowData {
  final String role;
  TimeOfDay startTime;
  TimeOfDay endTime;
  int leewayLate;
  int leewayEarly;
  String updatedBy;
  String updatedAt;

  _PolicyRowData({
    required this.role,
    this.startTime = const TimeOfDay(hour: 0, minute: 0),
    this.endTime = const TimeOfDay(hour: 0, minute: 0),
    this.leewayLate = 0,
    this.leewayEarly = 0,
    this.updatedBy = "-",
    this.updatedAt = "-",
  });
}

class _TimingSettingsOverlay extends ConsumerStatefulWidget {
  const _TimingSettingsOverlay();

  @override
  ConsumerState<_TimingSettingsOverlay> createState() => _TimingSettingsOverlayState();
}

class _TimingSettingsOverlayState extends ConsumerState<_TimingSettingsOverlay> {
  bool _isLoading = true;
  List<_PolicyRowData> _tableRows = [];

  final List<String> _systemRoles = ['Shiksha Mitra (3-8)', 'Shiksha Mitra (9-10)', 'Mentor (BV-8)'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAllWorkPolicies());
  }

  TimeOfDay _parseTime(String? timeStr) {
    if (timeStr == null) return const TimeOfDay(hour: 0, minute: 0);
    try {
      final parts = timeStr.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return const TimeOfDay(hour: 0, minute: 0);
    }
  }

  Future<void> _loadAllWorkPolicies() async {
    setState(() => _isLoading = true);
    final supabase = ref.read(supabaseClientProvider);

    try {
      final List<dynamic> data = await supabase.from('role_work_policies').select();
      final List<dynamic> profilesData = await supabase.from('profiles').select('id, first_name, last_name');
      final Map<String, String> userNamesMap = {
        for (var p in profilesData) p['id'].toString(): "${p['first_name'] ?? ''} ${p['last_name'] ?? ''}".trim(),
      };

      final List<_PolicyRowData> fetchedRows = [];

      for (String systemRole in _systemRoles) {
        final Map<String, dynamic>? existingRecord = data.cast<Map<String, dynamic>?>().firstWhere(
          (element) => element?['role'] == systemRole,
          orElse: () => null,
        );

        if (existingRecord != null) {
          final updaterUuid = existingRecord['updated_by']?.toString();
          String formattedDate = "-";

          if (existingRecord['updated_at'] != null) {
            final localDate = DateTime.parse(existingRecord['updated_at'].toString()).toLocal();
            formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(localDate);
          }

          fetchedRows.add(
            _PolicyRowData(
              role: systemRole,
              startTime: _parseTime(existingRecord['start_time']?.toString()),
              endTime: _parseTime(existingRecord['end_time']?.toString()),
              leewayLate: existingRecord['leeway_late_minutes'] ?? 0,
              leewayEarly: existingRecord['leeway_early_minutes'] ?? 0,
              updatedBy: userNamesMap[updaterUuid] ?? (updaterUuid ?? "-"),
              updatedAt: formattedDate,
            ),
          );
        } else {
          fetchedRows.add(_PolicyRowData(role: systemRole));
        }
      }

      setState(() {
        _tableRows = fetchedRows;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  String _formatTime(TimeOfDay time) {
    final String hour = time.hour.toString().padLeft(2, '0');
    final String minute = time.minute.toString().padLeft(2, '0');
    return "$hour:$minute:00";
  }

  void _editRowPolicy(_PolicyRowData rowData) {
    final lateController = TextEditingController(text: rowData.leewayLate.toString());
    final earlyController = TextEditingController(text: rowData.leewayEarly.toString());
    TimeOfDay localStart = rowData.startTime;
    TimeOfDay localEnd = rowData.endTime;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text("Edit Rules: ${rowData.role}", style: const TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        await _selectTime(context, localStart, (t) {
                          setModalState(() => localStart = t);
                        });
                      },
                      child: Text("Start: ${localStart.format(context)}"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        await _selectTime(context, localEnd, (t) {
                          setModalState(() => localEnd = t);
                        });
                      },
                      child: Text("End: ${localEnd.format(context)}"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: lateController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Late Mins", border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: earlyController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Early Mins", border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue, foregroundColor: Colors.white),
              onPressed: () async {
                final supabase = ref.read(supabaseClientProvider);
                final currentAdminId = supabase.auth.currentUser?.id;

                try {
                  await supabase.from('role_work_policies').upsert({
                    'role': rowData.role,
                    'start_time': _formatTime(localStart),
                    'end_time': _formatTime(localEnd),
                    'leeway_late_minutes': int.tryParse(lateController.text.trim()) ?? 0,
                    'leeway_early_minutes': int.tryParse(earlyController.text.trim()) ?? 0,
                    'updated_at': DateTime.now().toUtc().toIso8601String(),
                    'updated_by': currentAdminId,
                  });
                  if (context.mounted) Navigator.pop(context);
                  _loadAllWorkPolicies();
                } catch (_) {}
              },
              child: const Text("Apply Updates"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Role Work Policies Manager"),
      content: _isLoading
          ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                  columns: const [
                    DataColumn(
                      label: Text("Role", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    DataColumn(
                      label: Text("Start Time", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    DataColumn(
                      label: Text("End Time", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    DataColumn(
                      label: Text("Start Leeway", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    DataColumn(
                      label: Text("End Leeway", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    DataColumn(
                      label: Text("Modified By", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    DataColumn(
                      label: Text("Modified At", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    DataColumn(
                      label: Text("Action", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                  rows: _tableRows.map((row) {
                    return DataRow(
                      cells: [
                        DataCell(Text(row.role, style: const TextStyle(fontWeight: FontWeight.w500))),
                        DataCell(Text(row.startTime.format(context))),
                        DataCell(Text(row.endTime.format(context))),
                        DataCell(Text("${row.leewayLate} mins")),
                        DataCell(Text("${row.leewayEarly} mins")),
                        DataCell(Text(row.updatedBy, style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
                        DataCell(Text(row.updatedAt, style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
                        DataCell(
                          IconButton(
                            icon: const Icon(Icons.edit, color: AppTheme.primaryBlue, size: 20),
                            onPressed: () => _editRowPolicy(row),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close Panel"))],
    );
  }

  Future<void> _selectTime(BuildContext context, TimeOfDay initialTime, Function(TimeOfDay) onTimePicked) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppTheme.primaryBlue,
              onPrimary: Colors.white,
              tertiaryContainer: AppTheme.primaryBlue.withAlpha(40),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      onTimePicked(picked);
    }
  }
}
