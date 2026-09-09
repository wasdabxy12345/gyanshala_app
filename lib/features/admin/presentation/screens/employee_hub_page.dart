// added special date selection functionality

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/models/user_role.dart';
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
      if (!_tabController.indexIsChanging) setState(() {});
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
      if (_tabController.index == 0)
        await _attendanceTabKey.currentState?.exportCurrentTable();
      else
        await _employeeListKey.currentState?.exportExcel();
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
                if (value == 'export')
                  _triggerExportPipeline();
                else if (value == 'timing_settings')
                  _showTimingSettingsDialog();
                else if (value == 'special_date')
                  showDialog(context: context, builder: (context) => const _SpecialDatesManagementDialog());
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
                const PopupMenuItem<String>(
                  value: 'special_date',
                  child: Row(
                    children: [
                      Icon(Icons.edit_calendar, size: 20, color: Colors.black54),
                      SizedBox(width: 10),
                      Text('Manage Special Dates'),
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

class _SpecialDatesManagementDialog extends ConsumerStatefulWidget {
  const _SpecialDatesManagementDialog();

  @override
  ConsumerState<_SpecialDatesManagementDialog> createState() => _SpecialDatesManagementDialogState();
}

class _SpecialDatesManagementDialogState extends ConsumerState<_SpecialDatesManagementDialog> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _tableRows = [];
  List<Map<String, dynamic>> _clusters = [];
  List<Map<String, dynamic>> _villages = [];
  List<Map<String, dynamic>> _schools = [];

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await _loadMetadata();
    await _loadSpecialDates();
  }

  Future<void> _loadMetadata() async {
    final supabase = ref.read(supabaseClientProvider);
    try {
      final clustersData = await supabase.from('clusters').select('id, name');
      final villagesData = await supabase.from('villages').select('id, name');
      final schoolsData = await supabase.from('schools').select('id, name');
      setState(() {
        _clusters = List<Map<String, dynamic>>.from(clustersData);
        _villages = List<Map<String, dynamic>>.from(villagesData);
        _schools = List<Map<String, dynamic>>.from(schoolsData);
      });
    } catch (e) {
      debugPrint("Error loading location metadata: $e");
    }
  }

  Future<void> _loadSpecialDates() async {
    setState(() => _isLoading = true);
    final supabase = ref.read(supabaseClientProvider);
    try {
      final data = await supabase
          .from('special_dates')
          .select('''
            id,
            start_date,
            end_date,
            type,
            roles,
            special_dates_locations(cluster_id, village_id, school_id)
          ''')
          .order('start_date', ascending: false);

      setState(() {
        _tableRows = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading special dates: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteSpecialDate(String id) async {
    final supabase = ref.read(supabaseClientProvider);
    try {
      await supabase.from('special_dates').delete().eq('id', id);
      _loadSpecialDates();
    } catch (e) {
      debugPrint("Error deleting special date: $e");
    }
  }

  String _formatLocationScope(List<dynamic>? locations) {
    if (locations == null || locations.isEmpty) return "Global (All Locations)";

    final clusterMap = {for (var c in _clusters) c['id'].toString(): c['name'].toString()};
    final villageMap = {for (var v in _villages) v['id'].toString(): v['name'].toString()};
    final schoolMap = {for (var s in _schools) s['id'].toString(): s['name'].toString()};

    List<String> clusterNames = [];
    List<String> villageNames = [];
    List<String> schoolNames = [];

    for (var loc in locations) {
      if (loc['cluster_id'] != null) {
        final name = clusterMap[loc['cluster_id'].toString()];
        if (name != null) clusterNames.add(name);
      } else if (loc['village_id'] != null) {
        final name = villageMap[loc['village_id'].toString()];
        if (name != null) villageNames.add(name);
      } else if (loc['school_id'] != null) {
        final name = schoolMap[loc['school_id'].toString()];
        if (name != null) schoolNames.add(name);
      } else
        return "Global (All Locations)";
    }

    List<String> resultParts = [];
    if (clusterNames.isNotEmpty) resultParts.add("Cluster: ${clusterNames.join(', ')}");

    if (villageNames.isNotEmpty) resultParts.add("Village: ${villageNames.join(', ')}");

    if (schoolNames.isNotEmpty) resultParts.add("School: ${schoolNames.join(', ')}");

    return resultParts.isEmpty ? "Global (All Locations)" : resultParts.join(' | ');
  }

  void _openFormDialog({Map<String, dynamic>? existingRow}) {
    showDialog(
      context: context,
      builder: (context) => _AddEditSpecialDateDialog(
        existingData: existingRow,
        clusters: _clusters,
        villages: _villages,
        schools: _schools,
        onSaved: () => _loadSpecialDates(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("Manage Special Dates", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue, foregroundColor: Colors.white),
            onPressed: () => _openFormDialog(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text("Add Special Date"),
          ),
        ],
      ),
      content: _isLoading
          ? const SizedBox(height: 250, width: 500, child: Center(child: CircularProgressIndicator()))
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
                              label: Text("Date Range", style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            DataColumn(
                              label: Text("Type", style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            DataColumn(
                              label: Text("Roles", style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            DataColumn(
                              label: Text("Location Scope", style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            DataColumn(
                              label: Text("Actions", style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                          rows: _tableRows.map((row) {
                            final roles = row['roles'] as List<dynamic>?;
                            final rolesText = roles == null || roles.isEmpty
                                ? "All Roles"
                                : roles.map((r) => UserRole.fromString(r.toString()).label).join(', ');

                            final locations = row['special_dates_locations'] as List<dynamic>?;
                            final scopeText = _formatLocationScope(locations);
                            final typeText = row['type'] == 'holiday' ? 'Holiday' : 'Atypical Working Day';

                            final formattedStart = DateFormat('dd/MM/yyyy').format(DateTime.parse(row['start_date']));
                            final formattedEnd = DateFormat('dd/MM/yyyy').format(DateTime.parse(row['end_date']));

                            return DataRow(
                              cells: [
                                DataCell(
                                  Text("$formattedStart to $formattedEnd", style: const TextStyle(fontWeight: FontWeight.w500)),
                                ),
                                DataCell(
                                  Chip(
                                    label: Text(typeText, style: const TextStyle(fontSize: 12, color: Colors.white)),
                                    backgroundColor: row['type'] == 'holiday' ? Colors.red.shade400 : Colors.orange.shade700,
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                                DataCell(
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 220),
                                    child: Text(rolesText, overflow: TextOverflow.ellipsis),
                                  ),
                                ),
                                DataCell(
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 250),
                                    child: Text(scopeText, overflow: TextOverflow.ellipsis),
                                  ),
                                ),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: "Edit entry",
                                        icon: const Icon(Icons.edit, color: AppTheme.primaryBlue, size: 20),
                                        onPressed: () => _openFormDialog(existingRow: row),
                                      ),
                                      IconButton(
                                        tooltip: "Delete entry",
                                        icon: const Icon(Icons.delete_forever, color: Colors.red, size: 20),
                                        onPressed: () => _deleteSpecialDate(row['id'].toString()),
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

class _AddEditSpecialDateDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existingData;
  final List<Map<String, dynamic>> clusters;
  final List<Map<String, dynamic>> villages;
  final List<Map<String, dynamic>> schools;
  final VoidCallback onSaved;

  const _AddEditSpecialDateDialog({
    this.existingData,
    required this.clusters,
    required this.villages,
    required this.schools,
    required this.onSaved,
  });

  @override
  ConsumerState<_AddEditSpecialDateDialog> createState() => _AddEditSpecialDateDialogState();
}

class _AddEditSpecialDateDialogState extends ConsumerState<_AddEditSpecialDateDialog> {
  late DateTimeRange _dateRange;
  String _type = 'holiday';

  final List<UserRole> _allRoles = [
    UserRole.shikshaMitra38,
    UserRole.shikshaMitra910,
    UserRole.mentorBV8,
    UserRole.designTeamSS,
    UserRole.designTeamGS,
    UserRole.fieldCoordinator,
  ];
  late Map<UserRole, bool> _selectedRoles;

  String _scopeLevel = 'global';
  final Set<String> _selectedClusterIds = {};
  final Set<String> _selectedVillageIds = {};
  final Set<String> _selectedSchoolIds = {};

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingData != null) {
      final item = widget.existingData!;
      _dateRange = DateTimeRange(start: DateTime.parse(item['start_date']), end: DateTime.parse(item['end_date']));
      _type = item['type'] ?? 'holiday';

      final rolesList = item['roles'] as List<dynamic>?;
      if (rolesList == null || rolesList.isEmpty)
        _selectedRoles = {for (var r in _allRoles) r: true};
      else
        _selectedRoles = {for (var r in _allRoles) r: rolesList.contains(r.name)};

      final locs = item['special_dates_locations'] as List<dynamic>?;
      if (locs != null && locs.isNotEmpty) {
        if (locs.any((l) => l['cluster_id'] != null)) {
          _scopeLevel = 'cluster';
          _selectedClusterIds.addAll(locs.map((l) => l['cluster_id'].toString()).whereType<String>());
        } else if (locs.any((l) => l['village_id'] != null)) {
          _scopeLevel = 'village';
          _selectedVillageIds.addAll(locs.map((l) => l['village_id'].toString()).whereType<String>());
        } else if (locs.any((l) => l['school_id'] != null)) {
          _scopeLevel = 'school';
          _selectedSchoolIds.addAll(locs.map((l) => l['school_id'].toString()).whereType<String>());
        }
      }
    } else {
      _dateRange = DateTimeRange(start: DateTime.now(), end: DateTime.now());
      _selectedRoles = {for (var r in _allRoles) r: true};
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final supabase = ref.read(supabaseClientProvider);

    bool allRolesSelected = _selectedRoles.values.every((v) => v);
    List<String>? rolesPayload = allRolesSelected
        ? null
        : _selectedRoles.entries.where((e) => e.value).map((e) => e.key.name).toList();

    try {
      String specialDateId;
      if (widget.existingData != null) {
        specialDateId = widget.existingData!['id'].toString();
        await supabase
            .from('special_dates')
            .update({
              'start_date': DateFormat('yyyy-MM-dd').format(_dateRange.start),
              'end_date': DateFormat('yyyy-MM-dd').format(_dateRange.end),
              'type': _type,
              'roles': rolesPayload,
            })
            .eq('id', specialDateId);

        await supabase.from('special_dates_locations').delete().eq('special_dates_id', specialDateId);
      } else {
        final dateRes = await supabase
            .from('special_dates')
            .insert({
              'start_date': DateFormat('yyyy-MM-dd').format(_dateRange.start),
              'end_date': DateFormat('yyyy-MM-dd').format(_dateRange.end),
              'type': _type,
              'roles': rolesPayload,
            })
            .select('id')
            .single();

        specialDateId = dateRes['id'].toString();
      }

      List<Map<String, dynamic>> locationRows = [];
      if (_scopeLevel == 'global')
        locationRows.add({'special_dates_id': specialDateId, 'cluster_id': null, 'village_id': null, 'school_id': null});
      else if (_scopeLevel == 'cluster')
        for (var id in _selectedClusterIds)
          locationRows.add({'special_dates_id': specialDateId, 'cluster_id': id, 'village_id': null, 'school_id': null});
      else if (_scopeLevel == 'village')
        for (var id in _selectedVillageIds)
          locationRows.add({'special_dates_id': specialDateId, 'cluster_id': null, 'village_id': id, 'school_id': null});
      else if (_scopeLevel == 'school')
        for (var id in _selectedSchoolIds)
          locationRows.add({'special_dates_id': specialDateId, 'cluster_id': null, 'village_id': null, 'school_id': id});

      if (locationRows.isNotEmpty) {
        await supabase.from('special_dates_locations').insert(locationRows);
      }

      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint("Error saving special date: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingData != null;
    return AlertDialog(
      title: Text(isEditing ? "Edit Special Date Exception" : "Create Special Date Exception"),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Date Range", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2030),
                    initialDateRange: _dateRange,
                  );
                  if (picked != null) setState(() => _dateRange = picked);
                },
                icon: const Icon(Icons.date_range),
                label: Text(
                  "${DateFormat('dd/MM/yyyy').format(_dateRange.start)} - ${DateFormat('dd/MM/yyyy').format(_dateRange.end)}",
                ),
              ),
              const SizedBox(height: 16),
              const Text("Exception Type", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.all(10)),
                items: const [
                  DropdownMenuItem(value: 'holiday', child: Text("Holiday (Non-working)")),
                  DropdownMenuItem(value: 'atypical_work_day', child: Text("Atypical Working Day (Remote/Camp)")),
                ],
                onChanged: (val) => setState(() => _type = val ?? 'holiday'),
              ),
              const SizedBox(height: 16),
              const Text("Applicable Roles", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8.0,
                runSpacing: 0.0,
                children: _allRoles.map((role) {
                  return FilterChip(
                    label: Text(role.label),
                    selected: _selectedRoles[role]!,
                    onSelected: (selected) {
                      setState(() => _selectedRoles[role] = selected);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text("Location Scope Level", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _scopeLevel,
                decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.all(10)),
                items: const [
                  DropdownMenuItem(value: 'global', child: Text("Global (All Locations)")),
                  DropdownMenuItem(value: 'cluster', child: Text("Cluster(s)")),
                  DropdownMenuItem(value: 'village', child: Text("Village(s)")),
                  DropdownMenuItem(value: 'school', child: Text("School(s)")),
                ],
                onChanged: (val) => setState(() => _scopeLevel = val ?? 'global'),
              ),
              const SizedBox(height: 16),
              if (_scopeLevel == 'cluster') ...[
                const Text("Select Clusters", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                SizedBox(
                  height: 120,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ListView.builder(
                      itemCount: widget.clusters.length,
                      itemBuilder: (context, index) {
                        final c = widget.clusters[index];
                        final id = c['id'].toString();
                        final isSelected = _selectedClusterIds.contains(id);
                        return CheckboxListTile(
                          title: Text(c['name'].toString()),
                          value: isSelected,
                          onChanged: (val) {
                            setState(() {
                              if (val == true)
                                _selectedClusterIds.add(id);
                              else
                                _selectedClusterIds.remove(id);
                            });
                          },
                        );
                      },
                    ),
                  ),
                ),
              ] else if (_scopeLevel == 'village') ...[
                const Text("Select Villages", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                SizedBox(
                  height: 120,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ListView.builder(
                      itemCount: widget.villages.length,
                      itemBuilder: (context, index) {
                        final v = widget.villages[index];
                        final id = v['id'].toString();
                        final isSelected = _selectedVillageIds.contains(id);
                        return CheckboxListTile(
                          title: Text(v['name'].toString()),
                          value: isSelected,
                          onChanged: (val) {
                            setState(() {
                              if (val == true)
                                _selectedVillageIds.add(id);
                              else
                                _selectedVillageIds.remove(id);
                            });
                          },
                        );
                      },
                    ),
                  ),
                ),
              ] else if (_scopeLevel == 'school') ...[
                const Text("Select Schools", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                SizedBox(
                  height: 120,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ListView.builder(
                      itemCount: widget.schools.length,
                      itemBuilder: (context, index) {
                        final s = widget.schools[index];
                        final id = s['id'].toString();
                        final isSelected = _selectedSchoolIds.contains(id);
                        return CheckboxListTile(
                          title: Text(s['name'].toString()),
                          value: isSelected,
                          onChanged: (val) {
                            setState(() {
                              if (val == true)
                                _selectedSchoolIds.add(id);
                              else
                                _selectedSchoolIds.remove(id);
                            });
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue, foregroundColor: Colors.white),
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(isEditing ? "Apply Update" : "Save Special Date"),
        ),
      ],
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
        if (!hasUniversal) fetchedRows.add(WorkHoursRowData(role: systemRole));
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

                        if (!isCreatingException && rowData.id != null) payload['id'] = rowData.id;

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
