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

class WorkHoursRowData {
  final String? id;
  final String role;
  final String? schoolId;
  final String? schoolName;
  TimeOfDay startTime;
  TimeOfDay endTime;
  int leewayLate;
  int leewayEarly;
  String updatedBy;
  String updatedAt;

  WorkHoursRowData({
    this.id,
    required this.role,
    this.schoolId,
    this.schoolName,
    this.startTime = const TimeOfDay(hour: 0, minute: 0),
    this.endTime = const TimeOfDay(hour: 0, minute: 0),
    this.leewayLate = 0,
    this.leewayEarly = 0,
    this.updatedBy = "-",
    this.updatedAt = "-",
  });
  bool get isUniversal => schoolId == null;
}

class _TimingSettingsOverlay extends ConsumerStatefulWidget {
  const _TimingSettingsOverlay();

  @override
  ConsumerState<_TimingSettingsOverlay> createState() => _TimingSettingsOverlayState();
}

class _TimingSettingsOverlayState extends ConsumerState<_TimingSettingsOverlay> {
  bool _isLoading = true;
  List<WorkHoursRowData> _tableRows = [];
  List<Map<String, dynamic>> _allSchools = [];

  final List<String> _systemRoles = [
    'Shiksha Mitra (3-8)',
    'Shiksha Mitra (9-10)',
    'Mentor (BV-8)',
    'designTeamSS',
    'designTeamGS',
    'fieldCoordinator',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeData());
  }

  Future<void> _initializeData() async {
    await _loadSchools();
    await _loadAllWorkHours();
  }

  Future<void> _loadSchools() async {
    final supabase = ref.read(supabaseClientProvider);
    try {
      final data = await supabase.from('schools').select('id, name').order('name');
      _allSchools = List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint("Error loading schools: $e");
    }
  }

  TimeOfDay _parseTimeWithZone(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return const TimeOfDay(hour: 0, minute: 0);
    try {
      final timePart = timeStr.split('+')[0].split('-')[0];
      final parts = timePart.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return const TimeOfDay(hour: 0, minute: 0);
    }
  }

  String _formatTimeWithZone(TimeOfDay time) {
    final String hour = time.hour.toString().padLeft(2, '0');
    final String minute = time.minute.toString().padLeft(2, '0');
    final DateTime now = DateTime.now();
    final Duration offset = now.timeZoneOffset;
    final String sign = offset.isNegative ? "-" : "+";
    final String offsetHours = offset.inHours.abs().toString().padLeft(2, '0');
    final String offsetMins = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');

    return "$hour:$minute:00$sign$offsetHours:$offsetMins";
  }

  Future<void> _loadAllWorkHours() async {
    setState(() => _isLoading = true);
    final supabase = ref.read(supabaseClientProvider);
    try {
      final List<dynamic> data = await supabase.from('work_hours').select();
      final List<dynamic> profilesData = await supabase.from('profiles').select('id, first_name, last_name');

      final Map<String, String> userNamesMap = {
        for (var p in profilesData) p['id'].toString(): "${p['first_name'] ?? ''} ${p['last_name'] ?? ''}".trim(),
      };

      final Map<String, String> schoolNamesMap = {for (var s in _allSchools) s['id'].toString(): s['name'].toString()};

      final List<WorkHoursRowData> fetchedRows = [];

      for (var row in data) {
        final updaterUuid = row['updated_by']?.toString();
        String formattedDate = "-";
        if (row['updated_at'] != null) {
          final localDate = DateTime.parse(row['updated_at'].toString()).toLocal();
          formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(localDate);
        }

        final schId = row['school_id']?.toString();

        fetchedRows.add(
          WorkHoursRowData(
            id: row['id']?.toString(),
            role: row['role']?.toString() ?? '',
            schoolId: schId,
            schoolName: schId != null ? schoolNamesMap[schId] : null,
            startTime: _parseTimeWithZone(row['start_time']?.toString()),
            endTime: _parseTimeWithZone(row['end_time']?.toString()),
            leewayLate: row['leeway_late_minutes'] ?? 0,
            leewayEarly: row['leeway_early_minutes'] ?? 0,
            updatedBy: userNamesMap[updaterUuid] ?? (updaterUuid ?? "-"),
            updatedAt: formattedDate,
          ),
        );
      }

      for (String systemRole in _systemRoles) {
        bool hasUniversal = fetchedRows.any((r) => r.role == systemRole && r.isUniversal);
        if (!hasUniversal) {
          fetchedRows.add(WorkHoursRowData(role: systemRole));
        }
      }

      fetchedRows.sort((a, b) {
        if (a.role != b.role) return a.role.compareTo(b.role);
        if (a.isUniversal) return -1;
        if (b.isUniversal) return 1;
        return (a.schoolName ?? '').compareTo(b.schoolName ?? '');
      });

      setState(() {
        _tableRows = fetchedRows;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error pipeline execution: $e");
      setState(() => _isLoading = false);
    }
  }

  void _editOrAddWorkHours(WorkHoursRowData rowData, {bool isCreatingException = false}) {
    final lateController = TextEditingController(text: isCreatingException ? "0" : rowData.leewayLate.toString());
    final earlyController = TextEditingController(text: isCreatingException ? "0" : rowData.leewayEarly.toString());
    TimeOfDay localStart = rowData.startTime;
    TimeOfDay localEnd = rowData.endTime;
    String? selectedSchoolId = isCreatingException ? null : rowData.schoolId;

    final existingExceptions = _tableRows.where((r) => r.role == rowData.role && !r.isUniversal).map((r) => r.schoolId).toSet();
    final availableSchoolsForException = _allSchools.where((s) => !existingExceptions.contains(s['id'].toString())).toList();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text(
            isCreatingException ? "Add Exception for ${rowData.role}" : "Edit Work Hours: ${rowData.role}",
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isCreatingException) ...[
                  DropdownButtonFormField<String>(
                    initialValue: selectedSchoolId,
                    hint: const Text("Select Exception School"),
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.all(10)),
                    items: availableSchoolsForException.map((sch) {
                      return DropdownMenuItem<String>(value: sch['id'].toString(), child: Text(sch['name'].toString()));
                    }).toList(),
                    onChanged: (val) => setModalState(() => selectedSchoolId = val),
                  ),
                  const SizedBox(height: 12),
                ] else if (!rowData.isUniversal) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                    child: Text(
                      "Exception Target School: ${rowData.schoolName}",
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showTimePicker(context: context, initialTime: localStart);
                          if (picked != null) setModalState(() => localStart = picked);
                        },
                        child: Text("Start: ${localStart.format(context)}"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showTimePicker(context: context, initialTime: localEnd);
                          if (picked != null) setModalState(() => localEnd = picked);
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
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue, foregroundColor: Colors.white),
              onPressed: (isCreatingException && selectedSchoolId == null)
                  ? null
                  : () async {
                      final supabase = ref.read(supabaseClientProvider);
                      final currentAdminId = supabase.auth.currentUser?.id;

                      try {
                        final payload = {
                          'role': rowData.role,
                          'school_id': selectedSchoolId,
                          'start_time': _formatTimeWithZone(localStart),
                          'end_time': _formatTimeWithZone(localEnd),
                          'leeway_late_minutes': int.tryParse(lateController.text.trim()) ?? 0,
                          'leeway_early_minutes': int.tryParse(earlyController.text.trim()) ?? 0,
                          'updated_at': DateTime.now().toUtc().toIso8601String(),
                          'updated_by': currentAdminId,
                        };

                        if (!isCreatingException && rowData.id != null) {
                          payload['id'] = rowData.id;
                        }

                        await supabase.from('work_hours').upsert(payload);

                        if (context.mounted) Navigator.pop(context);
                        _loadAllWorkHours();
                      } catch (e) {
                        debugPrint("Error upserting configuration: $e");
                      }
                    },
              child: const Text("Apply Update"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteException(String id) async {
    final supabase = ref.read(supabaseClientProvider);
    try {
      await supabase.from('work_hours').delete().eq('id', id);
      _loadAllWorkHours();
    } catch (e) {
      debugPrint("Could not drop explicit structural Work Hours: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text("Role & School Work Hours Management")],
      ),
      content: _isLoading
          ? const SizedBox(height: 250, width: 400, child: Center(child: CircularProgressIndicator()))
          : SizedBox(
              width: MediaQuery.of(context).size.width * 0.85,
              height: MediaQuery.of(context).size.height * 0.6,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                          columns: const [
                            DataColumn(
                              label: Text("Role / Scope", style: TextStyle(fontWeight: FontWeight.bold)),
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
                              label: Text("Actions", style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                          rows: _tableRows.map((row) {
                            return DataRow(
                              cells: [
                                DataCell(
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(row.role, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      Text(
                                        row.isUniversal ? "Universal Default" : "Exception: ${row.schoolName}",
                                        style: TextStyle(
                                          color: row.isUniversal ? Colors.teal : Colors.deepOrange,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                DataCell(Text(row.startTime.format(context))),
                                DataCell(Text(row.endTime.format(context))),
                                DataCell(Text("${row.leewayLate} mins")),
                                DataCell(Text("${row.leewayEarly} mins")),
                                DataCell(Text(row.updatedBy, style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
                                DataCell(Text(row.updatedAt, style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: "Edit details",
                                        icon: const Icon(Icons.edit, color: AppTheme.primaryBlue, size: 20),
                                        onPressed: () => _editOrAddWorkHours(row),
                                      ),
                                      if (row.isUniversal)
                                        IconButton(
                                          tooltip: "Create custom school exception",
                                          icon: const Icon(Icons.add_location_alt, color: Colors.green, size: 20),
                                          onPressed: () => _editOrAddWorkHours(row, isCreatingException: true),
                                        )
                                      else
                                        IconButton(
                                          tooltip: "Remove school exception rule",
                                          icon: const Icon(Icons.delete_forever, color: Colors.red, size: 20),
                                          onPressed: () => _deleteException(row.id!),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close Panel"))],
    );
  }
}
