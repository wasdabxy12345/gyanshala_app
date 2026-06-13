import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/models/user_role.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';

/// A tab widget that displays a highly functional, filterable, and sortable
/// list of employees using Riverpod for global state access and Supabase for realtime data.
class EmployeeListTab extends ConsumerStatefulWidget {
  final String searchQuery; // Global search string passed down from the parent widget

  const EmployeeListTab({super.key, required this.searchQuery});

  @override
  ConsumerState<EmployeeListTab> createState() => EmployeeListTabState();
}

class EmployeeListTabState extends ConsumerState<EmployeeListTab> {
  // ==========================================
  // STATE PROPERTIES
  // ==========================================

  /// Holds the distinct database IDs of rows currently marked as selected.
  final Set<String> _selectedEmployeeIds = {};

  /// Indexes for tracking columns:
  /// 0: First Name, 1: Last Name, 2: Phone, 3: Role, 4: Cluster, 5: Village, 6: School
  int _sortColumnIndex = 0;
  bool _isAscending = true;

  /// Multi-select categorical filters for specific columns.
  /// A `null` value implies no restrictions are active for that specific column.
  Set<String>? _selectedFirstNameFilters;
  Set<String>? _selectedLastNameFilters;
  Set<String>? _selectedPhoneFilters;
  Set<String>? _selectedRoleFilters;
  Set<String>? _selectedClusterFilters;
  Set<String>? _selectedVillageFilters;
  Set<String>? _selectedSchoolFilters;

  /// Cache layers preserving data manipulation pipelines.
  List<Map<String, dynamic>> _rawEmployees = []; // Master records fetched from the database
  List<Map<String, dynamic>> _filteredEmployees = []; // Mutations after search queries and categorical filters

  // Public Getters exposing internal state matrices
  List<Map<String, dynamic>> get filteredEmployees => _filteredEmployees;
  Set<String> get selectedEmployeeIds => _selectedEmployeeIds;

  // ==========================================
  // SORTING LOGIC
  // ==========================================

  /// Triggers a state mutation to sort data based on the targeted column index.
  void _onSort(int columnIndex) {
    setState(() {
      if (_sortColumnIndex == columnIndex) {
        _isAscending = !_isAscending; // Toggle ordering direction if same column is re-selected
      } else {
        _sortColumnIndex = columnIndex;
        _isAscending = true; // Default to ascending sequence on structural shift
      }
      _applySorting();
    });
  }

  /// Evaluates and sorts [_filteredEmployees] in-place depending on current criteria.
  void _applySorting() {
    _filteredEmployees.sort((a, b) {
      String valA = "";
      String valB = "";

      switch (_sortColumnIndex) {
        case 0:
          valA = a['first_name']?.toString() ?? "";
          break;
        case 1:
          valA = a['last_name']?.toString() ?? "";
          break;
        case 2:
          valA = a['phone']?.toString() ?? "";
          break;
        case 3:
          // Roles utilize specialized domain parsing logic based on explicit enum mappings
          valA = UserRole.fromString(a['role']).label;
          valB = UserRole.fromString(b['role']).label;
          int compare = valA.toLowerCase().compareTo(valB.toLowerCase());
          return _isAscending ? compare : -compare;
        case 4:
          valA = a['cluster']?.toString() ?? "";
          break;
        case 5:
          valA = a['village']?.toString() ?? "";
          break;
        case 6:
          valA = a['school']?.toString() ?? "";
          break;
      }

      // Universal column key resolution fallback logic (ignoring specialized roles extraction index)
      if (_sortColumnIndex != 3) {
        valB = b[_getDatabaseKeyFromColumnIndex(_sortColumnIndex)]?.toString() ?? "";
      }

      int compare = valA.toLowerCase().compareTo(valB.toLowerCase());
      return _isAscending ? compare : -compare;
    });
  }

  /// Maps presentation column indexes directly to standard Supabase DB collection schema string tags.
  String _getDatabaseKeyFromColumnIndex(int index) {
    switch (index) {
      case 0:
        return 'first_name';
      case 1:
        return 'last_name';
      case 2:
        return 'phone';
      case 4:
        return 'cluster';
      case 5:
        return 'village';
      case 6:
        return 'school';
      default:
        return '';
    }
  }

  // ==========================================
  // FILTERING LOGIC
  // ==========================================

  /// Re-evaluates search queries and user selections across all records.
  void _applyAllFilters() {
    final query = widget.searchQuery.toLowerCase().trim();
    final result = _rawRequestsFilterPass(_rawEmployees, query);

    setState(() {
      _filteredEmployees = result;
      _applySorting(); // Maintain data integrity configurations on content changes
    });
  }

  /// Evaluates every record against standard text string searches and selected filters.
  List<Map<String, dynamic>> _rawRequestsFilterPass(List<Map<String, dynamic>> source, String searchStr) {
    return source.where((emp) {
      final firstName = emp['first_name']?.toString() ?? "";
      final lastName = emp['last_name']?.toString() ?? "";
      final fullName = "$firstName $lastName";
      final phone = emp['phone']?.toString() ?? "";
      final roleLabel = UserRole.fromString(emp['role']).label;
      final cluster = emp['cluster']?.toString() ?? "";
      final village = emp['village']?.toString() ?? "";
      final school = emp['school']?.toString() ?? "";

      // Evaluation 1: Global String Match check across metadata parameters
      final matchesSearch =
          searchStr.isEmpty ||
          fullName.toLowerCase().contains(searchStr) ||
          phone.toLowerCase().contains(searchStr) ||
          roleLabel.toLowerCase().contains(searchStr) ||
          cluster.toLowerCase().contains(searchStr) ||
          village.toLowerCase().contains(searchStr) ||
          school.toLowerCase().contains(searchStr);

      if (!matchesSearch) return false;

      // Evaluation 2: Multi-select discrete filtering criteria assertions
      if (_selectedFirstNameFilters != null && !_selectedFirstNameFilters!.contains(firstName)) return false;
      if (_selectedLastNameFilters != null && !_selectedLastNameFilters!.contains(lastName)) return false;
      if (_selectedPhoneFilters != null && !_selectedPhoneFilters!.contains(phone)) return false;
      if (_selectedRoleFilters != null && !_selectedRoleFilters!.contains(emp['role']?.toString())) return false;
      if (_selectedClusterFilters != null && !_selectedClusterFilters!.contains(cluster)) return false;
      if (_selectedVillageFilters != null && !_selectedVillageFilters!.contains(village)) return false;
      if (_selectedSchoolFilters != null && !_selectedSchoolFilters!.contains(school)) return false;

      return true;
    }).toList();
  }

  /// Extracts unique historical variants present across raw datasets to populate targeted contextual checklist configurations.
  List<String> _getUniqueValuesForColumn(int columnIndex) {
    final Set<String> values = {};
    for (final emp in _rawEmployees) {
      switch (columnIndex) {
        case 0:
          if (emp['first_name'] != null) values.add(emp['first_name'].toString());
          break;
        case 1:
          if (emp['last_name'] != null) values.add(emp['last_name'].toString());
          break;
        case 2:
          if (emp['phone'] != null) values.add(emp['phone'].toString());
          break;
        case 3:
          if (emp['role'] != null) values.add(emp['role'].toString());
          break;
        case 4:
          if (emp['cluster'] != null) values.add(emp['cluster'].toString());
          break;
        case 5:
          if (emp['village'] != null) values.add(emp['village'].toString());
          break;
        case 6:
          if (emp['school'] != null) values.add(emp['school'].toString());
          break;
      }
    }
    return values.toList()..sort();
  }

  /// Displays an interactive popup dialog filled with distinct criteria checkboxes, allowing granular multi-filtering.
  Future<void> _showFilterMenu(int columnIndex, String label) async {
    final allValues = _getUniqueValuesForColumn(columnIndex);
    Set<String> currentSelection;

    // Isolate targeting instances parsing configurations
    if (columnIndex == 0)
      currentSelection = _selectedFirstNameFilters != null ? Set.from(_selectedFirstNameFilters!) : Set.from(allValues);
    else if (columnIndex == 1)
      currentSelection = _selectedLastNameFilters != null ? Set.from(_selectedLastNameFilters!) : Set.from(allValues);
    else if (columnIndex == 2)
      currentSelection = _selectedPhoneFilters != null ? Set.from(_selectedPhoneFilters!) : Set.from(allValues);
    else if (columnIndex == 3)
      currentSelection = _selectedRoleFilters != null ? Set.from(_selectedRoleFilters!) : Set.from(allValues);
    else if (columnIndex == 4)
      currentSelection = _selectedClusterFilters != null ? Set.from(_selectedClusterFilters!) : Set.from(allValues);
    else if (columnIndex == 5)
      currentSelection = _selectedVillageFilters != null ? Set.from(_selectedVillageFilters!) : Set.from(allValues);
    else
      currentSelection = _selectedSchoolFilters != null ? Set.from(_selectedSchoolFilters!) : Set.from(allValues);

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
                // In-dialog search input box for looking through long filter lists
                TextField(
                  controller: dialogSearchController,
                  decoration: const InputDecoration(hintText: "Search values...", prefixIcon: Icon(Icons.search)),
                  onChanged: (value) {
                    setStateDialog(() {
                      filteredValues = allValues.where((e) {
                        String dynamicValue = e;
                        if (columnIndex == 3) {
                          dynamicValue = UserRole.fromString(e).label;
                        }
                        return dynamicValue.toLowerCase().contains(value.toLowerCase());
                      }).toList();
                    });
                  },
                ),
                const SizedBox(height: 12),
                // Mass operations Master Checkbox control
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
                // Individual element checklist mapping loop blocks
                Expanded(
                  child: ListView(
                    children: filteredValues.map((value) {
                      String displayString = value;
                      if (columnIndex == 3) {
                        displayString = UserRole.fromString(value).label;
                      }
                      return CheckboxListTile(
                        dense: true,
                        value: currentSelection.contains(value),
                        title: Text(displayString),
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
                  final isAllSelected = currentSelection.length == allValues.length;
                  // If all options are selected, clear the filter constraint (null means no filter)
                  if (columnIndex == 0) _selectedFirstNameFilters = isAllSelected ? null : Set.from(currentSelection);
                  if (columnIndex == 1) _selectedLastNameFilters = isAllSelected ? null : Set.from(currentSelection);
                  if (columnIndex == 2) _selectedPhoneFilters = isAllSelected ? null : Set.from(currentSelection);
                  if (columnIndex == 3) _selectedRoleFilters = isAllSelected ? null : Set.from(currentSelection);
                  if (columnIndex == 4) _selectedClusterFilters = isAllSelected ? null : Set.from(currentSelection);
                  if (columnIndex == 5) _selectedVillageFilters = isAllSelected ? null : Set.from(currentSelection);
                  if (columnIndex == 6) _selectedSchoolFilters = isAllSelected ? null : Set.from(currentSelection);
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

  /// Resets all category filter matrices back to default parameters.
  void _clearAllFilters() {
    setState(() {
      _selectedFirstNameFilters = null;
      _selectedLastNameFilters = null;
      _selectedPhoneFilters = null;
      _selectedRoleFilters = null;
      _selectedClusterFilters = null;
      _selectedVillageFilters = null;
      _selectedSchoolFilters = null;
      _applyAllFilters();
    });
  }

  // ==========================================
  // BUILD ARCHITECTURE LAYERS
  // ==========================================

  @override
  Widget build(BuildContext context) {
    // Read the database client provider via Riverpod framework hooks.
    final supabase = ref.watch(supabaseClientProvider);

    return Scaffold(
      body: StreamBuilder<List<Map<String, dynamic>>>(
        // Connects to a realtime query stream looking specifically at targeted roles in the profiles database.
        stream: supabase.from('profiles').stream(primaryKey: ['id']).inFilter('role', ['shikshaMitra', 'seniorMentor']),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          // Populate local cache collections with raw stream results
          _rawEmployees = List<Map<String, dynamic>>.from(snapshot.data!);

          // Process and synchronize the display records instantly when underlying streams update
          final query = widget.searchQuery.toLowerCase().trim();
          _filteredEmployees = _rawRequestsFilterPass(_rawEmployees, query);
          _applySorting();

          // Performance flags evaluating component display conditions
          bool hasActiveFilters = [
            _selectedFirstNameFilters,
            _selectedLastNameFilters,
            _selectedPhoneFilters,
            _selectedRoleFilters,
            _selectedClusterFilters,
            _selectedVillageFilters,
            _selectedSchoolFilters,
          ].any((f) => f != null);

          bool isAllRowsSelected = _filteredEmployees.isNotEmpty && _selectedEmployeeIds.length == _filteredEmployees.length;

          return Column(
            children: [
              // ------------------------------------------
              // CONTROL HEADER BAR: Batch Operations & Status
              // ------------------------------------------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: Colors.blue.shade50),
                      child: Text(
                        '${_selectedEmployeeIds.length} Selected',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 13),
                      ),
                    ),
                    const Spacer(),
                    if (hasActiveFilters)
                      TextButton.icon(
                        onPressed: _clearAllFilters,
                        icon: const Icon(Icons.filter_alt_off, size: 16),
                        label: const Text('Clear Table Filters'),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                      ),
                    TextButton(
                      onPressed: () => setState(() {
                        if (isAllRowsSelected) {
                          _selectedEmployeeIds.clear();
                        } else {
                          _selectedEmployeeIds.addAll(_filteredEmployees.map((m) => m['id'].toString()));
                        }
                      }),
                      child: Text(isAllRowsSelected ? 'Deselect All' : 'Select All'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        final currentFilteredIds = _filteredEmployees.map((m) => m['id'].toString()).toSet();
                        final newSelection = currentFilteredIds.difference(_selectedEmployeeIds);
                        _selectedEmployeeIds.clear();
                        _selectedEmployeeIds.addAll(newSelection);
                      }),
                      child: const Text('Invert Selection'),
                    ),
                  ],
                ),
              ),

              // ------------------------------------------
              // DATA TABLE AREA
              // ------------------------------------------
              Expanded(
                child: _filteredEmployees.isEmpty
                    ? const Center(child: Text('No employees found matching configuration.'))
                    : SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Table(
                              defaultColumnWidth: const FixedColumnWidth(135),
                              columnWidths: const {
                                0: FixedColumnWidth(50), // Checkbox column
                                1: FixedColumnWidth(140), // First Name
                                2: FixedColumnWidth(140), // Last Name
                                3: FixedColumnWidth(110), // Phone
                                4: FixedColumnWidth(120), // Role
                                5: FixedColumnWidth(100), // Cluster
                                6: FixedColumnWidth(130), // Village
                                7: FixedColumnWidth(320), // School
                              },
                              border: TableBorder(
                                verticalInside: BorderSide(color: Colors.grey.shade300),
                                horizontalInside: BorderSide(color: Colors.grey.shade300, width: 1.0),
                                bottom: BorderSide(color: Colors.grey.shade300),
                                left: BorderSide(color: Colors.grey.shade300),
                                right: BorderSide(color: Colors.grey.shade300),
                              ),
                              children: [
                                // Master Header Row Definition Block
                                TableRow(
                                  decoration: BoxDecoration(color: Colors.grey.shade200),
                                  children: [
                                    TableCell(
                                      verticalAlignment: TableCellVerticalAlignment.middle,
                                      child: Center(
                                        child: Checkbox(
                                          value: isAllRowsSelected,
                                          tristate: _selectedEmployeeIds.isNotEmpty && !isAllRowsSelected,
                                          onChanged: (checked) {
                                            setState(() {
                                              if (checked == true) {
                                                _selectedEmployeeIds.addAll(_filteredEmployees.map((m) => m['id'].toString()));
                                              } else {
                                                _selectedEmployeeIds.clear();
                                              }
                                            });
                                          },
                                        ),
                                      ),
                                    ),
                                    _SortableHeader(
                                      label: "First Name",
                                      onSort: () => _onSort(0),
                                      onFilter: () => _showFilterMenu(0, "First Name"),
                                      isSorted: _sortColumnIndex == 0,
                                      isAscending: _isAscending,
                                      hasFilter: _selectedFirstNameFilters != null,
                                    ),
                                    _SortableHeader(
                                      label: "Last Name",
                                      onSort: () => _onSort(1),
                                      onFilter: () => _showFilterMenu(1, "Last Name"),
                                      isSorted: _sortColumnIndex == 1,
                                      isAscending: _isAscending,
                                      hasFilter: _selectedLastNameFilters != null,
                                    ),
                                    _SortableHeader(
                                      label: "Phone",
                                      onSort: () => _onSort(2),
                                      onFilter: () => _showFilterMenu(2, "Phone"),
                                      isSorted: _sortColumnIndex == 2,
                                      isAscending: _isAscending,
                                      hasFilter: _selectedPhoneFilters != null,
                                    ),
                                    _SortableHeader(
                                      label: "Role",
                                      onSort: () => _onSort(3),
                                      onFilter: () => _showFilterMenu(3, "Role"),
                                      isSorted: _sortColumnIndex == 3,
                                      isAscending: _isAscending,
                                      hasFilter: _selectedRoleFilters != null,
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
                                  ],
                                ),

                                // Dynamic Record Mapping Segment loops
                                ..._filteredEmployees.map((emp) {
                                  final empId = emp['id'].toString();
                                  final isRowSelected = _selectedEmployeeIds.contains(empId);

                                  return TableRow(
                                    decoration: BoxDecoration(color: isRowSelected ? Colors.blue.withValues(alpha: 0.04) : null),
                                    children: [
                                      TableCell(
                                        verticalAlignment: TableCellVerticalAlignment.middle,
                                        child: Center(
                                          child: Checkbox(
                                            value: isRowSelected,
                                            onChanged: (checked) {
                                              setState(() {
                                                if (checked == true) {
                                                  _selectedEmployeeIds.add(empId);
                                                } else {
                                                  _selectedEmployeeIds.remove(empId);
                                                }
                                              });
                                            },
                                          ),
                                        ),
                                      ),
                                      _DataCell(text: emp['first_name']?.toString() ?? "-", isBold: true),
                                      _DataCell(text: emp['last_name']?.toString() ?? "-"),
                                      _DataCell(text: emp['phone']?.toString() ?? "-"),
                                      _DataCell(text: UserRole.fromString(emp['role']).label),
                                      _DataCell(text: emp['cluster']?.toString() ?? "-"),
                                      _DataCell(text: emp['village']?.toString() ?? "-"),
                                      _DataCell(text: emp['school']?.toString() ?? "-"),
                                    ],
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ==========================================
// COMPONENT WIDGETS
// ==========================================

/// Reusable layout element for header cells that supports both tap-to-sort and tap-to-filter mechanics.
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
          // Sort trigger field interaction zone
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
                  const SizedBox(width: 2),
                  Icon(
                    isSorted ? (isAscending ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more,
                    size: 14,
                    color: isSorted ? AppTheme.primaryBlue : Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          // Filter trigger field interaction zone
          InkWell(
            onTap: onFilter,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: hasFilter ? AppTheme.primaryBlue.withValues(alpha: 0.15) : Colors.transparent),
              child: Icon(Icons.filter_alt, size: 16, color: hasFilter ? AppTheme.primaryBlue : Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Standardized cell format variant managing text-overflow clips and consistent content alignment properties.
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
