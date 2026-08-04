import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:gyanshala_app/features/employees/presentation/widgets/employee_attendance_table.dart';
import 'package:intl/intl.dart';

class EmployeeAttendanceTab extends ConsumerStatefulWidget {
  final DateTimeRange range;
  final String searchQuery;
  final Function(DateTimeRange) onRangeChanged;
  const EmployeeAttendanceTab({super.key, required this.range, required this.searchQuery, required this.onRangeChanged});

  @override
  ConsumerState<EmployeeAttendanceTab> createState() => EmployeeAttendanceTabState();
}

class EmployeeAttendanceTabState extends ConsumerState<EmployeeAttendanceTab> {
  final GlobalKey<EmployeeAttendanceTableState> _tableKey = GlobalKey<EmployeeAttendanceTableState>();

  List<String> _allRoles = [];
  List<String> _allGenders = [];
  List<String> _allClusters = [];
  List<String> _allVillages = [];
  List<String> _allSchools = [];

  Set<String>? _roleFilter;
  Set<String>? _genderFilter;
  Set<String>? _clusterFilter;
  Set<String>? _villageFilter;
  Set<String>? _schoolFilter;

  bool _filtersLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadFilterOptions();
  }

  Future<void> _loadFilterOptions() async {
    try {
      final supabase = ref.read(supabaseClientProvider);

      final profiles =
          ((await supabase.from('profiles').select('role, gender').inFilter('role', [
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

      final schools = ((await supabase.from('schools').select('name, villages(name, clusters(name))')) as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final roles = profiles.map((p) => p['role']?.toString() ?? '').where((r) => r.isNotEmpty).toSet().toList()..sort();
      final genders = profiles.map((p) => p['gender']?.toString() ?? '').where((g) => g.isNotEmpty).toSet().toList()..sort();

      final schoolNames = <String>{};
      final villageNames = <String>{};
      final clusterNames = <String>{};
      for (final s in schools) {
        final name = s['name']?.toString() ?? '';
        if (name.isNotEmpty) schoolNames.add(name);
        final v = s['villages'] as Map?;
        final vName = v?['name']?.toString() ?? '';
        if (vName.isNotEmpty) villageNames.add(vName);
        final c = v?['clusters'] as Map?;
        final cName = c?['name']?.toString() ?? '';
        if (cName.isNotEmpty) clusterNames.add(cName);
      }

      if (mounted) {
        setState(() {
          _allRoles = roles;
          _allGenders = genders;
          _allClusters = clusterNames.toList()..sort();
          _allVillages = villageNames.toList()..sort();
          _allSchools = schoolNames.toList()..sort();
          _filtersLoaded = true;
        });
      }
    } catch (_) {}
  }

  Future<void> exportCurrentTable() async {
    await _tableKey.currentState?.exportExcel();
  }

  Future<void> _showMultiSelectFilter({
    required String title,
    required List<String> allOptions,
    required Set<String>? currentFilter,
    required void Function(Set<String>?) onApply,
  }) async {
    Set<String> selection = currentFilter != null ? Set.from(currentFilter) : Set.from(allOptions);
    final searchCtrl = TextEditingController();
    List<String> filtered = List.from(allOptions);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text("Filter by $title"),
          content: SizedBox(
            width: 320,
            height: 420,
            child: Column(
              children: [
                TextField(
                  controller: searchCtrl,
                  decoration: const InputDecoration(hintText: "Search...", prefixIcon: Icon(Icons.search)),
                  onChanged: (v) => setD(() {
                    filtered = allOptions.where((e) => e.toLowerCase().contains(v.toLowerCase())).toList();
                  }),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  dense: true,
                  value: selection.length == allOptions.length,
                  title: const Text("Select All"),
                  onChanged: (v) => setD(() => selection = v == true ? Set.from(allOptions) : {}),
                ),
                const Divider(),
                Expanded(
                  child: ListView(
                    children: filtered
                        .map(
                          (opt) => CheckboxListTile(
                            dense: true,
                            value: selection.contains(opt),
                            title: Text(opt),
                            onChanged: (v) => setD(() => v == true ? selection.add(opt) : selection.remove(opt)),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                onApply(selection.length == allOptions.length ? null : Set.from(selection));
                Navigator.pop(ctx);
              },
              child: const Text("Apply"),
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasActiveFilters =>
      _roleFilter != null || _genderFilter != null || _clusterFilter != null || _villageFilter != null || _schoolFilter != null;

  Future<void> _selectSingleDate(BuildContext context, {required bool isStart}) async {
    final DateTime firstDate = DateTime(1970);
    final DateTime lastDate = DateTime.now();
    DateTime initialDate = isStart ? widget.range.start : widget.range.end;
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    if (initialDate.isAfter(lastDate)) initialDate = lastDate;
    final DateTime pickerFirstDate = isStart ? firstDate : widget.range.start;
    final DateTime pickerLastDate = isStart ? widget.range.end : lastDate;
    if (initialDate.isBefore(pickerFirstDate)) initialDate = pickerFirstDate;
    if (initialDate.isAfter(pickerLastDate)) initialDate = pickerLastDate;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: pickerFirstDate,
      lastDate: pickerLastDate,
    );
    if (picked != null) {
      if (isStart) {
        final newEnd = picked.isAfter(widget.range.end) ? picked : widget.range.end;
        widget.onRangeChanged(DateTimeRange(start: picked, end: newEnd));
      } else {
        final newStart = picked.isBefore(widget.range.start) ? picked : widget.range.start;
        widget.onRangeChanged(DateTimeRange(start: newStart, end: picked));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    Widget buildWeekControls() => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () {
            final newEnd = widget.range.start.subtract(const Duration(days: 1));
            final newStart = newEnd.subtract(const Duration(days: 6));
            widget.onRangeChanged(DateTimeRange(start: newStart, end: newEnd));
          },
          icon: const Icon(Icons.arrow_left, size: 37),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        Expanded(
          child: _quickBtn("This Week", () {
            final start = now.subtract(Duration(days: now.weekday - 1));
            final end = start.add(const Duration(days: 6));
            widget.onRangeChanged(DateTimeRange(start: start, end: end));
          }),
        ),
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: const Icon(Icons.arrow_right, size: 37),
          onPressed: () {
            final newStart = widget.range.end.add(const Duration(days: 1));
            final newEnd = newStart.add(const Duration(days: 6));
            widget.onRangeChanged(DateTimeRange(start: newStart, end: newEnd));
          },
          tooltip: 'Next week',
        ),
      ],
    );
    Widget buildMonthControls() => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: const Icon(Icons.arrow_left, size: 37),
          onPressed: () {
            final newMonthEnd = DateTime(widget.range.start.year, widget.range.start.month, 0);
            final newMonthStart = DateTime(newMonthEnd.year, newMonthEnd.month, 1);
            widget.onRangeChanged(DateTimeRange(start: newMonthStart, end: newMonthEnd));
          },
          tooltip: 'Previous month',
        ),
        Expanded(
          child: _quickBtn("This Month", () {
            final start = DateTime(now.year, now.month, 1);
            final end = DateTime(now.year, now.month + 1, 0);
            widget.onRangeChanged(DateTimeRange(start: start, end: end));
          }),
        ),
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: const Icon(Icons.arrow_right, size: 37),
          onPressed: () {
            final newMonthStart = DateTime(widget.range.end.year, widget.range.end.month + 1, 1);
            final newMonthEnd = DateTime(newMonthStart.year, newMonthStart.month + 1, 0);
            widget.onRangeChanged(DateTimeRange(start: newMonthStart, end: newMonthEnd));
          },
          tooltip: 'Next month',
        ),
      ],
    );

    Widget buildDateSelectors() => Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 8),
            _dateInkWell(context: context, date: widget.range.start, isStart: true),
            const SizedBox(width: 13),
            const Text("to", style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(width: 13),
            _dateInkWell(context: context, date: widget.range.end, isStart: false),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );

    Widget buildFilterBar() {
      if (!_filtersLoaded) return const SizedBox.shrink();

      _filterChip(String label, List<String> options, Set<String>? active, void Function(Set<String>?) onApply) => ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        avatar: Icon(Icons.filter_alt, size: 14, color: active != null ? AppTheme.primaryBlue : Colors.grey.shade600),
        backgroundColor: active != null ? AppTheme.primaryBlue.withAlpha(30) : null,
        side: BorderSide(color: active != null ? AppTheme.primaryBlue : Colors.grey.shade400),
        onPressed: () => _showMultiSelectFilter(
          title: label,
          allOptions: options,
          currentFilter: active,
          onApply: (v) => setState(() => onApply(v)),
        ),
      );

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: Colors.grey.shade50,
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _filterChip("Role", _allRoles, _roleFilter, (v) => _roleFilter = v),
                  _filterChip("Gender", _allGenders, _genderFilter, (v) => _genderFilter = v),
                  _filterChip("Cluster", _allClusters, _clusterFilter, (v) => _clusterFilter = v),
                  _filterChip("Village", _allVillages, _villageFilter, (v) => _villageFilter = v),
                  _filterChip("School", _allSchools, _schoolFilter, (v) => _schoolFilter = v),
                ],
              ),
            ),
            if (_hasActiveFilters)
              TextButton.icon(
                onPressed: () => setState(() {
                  _roleFilter = _genderFilter = _clusterFilter = _villageFilter = _schoolFilter = null;
                }),
                icon: const Icon(Icons.filter_alt_off, size: 15),
                label: const Text("Clear", style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 8)),
              ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3.0, vertical: 2),
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
        ),
        buildFilterBar(),
        const Divider(height: 1),
        Expanded(
          child: EmployeeAttendanceTable(
            key: _tableKey,
            searchQuery: widget.searchQuery,
            startDate: widget.range.start,
            endDate: widget.range.end,
            roleFilter: _roleFilter,
            genderFilter: _genderFilter,
            clusterFilter: _clusterFilter,
            villageFilter: _villageFilter,
            schoolFilter: _schoolFilter,
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

  Widget _dateInkWell({required BuildContext context, required DateTime date, required bool isStart}) {
    return InkWell(
      onTap: () => _selectSingleDate(context, isStart: isStart),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 13),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.primaryBlue, width: 1),
          color: Colors.white,
        ),
        child: Text(
          _formatDateWithMonth(date),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
          textAlign: TextAlign.center,
          maxLines: 1,
        ),
      ),
    );
  }

  String _formatDateWithMonth(DateTime date) {
    final dayName = DateFormat('EEE').format(date);
    final formatted = DateFormat('dd-MM-yyyy').format(date);
    return '$formatted ($dayName)';
  }
}
