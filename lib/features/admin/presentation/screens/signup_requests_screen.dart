import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:intl/intl.dart';

class SignupRequestsScreen extends ConsumerStatefulWidget {
  const SignupRequestsScreen({super.key});
  @override
  ConsumerState<SignupRequestsScreen> createState() => _SignupRequestsScreenState();
}

class _SignupRequestsScreenState extends ConsumerState<SignupRequestsScreen> {
  bool _isLoading = false;
  final _searchController = TextEditingController();
  int _sortColumnIndex = 7;
  bool _isAscending = false;
  Set<String>? _selectedNameFilters;
  Set<String>? _selectedPhoneFilters;
  Set<String>? _selectedRoleFilters;
  Set<String>? _selectedClusterFilters;
  Set<String>? _selectedVillageFilters;
  Set<String>? _selectedSchoolFilters;
  Set<String>? _selectedQualificationFilters;
  late DateTimeRange _selectedDateRange;
  Set<String>? _selectedTimeFilters;
  List<Map<String, dynamic>> _rawRequests = [];
  List<Map<String, dynamic>> _filteredRequests = [];

  @override
  void initState() {
    super.initState();
    final startOfWeek = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
    _selectedDateRange = DateTimeRange(start: startOfWeek, end: startOfWeek.add(const Duration(days: 6)));
  }

  void _onSort(int columnIndex) {
    if (columnIndex == 9) return;
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

  void _applySorting() {
    _filteredRequests.sort((a, b) {
      String valA = "";
      String valB = "";
      switch (_sortColumnIndex) {
        case 0:
          valA = "${a['first_name'] ?? ''} ${a['last_name'] ?? ''}";
          valB = "${b['first_name'] ?? ''} ${b['last_name'] ?? ''}";
          break;
        case 1:
          valA = a['phone']?.toString() ?? "";
          valB = b['phone']?.toString() ?? "";
          break;
        case 2:
          valA = a['role']?.toString() ?? "";
          valB = b['role']?.toString() ?? "";
          break;
        case 3:
          valA = a['cluster']?.toString() ?? "";
          valB = b['cluster']?.toString() ?? "";
          break;
        case 4:
          valA = a['village']?.toString() ?? "";
          valB = b['village']?.toString() ?? "";
          break;
        case 5:
          valA = a['school']?.toString() ?? "";
          valB = b['school']?.toString() ?? "";
          break;
        case 6:
          valA = a['qualification']?.toString() ?? "";
          valB = b['qualification']?.toString() ?? "";
          break;
        case 7:
        case 8:
          final dateA = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(1970);
          final dateB = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(1970);
          return _isAscending ? dateA.compareTo(dateB) : dateB.compareTo(dateA);
      }
      int compare = valA.toLowerCase().compareTo(valB.toLowerCase());
      return _isAscending ? compare : -compare;
    });
  }

  void _applyAllFilters() {
    final query = _searchController.text.toLowerCase().trim();
    final result = _rawRequests.where((req) {
      final fullName = "${req['first_name'] ?? ''} ${req['last_name'] ?? ''}";
      final phone = req['phone']?.toString() ?? "";
      final role = req['role']?.toString() ?? "";
      final cluster = req['cluster']?.toString() ?? "";
      final village = req['village']?.toString() ?? "";
      final school = req['school']?.toString() ?? "";
      final qualification = req['qualification']?.toString() ?? "";
      final createdAt = req['created_at'] != null ? DateTime.parse(req['created_at']).toLocal() : null;
      if (createdAt != null) {
        if (createdAt.isBefore(_selectedDateRange.start) || createdAt.isAfter(_selectedDateRange.end)) {
          return false;
        }
      }
      final signupTime = req['created_at'] != null
          ? DateFormat('hh:mm a').format(DateTime.parse(req['created_at']).toLocal())
          : '';

      final matchesSearch =
          query.isEmpty ||
          fullName.toLowerCase().contains(query) ||
          phone.toLowerCase().contains(query) ||
          role.toLowerCase().contains(query) ||
          cluster.toLowerCase().contains(query) ||
          village.toLowerCase().contains(query) ||
          school.toLowerCase().contains(query) ||
          qualification.toLowerCase().contains(query) ||
          signupTime.toLowerCase().contains(query);

      if (!matchesSearch) return false;
      if (_selectedNameFilters != null && !_selectedNameFilters!.contains(fullName)) return false;
      if (_selectedPhoneFilters != null && !_selectedPhoneFilters!.contains(phone)) return false;
      if (_selectedRoleFilters != null && !_selectedRoleFilters!.contains(role)) return false;
      if (_selectedClusterFilters != null && !_selectedClusterFilters!.contains(cluster)) return false;
      if (_selectedVillageFilters != null && !_selectedVillageFilters!.contains(village)) return false;
      if (_selectedSchoolFilters != null && !_selectedSchoolFilters!.contains(school)) return false;
      if (_selectedQualificationFilters != null && !_selectedQualificationFilters!.contains(qualification)) return false;
      if (_selectedTimeFilters != null && !_selectedTimeFilters!.contains(signupTime)) return false;
      return true;
    }).toList();
    setState(() {
      _filteredRequests = result;
      _applySorting();
    });
  }

  List<String> _getUniqueValuesForColumn(int columnIndex) {
    final Set<String> values = {};
    for (final req in _rawRequests) {
      switch (columnIndex) {
        case 0:
          values.add("${req['first_name'] ?? ''} ${req['last_name'] ?? ''}");
          break;
        case 1:
          if (req['phone'] != null) values.add(req['phone'].toString());
          break;
        case 2:
          if (req['role'] != null) values.add(req['role'].toString());
          break;
        case 3:
          if (req['cluster'] != null) values.add(req['cluster'].toString());
          break;
        case 4:
          if (req['village'] != null) values.add(req['village'].toString());
          break;
        case 5:
          if (req['school'] != null) values.add(req['school'].toString());
          break;
        case 6:
          if (req['qualification'] != null) values.add(req['qualification'].toString());
          break;
        case 8:
          if (req['created_at'] != null) {
            final date = DateTime.parse(req['created_at']).toLocal();
            values.add(DateFormat('hh:mm a').format(date));
          }
          break;
      }
    }
    return values.toList()..sort();
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
      currentSelection = _selectedClusterFilters != null ? Set.from(_selectedClusterFilters!) : Set.from(allValues);
    else if (columnIndex == 4)
      currentSelection = _selectedVillageFilters != null ? Set.from(_selectedVillageFilters!) : Set.from(allValues);
    else if (columnIndex == 5)
      currentSelection = _selectedSchoolFilters != null ? Set.from(_selectedSchoolFilters!) : Set.from(allValues);
    else if (columnIndex == 6)
      currentSelection = _selectedQualificationFilters != null ? Set.from(_selectedQualificationFilters!) : Set.from(allValues);
    else
      currentSelection = _selectedTimeFilters != null ? Set.from(_selectedTimeFilters!) : Set.from(allValues);

    final dialogSearchController = TextEditingController();
    List<String> filteredValues = List.from(allValues);

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
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  final noFilter = currentSelection.isEmpty || currentSelection.length == allValues.length;

                  if (columnIndex == 0) _selectedNameFilters = noFilter ? null : Set.from(currentSelection);
                  if (columnIndex == 1) _selectedPhoneFilters = noFilter ? null : Set.from(currentSelection);
                  if (columnIndex == 2) _selectedRoleFilters = noFilter ? null : Set.from(currentSelection);
                  if (columnIndex == 3) _selectedClusterFilters = noFilter ? null : Set.from(currentSelection);
                  if (columnIndex == 4) _selectedVillageFilters = noFilter ? null : Set.from(currentSelection);
                  if (columnIndex == 5) _selectedSchoolFilters = noFilter ? null : Set.from(currentSelection);
                  if (columnIndex == 6) _selectedQualificationFilters = noFilter ? null : Set.from(currentSelection);
                  if (columnIndex == 8) _selectedTimeFilters = noFilter ? null : Set.from(currentSelection);
                  _applyAllFilters();
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

  // UPDATED: Now supports updating action_reason to Supabase
  Future<void> _updateStatus(String id, String name, String status, {String? reason}) async {
    setState(() => _isLoading = true);
    try {
      final supabase = ref.read(supabaseClientProvider);

      final Map<String, dynamic> updatePayload = {'status': status};
      if (reason != null && reason.trim().isNotEmpty) {
        updatePayload['action_reason'] = reason.trim();
        updatePayload['actioned_at'] = DateTime.now().toIso8601String();
      }

      await supabase.from('signup_requests').update(updatePayload).eq('id', id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('User $name marked as $status')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ADDED: Prompt confirmation dialog with a reason text box
  Future<String?> _showRejectDialog(String name, String actionTitle) async {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('$actionTitle Request'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Are you sure you want to reject the signup request for $name?'),
              const SizedBox(height: 16),
              TextFormField(
                controller: reasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason for Rejection',
                  hintText: 'Provide context or why it was rejected...',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a reason for the rejection';
                  }
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
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, reasonController.text);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Confirm Reject'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateRange.start,
      firstDate: DateTime(1970),
      lastDate: _selectedDateRange.end,
    );

    if (picked != null) {
      setState(() {
        _selectedDateRange = DateTimeRange(start: picked, end: _selectedDateRange.end);
      });
      _applyAllFilters();
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateRange.end,
      firstDate: _selectedDateRange.start,
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _selectedDateRange = DateTimeRange(start: _selectedDateRange.start, end: picked);
      });
      _applyAllFilters();
    }
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
          onPressed: () {
            final newEnd = _selectedDateRange.start.subtract(const Duration(days: 1));
            final newStart = newEnd.subtract(const Duration(days: 6));
            setState(() {
              _selectedDateRange = DateTimeRange(start: newStart, end: newEnd);
            });
            _applyAllFilters();
          },
        ),
        Expanded(
          child: _quickBtn("This Week", () {
            final start = now.subtract(Duration(days: now.weekday - 1));
            final end = start.add(const Duration(days: 6));
            setState(() {
              _selectedDateRange = DateTimeRange(start: start, end: end);
            });
            _applyAllFilters();
          }),
        ),
        IconButton(
          icon: const Icon(Icons.arrow_right, size: 37),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () {
            final newStart = _selectedDateRange.end.add(const Duration(days: 1));
            final newEnd = newStart.add(const Duration(days: 6));
            setState(() {
              _selectedDateRange = DateTimeRange(start: newStart, end: newEnd);
            });
            _applyAllFilters();
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
          onPressed: () {
            final newMonthEnd = DateTime(_selectedDateRange.start.year, _selectedDateRange.start.month, 0);
            final newMonthStart = DateTime(newMonthEnd.year, newMonthEnd.month, 1);
            setState(() {
              _selectedDateRange = DateTimeRange(start: newMonthStart, end: newMonthEnd);
            });
            _applyAllFilters();
          },
        ),
        Expanded(
          child: _quickBtn("This Month", () {
            final start = DateTime(now.year, now.month, 1);
            final end = DateTime(now.year, now.month + 1, 0);
            setState(() {
              _selectedDateRange = DateTimeRange(start: start, end: end);
            });
            _applyAllFilters();
          }),
        ),
        IconButton(
          icon: const Icon(Icons.arrow_right, size: 37),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () {
            final newMonthStart = DateTime(_selectedDateRange.end.year, _selectedDateRange.end.month + 1, 1);
            final newMonthEnd = DateTime(newMonthStart.year, newMonthStart.month + 1, 0);
            setState(() {
              _selectedDateRange = DateTimeRange(start: newMonthStart, end: newMonthEnd);
            });
            _applyAllFilters();
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
            _dateInkWell(date: _selectedDateRange.start, isStart: true),
            const SizedBox(width: 13),
            const Text("to", style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(width: 13),
            _dateInkWell(date: _selectedDateRange.end, isStart: false),
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

  Widget _buildTable(String statusFilter) {
    final supabase = ref.watch(supabaseClientProvider);

    return Column(
      children: [
        _buildDateControls(),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: supabase.from('signup_requests').stream(primaryKey: ['id']).eq('status', statusFilter),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              _rawRequests = List<Map<String, dynamic>>.from(snapshot.data!);
              final query = _searchController.text.toLowerCase().trim();

              _filteredRequests = _rawRequests.where((req) {
                final fullName = "${req['first_name'] ?? ''} ${req['last_name'] ?? ''}";
                final signupTime = req['created_at'] != null
                    ? DateFormat('hh:mm a').format(DateTime.parse(req['created_at']).toLocal())
                    : '';

                if (_selectedNameFilters != null && !_selectedNameFilters!.contains(fullName)) return false;
                if (_selectedPhoneFilters != null && !_selectedPhoneFilters!.contains(req['phone']?.toString())) return false;
                if (_selectedRoleFilters != null && !_selectedRoleFilters!.contains(req['role'])) return false;
                if (_selectedClusterFilters != null && !_selectedClusterFilters!.contains(req['cluster'])) return false;
                if (_selectedVillageFilters != null && !_selectedVillageFilters!.contains(req['village'])) return false;
                if (_selectedSchoolFilters != null && !_selectedSchoolFilters!.contains(req['school'])) return false;
                if (_selectedQualificationFilters != null && !_selectedQualificationFilters!.contains(req['qualification']))
                  return false;

                final createdAt = req['created_at'] != null ? DateTime.parse(req['created_at']).toLocal() : null;
                if (createdAt != null) {
                  if (createdAt.isBefore(_selectedDateRange.start) || createdAt.isAfter(_selectedDateRange.end)) {
                    return false;
                  }
                }
                if (_selectedTimeFilters != null && !_selectedTimeFilters!.contains(signupTime)) return false;
                return query.isEmpty ||
                    fullName.toLowerCase().contains(query) ||
                    (req['phone']?.toString().toLowerCase().contains(query) ?? false) ||
                    (req['qualification']?.toString().toLowerCase().contains(query) ?? false);
              }).toList();

              _applySorting();
              final defaultStart = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
              final defaultEnd = defaultStart.add(const Duration(days: 6));

              return Column(
                children: [
                  Expanded(
                    child: _filteredRequests.isEmpty
                        ? const Center(child: Text("No records match your filters"))
                        : SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Table(
                                defaultColumnWidth: const IntrinsicColumnWidth(),
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
                                        label: "Cluster",
                                        onSort: () => _onSort(3),
                                        onFilter: () => _showFilterMenu(3, "Cluster"),
                                        isSorted: _sortColumnIndex == 3,
                                        isAscending: _isAscending,
                                        hasFilter: _selectedClusterFilters != null,
                                      ),
                                      _SortableHeader(
                                        label: "Village",
                                        onSort: () => _onSort(4),
                                        onFilter: () => _showFilterMenu(4, "Village"),
                                        isSorted: _sortColumnIndex == 4,
                                        isAscending: _isAscending,
                                        hasFilter: _selectedVillageFilters != null,
                                      ),
                                      _SortableHeader(
                                        label: "School",
                                        onSort: () => _onSort(5),
                                        onFilter: () => _showFilterMenu(5, "School"),
                                        isSorted: _sortColumnIndex == 5,
                                        isAscending: _isAscending,
                                        hasFilter: _selectedSchoolFilters != null,
                                      ),
                                      _SortableHeader(
                                        label: "Qualification",
                                        onSort: () => _onSort(6),
                                        onFilter: () => _showFilterMenu(6, "Qualification"),
                                        isSorted: _sortColumnIndex == 6,
                                        isAscending: _isAscending,
                                        hasFilter: _selectedQualificationFilters != null,
                                      ),
                                      _SortableHeader(
                                        label: "Date",
                                        onSort: () => _onSort(7),
                                        onFilter: () => _pickStartDate(),
                                        isSorted: _sortColumnIndex == 7,
                                        isAscending: _isAscending,
                                        hasFilter:
                                            _selectedDateRange.start != defaultStart || _selectedDateRange.end != defaultEnd,
                                      ),
                                      _SortableHeader(
                                        label: "Time",
                                        onSort: () => _onSort(8),
                                        onFilter: () => _showFilterMenu(8, "Time"),
                                        isSorted: _sortColumnIndex == 8,
                                        isAscending: _isAscending,
                                        hasFilter: _selectedTimeFilters != null,
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: Text("Actions", style: TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                  ..._filteredRequests.map((req) {
                                    final String currentName = "${req['first_name'] ?? ''} ${req['last_name'] ?? ''}";
                                    final createdAt = DateTime.parse(req['created_at']).toLocal();
                                    return TableRow(
                                      children: [
                                        _DataCell(text: currentName, isBold: true),
                                        _DataCell(text: req['phone']?.toString() ?? "-"),
                                        _DataCell(text: req['role']?.toString() ?? "-"),
                                        _DataCell(text: req['cluster']?.toString() ?? "-"),
                                        _DataCell(text: req['village']?.toString() ?? "-"),
                                        _DataCell(text: req['school']?.toString() ?? "-"),
                                        _DataCell(text: req['qualification']?.toString() ?? "-"),
                                        _DataCell(text: DateFormat('dd MMM yyyy').format(createdAt)),
                                        _DataCell(text: DateFormat('hh:mm a').format(createdAt)),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          child: statusFilter == 'pending'
                                              ? Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    SizedBox(
                                                      height: 32,
                                                      width: 75,
                                                      child: ElevatedButton(
                                                        onPressed: _isLoading
                                                            ? null
                                                            : () => _updateStatus(req['id'], req['first_name'] ?? '', 'approved'),
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor: Colors.green,
                                                          foregroundColor: Colors.white,
                                                          padding: EdgeInsets.zero,
                                                        ),
                                                        child: const Text(
                                                          "Approve",
                                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    SizedBox(
                                                      height: 32,
                                                      width: 75,
                                                      child: ElevatedButton(
                                                        // UPDATED: Now pops open text dialog before updating Supabase status to 'removed'
                                                        onPressed: _isLoading
                                                            ? null
                                                            : () async {
                                                                final reason = await _showRejectDialog(
                                                                  req['first_name'] ?? 'User',
                                                                  'Reject',
                                                                );
                                                                if (reason != null) {
                                                                  _updateStatus(
                                                                    req['id'],
                                                                    req['first_name'] ?? '',
                                                                    'removed',
                                                                    reason: reason,
                                                                  );
                                                                }
                                                              },
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor: Colors.red,
                                                          foregroundColor: Colors.white,
                                                          padding: EdgeInsets.zero,
                                                        ),
                                                        child: const Text(
                                                          "Reject",
                                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              : Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    SizedBox(
                                                      height: 32,
                                                      width: 80,
                                                      child: ElevatedButton(
                                                        onPressed: _isLoading
                                                            ? null
                                                            : () =>
                                                                  _updateStatus(req['id'], req['first_name'] ?? '', 'suspended'),
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor: Colors.orange,
                                                          foregroundColor: Colors.white,
                                                          padding: EdgeInsets.zero,
                                                        ),
                                                        child: const Text(
                                                          "Suspend",
                                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    SizedBox(
                                                      height: 32,
                                                      width: 75,
                                                      child: ElevatedButton(
                                                        // UPDATED: Standardized the "Remove" option to also use the new reason workflow
                                                        onPressed: _isLoading
                                                            ? null
                                                            : () async {
                                                                final reason = await _showRejectDialog(
                                                                  req['first_name'] ?? 'User',
                                                                  'Remove',
                                                                );
                                                                if (reason != null) {
                                                                  _updateStatus(
                                                                    req['id'],
                                                                    req['first_name'] ?? '',
                                                                    'removed',
                                                                    reason: reason,
                                                                  );
                                                                }
                                                              },
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor: Colors.red,
                                                          foregroundColor: Colors.white,
                                                          padding: EdgeInsets.zero,
                                                        ),
                                                        child: const Text(
                                                          "Remove",
                                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                        ),
                                      ],
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
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

  Widget _dateInkWell({required DateTime date, required bool isStart}) {
    return InkWell(
      onTap: () {
        if (isStart) {
          _pickStartDate();
        } else {
          _pickEndDate();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 13),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.primaryBlue),
          color: Colors.white,
        ),
        child: Text(
          _formatDateWithMonth(date),
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Signup Request Management"),
          bottom: const TabBar(
            tabs: [
              Tab(text: "Pending"),
              Tab(text: "Approved"),
              Tab(text: "Suspended"),
            ],
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [_buildTable('pending'), _buildTable('approved'), _buildTable('suspended')],
        ),
      ),
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
              decoration: BoxDecoration(color: hasFilter ? AppTheme.primaryBlue.withValues(alpha: 0.13) : Colors.transparent),
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
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: text == "-" ? Colors.grey : AppTheme.textPrimary,
        ),
      ),
    );
  }
}
