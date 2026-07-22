import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProcessedRequest {
  final Map<String, dynamic> rawData;
  final String id;
  final String fullName;
  final String phone;
  final String role;
  final String gender;
  final String qualification;
  final String cluster;
  final String village;
  final String school;
  final DateTime date;
  final String dateFormatted;
  final String timeFormatted;

  final String searchKey;

  ProcessedRequest({
    required this.rawData,
    required this.id,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.gender,
    required this.qualification,
    required this.cluster,
    required this.village,
    required this.school,
    required this.date,
    required this.dateFormatted,
    required this.timeFormatted,
    required this.searchKey,
  });

  factory ProcessedRequest.fromRaw(Map<String, dynamic> req, bool isProfileTable) {
    final firstName = req['first_name']?.toString() ?? '';
    final lastName = req['last_name']?.toString() ?? '';
    final fullName = '$firstName $lastName'.trim();
    final phone = req['phone']?.toString() ?? '-';
    final role = req['role']?.toString() ?? '-';
    final gender = req['gender']?.toString() ?? '-';
    final qualification = req['qualification']?.toString() ?? '-';

    final loc = _extractLocationNames(req);
    final cluster = loc['cluster']!;
    final village = loc['village']!;
    final school = loc['school']!;

    final dateField = isProfileTable ? req['updated_at'] : req['created_at'];
    final parsedDate = _parseDateTimeSafely(dateField);
    final dateFormatted = DateFormat('dd MMM yyyy').format(parsedDate);
    final timeFormatted = DateFormat('hh:mm a').format(parsedDate);

    final searchKey = '$fullName $phone $role $gender $cluster $village $school $qualification $timeFormatted'.toLowerCase();

    return ProcessedRequest(
      rawData: req,
      id: req['id']?.toString() ?? '',
      fullName: fullName,
      phone: phone,
      role: role,
      gender: gender,
      qualification: qualification,
      cluster: cluster,
      village: village,
      school: school,
      date: parsedDate,
      dateFormatted: dateFormatted,
      timeFormatted: timeFormatted,
      searchKey: searchKey,
    );
  }

  static DateTime _parseDateTimeSafely(dynamic dateValue) {
    if (dateValue == null) return DateTime.now();
    String dateStr = dateValue.toString().trim();
    if (dateStr.isEmpty) return DateTime.now();
    if (!dateStr.contains('Z') && !dateStr.contains('+') && !dateStr.endsWith('Z')) {
      if (dateStr.contains(' ') && !dateStr.contains('T')) dateStr = dateStr.replaceFirst(' ', 'T');
      dateStr = '${dateStr}Z';
    }
    return DateTime.tryParse(dateStr)?.toLocal() ?? DateTime.now();
  }

  static Map<String, String> _extractLocationNames(Map<String, dynamic> row) {
    final requestSchoolsList = row['signup_request_schools'] as List<dynamic>?;
    final profileSchoolsList = row['profile_schools'] as List<dynamic>?;
    final schoolsRelations = [...(requestSchoolsList ?? []), ...(profileSchoolsList ?? [])];

    final List<Map<String, String>> structuralList = [];

    for (final relation in schoolsRelations) {
      final school = relation['schools'] as Map<String, dynamic>?;
      if (school == null) continue;

      final schoolName = school['name']?.toString() ?? "-";
      final village = school['villages'] as Map<String, dynamic>?;
      final villageName = village?['name']?.toString() ?? "-";
      final cluster = village?['clusters'] as Map<String, dynamic>?;
      final clusterName = cluster?['name']?.toString() ?? "-";

      structuralList.add({'cluster': clusterName, 'village': villageName, 'school': schoolName});
    }

    structuralList.sort((a, b) {
      int clusterCompare = a['cluster']!.compareTo(b['cluster']!);
      if (clusterCompare != 0) return clusterCompare;
      int villageCompare = a['village']!.compareTo(b['village']!);
      if (villageCompare != 0) return villageCompare;
      return a['school']!.compareTo(b['school']!);
    });

    final List<String> clusterLines = [];
    final List<String> villageLines = [];
    final List<String> schoolLines = [];

    String lastCluster = "";
    String lastVillage = "";
    bool isFirstRow = true;

    for (final item in structuralList) {
      final currentCluster = item['cluster']!;
      final currentVillage = item['village']!;
      final currentSchool = item['school']!;

      bool isNewCluster = currentCluster != lastCluster;
      bool isNewVillage = currentVillage != lastVillage;
      bool globalBlockChanged = !isFirstRow && (isNewCluster || isNewVillage);

      if (isNewCluster) {
        clusterLines.add(isFirstRow ? currentCluster : "[LINE]$currentCluster");
        lastCluster = currentCluster;
        lastVillage = "";
      } else {
        clusterLines.add(globalBlockChanged ? "[SPACE]" : "");
      }

      if (currentVillage != lastVillage) {
        villageLines.add(isFirstRow ? currentVillage : "[LINE]$currentVillage");
        lastVillage = currentVillage;
      } else {
        villageLines.add(globalBlockChanged ? "[SPACE]" : "");
      }

      schoolLines.add(globalBlockChanged ? "[LINE]$currentSchool" : currentSchool);
      isFirstRow = false;
    }

    if (clusterLines.isEmpty) return {'cluster': '-', 'village': '-', 'school': '-'};

    return {'cluster': clusterLines.join('\n'), 'village': villageLines.join('\n'), 'school': schoolLines.join('\n')};
  }
}

class SignupRequestsScreen extends ConsumerStatefulWidget {
  const SignupRequestsScreen({super.key});

  @override
  ConsumerState<SignupRequestsScreen> createState() => _SignupRequestsScreenState();
}

class _SignupRequestsScreenState extends ConsumerState<SignupRequestsScreen> {
  final GlobalKey<_SignupTableTabViewState> _pendingKey = GlobalKey();
  final GlobalKey<_SignupTableTabViewState> _activeKey = GlobalKey();
  final GlobalKey<_SignupTableTabViewState> _suspendedKey = GlobalKey();

  void _refreshAllTabs() {
    _pendingKey.currentState?.fetchData();
    _activeKey.currentState?.fetchData();
    _suspendedKey.currentState?.fetchData();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Signup Request Management"),
          actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: "Refresh Data", onPressed: _refreshAllTabs)],
          bottom: const TabBar(
            tabs: [
              Tab(text: "Pending Requests"),
              Tab(text: "Active Profiles"),
              Tab(text: "Suspended Profiles"),
            ],
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            SignupTableTabView(key: _pendingKey, statusFilter: 'pending', isProfileTable: false),
            SignupTableTabView(key: _activeKey, statusFilter: 'active', isProfileTable: true),
            SignupTableTabView(key: _suspendedKey, statusFilter: 'suspended', isProfileTable: true),
          ],
        ),
      ),
    );
  }
}

class SignupTableTabView extends ConsumerStatefulWidget {
  final String statusFilter;
  final bool isProfileTable;

  const SignupTableTabView({super.key, required this.statusFilter, required this.isProfileTable});

  @override
  ConsumerState<SignupTableTabView> createState() => _SignupTableTabViewState();
}

class _SignupTableTabViewState extends ConsumerState<SignupTableTabView> {
  bool _isLoading = true;
  bool _isProcessingAction = false;

  final TextEditingController _searchController = TextEditingController();
  int _sortColumnIndex = 8;
  bool _isAscending = false;

  int _currentPage = 0;
  int _rowsPerPage = 50;
  final List<int> _availableRowsPerPage = [25, 50, 100, 200];

  Set<String>? _selectedNameFilters;
  Set<String>? _selectedPhoneFilters;
  Set<String>? _selectedRoleFilters;
  Set<String>? _selectedGenderFilters;
  Set<String>? _selectedClusterFilters;
  Set<String>? _selectedVillageFilters;
  Set<String>? _selectedSchoolFilters;
  Set<String>? _selectedQualificationFilters;
  DateTimeRange? _selectedDateRange;
  Set<String>? _selectedTimeFilters;

  List<ProcessedRequest> _rawRequests = [];
  List<ProcessedRequest> _filteredRequests = [];

  RealtimeChannel? _realtimeChannel;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    fetchData();

    if (widget.statusFilter == 'pending') {
      _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) => fetchData(showLoading: false));
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _pollingTimer?.cancel();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  void _onSearchChanged() {
    _currentPage = 0;
    _applyAllFilters();
  }

  Future<void> fetchData({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() => _isLoading = true);
    }

    final supabase = ref.read(supabaseClientProvider);
    final table = widget.isProfileTable ? 'profiles' : 'signup_requests';
    final column = widget.isProfileTable ? 'account_status' : 'status';

    _setupRealtimeSubscription(table);

    final String junctionSelect = widget.isProfileTable
        ? 'profile_schools ( schools ( name, villages:village_id ( name, clusters:cluster_id (name) ) ) )'
        : 'signup_request_schools ( schools ( name, villages:village_id ( name, clusters:cluster_id (name) ) ) )';

    try {
      final response = await supabase.from(table).select('*, $junctionSelect').eq(column, widget.statusFilter);
      final List<Map<String, dynamic>> rawData = List<Map<String, dynamic>>.from(response as List);

      _rawRequests = rawData.map((e) => ProcessedRequest.fromRaw(e, widget.isProfileTable)).toList();

      if (mounted) {
        await _applyAllFilters();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _setupRealtimeSubscription(String table) {
    _realtimeChannel?.unsubscribe();
    final supabase = ref.read(supabaseClientProvider);
    _realtimeChannel =
        supabase
            .channel('realtime-$table-${widget.statusFilter}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: table,
              callback: (_) => fetchData(showLoading: false),
            )
          ..subscribe();
  }

  Future<void> _applyAllFilters() async {
    await Future.delayed(Duration.zero);
    final query = _searchController.text.toLowerCase().trim();

    final params = FilterParams(
      requests: _rawRequests,
      query: query,
      dateRange: _selectedDateRange,
      names: _selectedNameFilters,
      phones: _selectedPhoneFilters,
      roles: _selectedRoleFilters,
      genders: _selectedGenderFilters,
      clusters: _selectedClusterFilters,
      villages: _selectedVillageFilters,
      schools: _selectedSchoolFilters,
      qualifications: _selectedQualificationFilters,
      times: _selectedTimeFilters,
      sortColumnIndex: _sortColumnIndex,
      isAscending: _isAscending,
    );

    if (kIsWeb) await Future.delayed(const Duration(milliseconds: 16));

    final result = await compute(_filterAndSortInIsolate, params);

    if (mounted)
      setState(() {
        _filteredRequests = result;
      });
  }

  void _applySorting() {
    _filteredRequests.sort((a, b) {
      String valA = "";
      String valB = "";
      switch (_sortColumnIndex) {
        case 0:
          valA = a.fullName;
          valB = b.fullName;
          break;
        case 1:
          valA = a.phone;
          valB = b.phone;
          break;
        case 2:
          valA = a.role;
          valB = b.role;
          break;
        case 3:
          valA = a.gender;
          valB = b.gender;
          break;
        case 4:
          valA = a.cluster;
          valB = b.cluster;
          break;
        case 5:
          valA = a.village;
          valB = b.village;
          break;
        case 6:
          valA = a.school;
          valB = b.school;
          break;
        case 7:
          valA = a.qualification;
          valB = b.qualification;
          break;
        case 8:
        case 9:
          return _isAscending ? a.date.compareTo(b.date) : b.date.compareTo(a.date);
      }
      int compare = valA.toLowerCase().compareTo(valB.toLowerCase());
      return _isAscending ? compare : -compare;
    });
  }

  List<String> _getUniqueValuesForColumn(int columnIndex) {
    final Set<String> values = {};
    for (final req in _rawRequests) {
      switch (columnIndex) {
        case 0:
          values.add(req.fullName);
          break;
        case 1:
          values.add(req.phone);
          break;
        case 2:
          values.add(req.role);
          break;
        case 3:
          values.add(req.gender);
          break;
        case 4:
          values.add(req.cluster);
          break;
        case 5:
          values.add(req.village);
          break;
        case 6:
          values.add(req.school);
          break;
        case 7:
          values.add(req.qualification);
          break;
        case 9:
          values.add(req.timeFormatted);
          break;
      }
    }
    return values.toList()..sort();
  }

  void _onSort(int columnIndex) {
    if (columnIndex == 10) return;
    setState(() {
      if (_sortColumnIndex == columnIndex) {
        _isAscending = !_isAscending;
      } else {
        _sortColumnIndex = columnIndex;
        _isAscending = true;
      }
      _applySorting();
    });
  }

  Future<void> _showFilterMenu(int columnIndex, String label) async {
    final allValues = _getUniqueValuesForColumn(columnIndex);
    Set<String> currentSelection;

    if (columnIndex == 0)
      currentSelection = _selectedNameFilters != null ? Set.from(_selectedNameFilters!) : Set.from(allValues);
    else if (columnIndex == 1)
      currentSelection = _selectedPhoneFilters != null ? Set.from(_selectedPhoneFilters!) : Set.from(allValues);
    else if (columnIndex == 2)
      currentSelection = _selectedRoleFilters != null ? Set.from(_selectedRoleFilters!) : Set.from(allValues);
    else if (columnIndex == 3)
      currentSelection = _selectedGenderFilters != null ? Set.from(_selectedGenderFilters!) : Set.from(allValues);
    else if (columnIndex == 4)
      currentSelection = _selectedClusterFilters != null ? Set.from(_selectedClusterFilters!) : Set.from(allValues);
    else if (columnIndex == 5)
      currentSelection = _selectedVillageFilters != null ? Set.from(_selectedVillageFilters!) : Set.from(allValues);
    else if (columnIndex == 6)
      currentSelection = _selectedSchoolFilters != null ? Set.from(_selectedSchoolFilters!) : Set.from(allValues);
    else if (columnIndex == 7)
      currentSelection = _selectedQualificationFilters != null ? Set.from(_selectedQualificationFilters!) : Set.from(allValues);
    else
      currentSelection = _selectedTimeFilters != null ? Set.from(_selectedTimeFilters!) : Set.from(allValues);

    final dialogSearchController = TextEditingController();
    List<String> filteredValues = List.from(allValues);
    bool isApplying = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text("Filter by $label"),
          content: SizedBox(
            width: 320,
            height: 450,
            child: Column(
              children: [
                TextField(
                  controller: dialogSearchController,
                  decoration: const InputDecoration(hintText: "Search values...", prefixIcon: Icon(Icons.search)),
                  onChanged: (value) {
                    setStateDialog(() {
                      filteredValues = allValues.where((e) => e.toLowerCase().contains(value.toLowerCase())).toList();
                    });
                  },
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  dense: true,
                  value: currentSelection.length == allValues.length,
                  title: const Text("Select All"),
                  onChanged: (checked) {
                    setStateDialog(() {
                      currentSelection = checked == true ? Set.from(allValues) : {};
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
            TextButton(onPressed: isApplying ? null : () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: isApplying
                  ? null
                  : () async {
                      setStateDialog(() => isApplying = true);

                      final noFilter = currentSelection.isEmpty || currentSelection.length == allValues.length;

                      setState(() {
                        if (columnIndex == 0) _selectedNameFilters = noFilter ? null : Set.from(currentSelection);
                        if (columnIndex == 1) _selectedPhoneFilters = noFilter ? null : Set.from(currentSelection);
                        if (columnIndex == 2) _selectedRoleFilters = noFilter ? null : Set.from(currentSelection);
                        if (columnIndex == 3) _selectedGenderFilters = noFilter ? null : Set.from(currentSelection);
                        if (columnIndex == 4) _selectedClusterFilters = noFilter ? null : Set.from(currentSelection);
                        if (columnIndex == 5) _selectedVillageFilters = noFilter ? null : Set.from(currentSelection);
                        if (columnIndex == 6) _selectedSchoolFilters = noFilter ? null : Set.from(currentSelection);
                        if (columnIndex == 7) _selectedQualificationFilters = noFilter ? null : Set.from(currentSelection);
                        if (columnIndex == 9) _selectedTimeFilters = noFilter ? null : Set.from(currentSelection);
                        _currentPage = 0;
                      });

                      await _applyAllFilters();

                      if (ctx.mounted) Navigator.pop(ctx);
                    },
              child: isApplying
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text("Apply"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAction({
    required String id,
    required String targetStatus,
    required bool isProfileTable,
    String? reason,
  }) async {
    setState(() => _isProcessingAction = true);
    final supabase = ref.read(supabaseClientProvider);
    final currentAdminId = supabase.auth.currentUser?.id;

    try {
      if (isProfileTable) {
        await supabase
            .from('profiles')
            .update({
              'account_status': targetStatus,
              'action_reason': reason,
              'actioned_by': currentAdminId,
              'actioned_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', id);
      } else {
        await supabase
            .from('signup_requests')
            .update({'status': targetStatus, 'action_reason': reason, 'actioned_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', id);
      }

      // Local mutations for responsive UI
      _rawRequests.removeWhere((element) => element.id == id);
      await _applyAllFilters();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Successfully updated status to $targetStatus')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingAction = false);
      }
    }
  }

  Future<String?> _showActionReasonDialog({
    required String name,
    required String actionTitle,
    required String explanationText,
    Color confirmButtonColor = Colors.red,
  }) async {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('$actionTitle Account'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(explanationText),
              const SizedBox(height: 16),
              TextFormField(
                controller: reasonController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Reason for $actionTitle',
                  hintText: 'Provide context or justification...',
                  border: const OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Please enter a reason for this action';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(context, reasonController.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: confirmButtonColor, foregroundColor: Colors.white),
            child: Text('Confirm $actionTitle'),
          ),
        ],
      ),
    );
  }

  Widget _buildDateControls() {
    final now = DateTime.now();

    Widget buildWeekControls() => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_left, size: 37),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () async {
            final newEnd = (_selectedDateRange?.start ?? now).subtract(const Duration(days: 1));
            final newStart = newEnd.subtract(const Duration(days: 6));
            setState(() {
              _selectedDateRange = DateTimeRange(start: newStart, end: newEnd);
              _currentPage = 0;
            });
            await _applyAllFilters();
          },
        ),
        Expanded(
          child: _quickBtn("This Week", () async {
            final start = now.subtract(Duration(days: now.weekday - 1));
            final end = start.add(const Duration(days: 6));
            setState(() {
              _selectedDateRange = DateTimeRange(start: start, end: end);
              _currentPage = 0;
            });
            await _applyAllFilters();
          }),
        ),
        IconButton(
          icon: const Icon(Icons.arrow_right, size: 37),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () async {
            final newStart = (_selectedDateRange?.end ?? now).add(const Duration(days: 1));
            final newEnd = newStart.add(const Duration(days: 6));
            setState(() {
              _selectedDateRange = DateTimeRange(start: newStart, end: newEnd);
              _currentPage = 0;
            });
            await _applyAllFilters();
          },
        ),
      ],
    );

    Widget buildMonthControls() => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_left, size: 37),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () async {
            final base = _selectedDateRange?.start ?? now;
            final newMonthEnd = DateTime(base.year, base.month, 0);
            final newMonthStart = DateTime(newMonthEnd.year, newMonthEnd.month, 1);
            setState(() {
              _selectedDateRange = DateTimeRange(start: newMonthStart, end: newMonthEnd);
              _currentPage = 0;
            });
            await _applyAllFilters();
          },
        ),
        Expanded(
          child: _quickBtn("This Month", () async {
            final start = DateTime(now.year, now.month, 1);
            final end = DateTime(now.year, now.month + 1, 0);
            setState(() {
              _selectedDateRange = DateTimeRange(start: start, end: end);
              _currentPage = 0;
            });
            await _applyAllFilters();
          }),
        ),
        IconButton(
          icon: const Icon(Icons.arrow_right, size: 37),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () async {
            final base = _selectedDateRange?.end ?? now;
            final newMonthStart = DateTime(base.year, base.month + 1, 1);
            final newMonthEnd = DateTime(newMonthStart.year, newMonthStart.month + 1, 0);
            setState(() {
              _selectedDateRange = DateTimeRange(start: newMonthStart, end: newMonthEnd);
              _currentPage = 0;
            });
            await _applyAllFilters();
          },
        ),
      ],
    );

    Widget buildDateSelectors() => Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dateInkWell(date: _selectedDateRange?.start, isStart: true),
            const SizedBox(width: 13),
            const Text("to", style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(width: 13),
            _dateInkWell(date: _selectedDateRange?.end, isStart: false),
            if (_selectedDateRange != null) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.clear, color: Colors.redAccent, size: 20),
                onPressed: () async {
                  setState(() {
                    _selectedDateRange = null;
                    _currentPage = 0;
                  });
                  await _applyAllFilters();
                },
              ),
            ],
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 600) {
            return Column(
              children: [
                buildDateSelectors(),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(child: buildWeekControls()),
                    const SizedBox(width: 8),
                    Expanded(child: buildMonthControls()),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: buildWeekControls()),
              buildDateSelectors(),
              Expanded(child: buildMonthControls()),
            ],
          );
        },
      ),
    );
  }

  Widget _quickBtn(String label, VoidCallback action) {
    return TextButton(
      style: TextButton.styleFrom(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 37),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: action,
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _dateInkWell({required DateTime? date, required bool isStart}) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(1970),
          lastDate: DateTime.now(),
        );
        if (picked != null) {
          setState(() {
            if (isStart) {
              _selectedDateRange = DateTimeRange(
                start: picked,
                end: _selectedDateRange?.end ?? picked.add(const Duration(days: 6)),
              );
            } else {
              _selectedDateRange = DateTimeRange(
                start: _selectedDateRange?.start ?? picked.subtract(const Duration(days: 6)),
                end: picked,
              );
            }
            _currentPage = 0;
          });
          await _applyAllFilters();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 13),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.primaryBlue),
          color: Colors.white,
        ),
        child: Text(
          date == null ? (isStart ? "Start Date" : "End Date") : _formatDateWithMonth(date),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
        ),
      ),
    );
  }

  String _formatDateWithMonth(DateTime date) {
    final dayName = DateFormat('EEE').format(date);
    final formatted = DateFormat('dd-MM-yyyy').format(date);
    return '$formatted ($dayName)';
  }

  Widget _buildActionButtons(ProcessedRequest req) {
    if (widget.statusFilter == 'pending') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 32,
            width: 75,
            child: ElevatedButton(
              onPressed: _isProcessingAction
                  ? null
                  : () => _handleAction(id: req.id, targetStatus: 'approved', isProfileTable: false),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
              child: const Text("Approve", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 32,
            width: 75,
            child: ElevatedButton(
              onPressed: _isProcessingAction
                  ? null
                  : () async {
                      final reason = await _showActionReasonDialog(
                        name: req.fullName,
                        actionTitle: 'Reject',
                        explanationText: 'Are you sure you want to reject the signup request for ${req.fullName}?',
                      );
                      if (reason != null) {
                        _handleAction(id: req.id, targetStatus: 'rejected', isProfileTable: false, reason: reason);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
              child: const Text("Reject", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      );
    } else if (widget.statusFilter == 'active') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 32,
            width: 80,
            child: ElevatedButton(
              onPressed: _isProcessingAction
                  ? null
                  : () async {
                      final reason = await _showActionReasonDialog(
                        name: req.fullName,
                        actionTitle: 'Suspend',
                        explanationText: 'Provide a reason to temporarily suspend ${req.fullName}\'s account access.',
                        confirmButtonColor: Colors.orange,
                      );
                      if (reason != null) {
                        _handleAction(id: req.id, targetStatus: 'suspended', isProfileTable: true, reason: reason);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
              child: const Text("Suspend", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 32,
            width: 75,
            child: ElevatedButton(
              onPressed: _isProcessingAction
                  ? null
                  : () async {
                      final reason = await _showActionReasonDialog(
                        name: req.fullName,
                        actionTitle: 'Remove',
                        explanationText: 'Are you completely sure you want to permanently remove ${req.fullName}?',
                      );
                      if (reason != null) {
                        _handleAction(id: req.id, targetStatus: 'removed', isProfileTable: true, reason: reason);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
              child: const Text("Remove", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      );
    } else {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 32,
            width: 90,
            child: ElevatedButton(
              onPressed: _isProcessingAction
                  ? null
                  : () async {
                      final reason = await _showActionReasonDialog(
                        name: req.fullName,
                        actionTitle: 'Unsuspend',
                        explanationText: 'Provide a reason to reinstate ${req.fullName} to active status.',
                        confirmButtonColor: Colors.blue,
                      );
                      if (reason != null) {
                        _handleAction(id: req.id, targetStatus: 'active', isProfileTable: true, reason: reason);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
              child: const Text("Unsuspend", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 32,
            width: 75,
            child: ElevatedButton(
              onPressed: _isProcessingAction
                  ? null
                  : () async {
                      final reason = await _showActionReasonDialog(
                        name: req.fullName,
                        actionTitle: 'Remove',
                        explanationText: 'Permanently remove ${req.fullName}? This action is irreversible.',
                      );
                      if (reason != null) {
                        _handleAction(id: req.id, targetStatus: 'removed', isProfileTable: true, reason: reason);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
              child: const Text("Remove", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final totalRows = _filteredRequests.length;
    final maxPages = (totalRows / _rowsPerPage).ceil();

    if (_currentPage >= maxPages && maxPages > 0) _currentPage = maxPages - 1;

    final int startIdx = _currentPage * _rowsPerPage;
    final int endIdx = (startIdx + _rowsPerPage) > totalRows ? totalRows : (startIdx + _rowsPerPage);

    final paginatedRequests = (_filteredRequests.isEmpty || startIdx >= totalRows)
        ? <ProcessedRequest>[]
        : _filteredRequests.sublist(startIdx, endIdx);

    return Column(
      children: [
        _buildDateControls(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: "Search records...",
              prefixIcon: Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: _filteredRequests.isEmpty
              ? const Center(child: Text("No records match your filters"))
              : SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Table(
                      // Explicit fixed widths prevent UI thread bottlenecks caused by IntrinsicColumnWidth measurements
                      columnWidths: const {
                        0: FixedColumnWidth(160),
                        1: FixedColumnWidth(120),
                        2: FixedColumnWidth(110),
                        3: FixedColumnWidth(90),
                        4: FixedColumnWidth(140),
                        5: FixedColumnWidth(140),
                        6: FixedColumnWidth(160),
                        7: FixedColumnWidth(130),
                        8: FixedColumnWidth(120),
                        9: FixedColumnWidth(100),
                        10: FixedColumnWidth(177),
                      },
                      border: TableBorder(
                        verticalInside: BorderSide(color: Colors.grey.shade300),
                        horizontalInside: BorderSide(color: Colors.grey.shade300, width: 1.0),
                        bottom: BorderSide(color: Colors.grey.shade300),
                        left: BorderSide(color: Colors.grey.shade300),
                        right: BorderSide(color: Colors.grey.shade300),
                      ),
                      children: [
                        TableRow(
                          decoration: BoxDecoration(color: Colors.grey.shade200),
                          children: [
                            _SortableHeader(
                              label: "Full Name",
                              onSort: () => _onSort(0),
                              onFilter: () => _showFilterMenu(0, "Name"),
                              isSorted: _sortColumnIndex == 0,
                              isAscending: _isAscending,
                              hasFilter: _selectedNameFilters != null,
                            ),
                            _SortableHeader(
                              label: "Phone",
                              onSort: () => _onSort(1),
                              onFilter: () => _showFilterMenu(1, "Phone"),
                              isSorted: _sortColumnIndex == 1,
                              isAscending: _isAscending,
                              hasFilter: _selectedPhoneFilters != null,
                            ),
                            _SortableHeader(
                              label: "Role",
                              onSort: () => _onSort(2),
                              onFilter: () => _showFilterMenu(2, "Role"),
                              isSorted: _sortColumnIndex == 2,
                              isAscending: _isAscending,
                              hasFilter: _selectedRoleFilters != null,
                            ),
                            _SortableHeader(
                              label: "Gender",
                              onSort: () => _onSort(3),
                              onFilter: () => _showFilterMenu(3, "Gender"),
                              isSorted: _sortColumnIndex == 3,
                              isAscending: _isAscending,
                              hasFilter: _selectedGenderFilters != null,
                            ),
                            _SortableHeader(
                              label: "Cluster",
                              onSort: () => _onSort(4),
                              onFilter: () => _showFilterMenu(4, "Cluster"),
                              isSorted: _sortColumnIndex == 4,
                              isAscending: _isAscending,
                              hasFilter: _selectedClusterFilters != null,
                            ),
                            _SortableHeader(
                              label: "Village",
                              onSort: () => _onSort(5),
                              onFilter: () => _showFilterMenu(5, "Village"),
                              isSorted: _sortColumnIndex == 5,
                              isAscending: _isAscending,
                              hasFilter: _selectedVillageFilters != null,
                            ),
                            _SortableHeader(
                              label: "School",
                              onSort: () => _onSort(6),
                              onFilter: () => _showFilterMenu(6, "School"),
                              isSorted: _sortColumnIndex == 6,
                              isAscending: _isAscending,
                              hasFilter: _selectedSchoolFilters != null,
                            ),
                            _SortableHeader(
                              label: "Qualification",
                              onSort: () => _onSort(7),
                              onFilter: () => _showFilterMenu(7, "Qualification"),
                              isSorted: _sortColumnIndex == 7,
                              isAscending: _isAscending,
                              hasFilter: _selectedQualificationFilters != null,
                            ),
                            _SortableHeader(
                              label: "Date",
                              onSort: () => _onSort(8),
                              onFilter: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _selectedDateRange?.start ?? DateTime.now(),
                                  firstDate: DateTime(1970),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null) {
                                  setState(() {
                                    _selectedDateRange = DateTimeRange(
                                      start: picked,
                                      end: _selectedDateRange?.end ?? picked.add(const Duration(days: 6)),
                                    );
                                    _currentPage = 0;
                                  });
                                  await _applyAllFilters();
                                }
                              },
                              isSorted: _sortColumnIndex == 8,
                              isAscending: _isAscending,
                              hasFilter: _selectedDateRange != null,
                            ),
                            _SortableHeader(
                              label: "Time",
                              onSort: () => _onSort(9),
                              onFilter: () => _showFilterMenu(9, "Time"),
                              isSorted: _sortColumnIndex == 9,
                              isAscending: _isAscending,
                              hasFilter: _selectedTimeFilters != null,
                            ),
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text("Actions", style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        ...paginatedRequests.map((req) {
                          return TableRow(
                            children: [
                              _DataCell(text: req.fullName, isBold: true),
                              _DataCell(text: req.phone),
                              _DataCell(text: req.role),
                              _DataCell(text: req.gender),
                              _DataCell(text: req.cluster),
                              _DataCell(text: req.village),
                              _DataCell(text: req.school),
                              _DataCell(text: req.qualification),
                              _DataCell(text: req.dateFormatted),
                              _DataCell(text: req.timeFormatted),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                child: _buildActionButtons(req),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ),
        ),

        if (_filteredRequests.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text("Rows per page: "),
                    DropdownButton<int>(
                      items: _availableRowsPerPage.map((e) => DropdownMenuItem<int>(value: e, child: Text("$e"))).toList(),
                      onChanged: (val) async {
                        if (val != null) {
                          setState(() {
                            _rowsPerPage = val;
                            _currentPage = 0;
                          });
                          await _applyAllFilters();
                        }
                      },
                      value: _rowsPerPage,
                      isDense: true,
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text(
                      "Page ${_currentPage + 1} of ${maxPages == 0 ? 1 : maxPages}  •  "
                      "Entries: ${totalRows == 0 ? 0 : startIdx + 1}-$endIdx of $totalRows",
                    ),
                    IconButton(
                      onPressed: _currentPage < maxPages - 1 ? () => setState(() => _currentPage++) : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SortableHeader extends StatelessWidget {
  final String label;
  final VoidCallback onSort;
  final VoidCallback onFilter;
  final bool isSorted;
  final bool isAscending;
  final bool hasFilter;

  const _SortableHeader({
    required this.label,
    required this.onSort,
    required this.onFilter,
    required this.isSorted,
    required this.isAscending,
    required this.hasFilter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onSort,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    isSorted ? (isAscending ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more,
                    size: 13,
                    color: isSorted ? AppTheme.primaryBlue : Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: onFilter,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: hasFilter ? AppTheme.primaryBlue.withAlpha(33) : Colors.transparent),
              child: Icon(Icons.filter_alt, size: 13, color: hasFilter ? AppTheme.primaryBlue : Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  final String text;
  final bool isBold;

  const _DataCell({required this.text, this.isBold = false});

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: lines.map((line) {
        bool drawDivider = line.startsWith("[LINE]");
        bool addLineSpacing = line.startsWith("[SPACE]");

        String cleanText = line.replaceFirst("[LINE]", "").replaceFirst("[SPACE]", "");
        Widget lineWidget = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 3),
          child: Container(
            constraints: const BoxConstraints(minHeight: 22),
            alignment: Alignment.centerLeft,
            child: Text(
              cleanText,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: cleanText == "-" || cleanText.isEmpty ? Colors.grey : AppTheme.textPrimary,
              ),
            ),
          ),
        );

        if (drawDivider) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Divider(color: Colors.grey.shade300, thickness: 0.8, height: 1, indent: 0, endIndent: 0),
              lineWidget,
            ],
          );
        }

        if (addLineSpacing) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [const SizedBox(height: 13), lineWidget],
          );
        }

        return lineWidget;
      }).toList(),
    );
  }
}

class FilterParams {
  final List<ProcessedRequest> requests;
  final String query;
  final DateTimeRange? dateRange;
  final Set<String>? names;
  final Set<String>? phones;
  final Set<String>? roles;
  final Set<String>? genders;
  final Set<String>? clusters;
  final Set<String>? villages;
  final Set<String>? schools;
  final Set<String>? qualifications;
  final Set<String>? times;
  final int sortColumnIndex;
  final bool isAscending;

  FilterParams({
    required this.requests,
    required this.query,
    this.dateRange,
    this.names,
    this.phones,
    this.roles,
    this.genders,
    this.clusters,
    this.villages,
    this.schools,
    this.qualifications,
    this.times,
    required this.sortColumnIndex,
    required this.isAscending,
  });
}

List<ProcessedRequest> _filterAndSortInIsolate(FilterParams params) {
  final query = params.query;

  final filtered = params.requests.where((req) {
    if (params.dateRange != null &&
        (req.date.isBefore(params.dateRange!.start) || req.date.isAfter(params.dateRange!.end.add(const Duration(days: 1))))) {
      return false;
    }

    if (query.isNotEmpty && !req.searchKey.contains(query)) {
      return false;
    }

    if (params.names != null && !params.names!.contains(req.fullName)) return false;
    if (params.phones != null && !params.phones!.contains(req.phone)) return false;
    if (params.roles != null && !params.roles!.contains(req.role)) return false;
    if (params.genders != null && !params.genders!.contains(req.gender)) return false;
    if (params.clusters != null && !params.clusters!.contains(req.cluster)) return false;
    if (params.villages != null && !params.villages!.contains(req.village)) return false;
    if (params.schools != null && !params.schools!.contains(req.school)) return false;
    if (params.qualifications != null && !params.qualifications!.contains(req.qualification)) return false;
    if (params.times != null && !params.times!.contains(req.timeFormatted)) return false;

    return true;
  }).toList();

  filtered.sort((a, b) {
    String valA = "";
    String valB = "";
    switch (params.sortColumnIndex) {
      case 0:
        valA = a.fullName;
        valB = b.fullName;
        break;
      case 1:
        valA = a.phone;
        valB = b.phone;
        break;
      case 2:
        valA = a.role;
        valB = b.role;
        break;
      case 3:
        valA = a.gender;
        valB = b.gender;
        break;
      case 4:
        valA = a.cluster;
        valB = b.cluster;
        break;
      case 5:
        valA = a.village;
        valB = b.village;
        break;
      case 6:
        valA = a.school;
        valB = b.school;
        break;
      case 7:
        valA = a.qualification;
        valB = b.qualification;
        break;
      case 8:
      case 9:
        return params.isAscending ? a.date.compareTo(b.date) : b.date.compareTo(a.date);
    }
    int compare = valA.toLowerCase().compareTo(valB.toLowerCase());
    return params.isAscending ? compare : -compare;
  });

  return filtered;
}
