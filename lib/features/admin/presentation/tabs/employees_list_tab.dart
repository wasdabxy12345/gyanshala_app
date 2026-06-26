import 'dart:io';

import 'package:excel/excel.dart' hide TextSpan, Border;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide TextDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/models/user_role.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_html/html.dart' as html;

class EmployeeListTab extends ConsumerStatefulWidget {
  final String searchQuery;
  const EmployeeListTab({super.key, required this.searchQuery});

  @override
  ConsumerState<EmployeeListTab> createState() => EmployeeListTabState();
}

class EmployeeListTabState extends ConsumerState<EmployeeListTab> {
  final Set<String> _selectedEmployeeIds = {};
  int _sortColumnIndex = 0;
  bool _isAscending = true;

  Set<String>? _selectedFirstNameFilters;
  Set<String>? _selectedLastNameFilters;
  Set<String>? _selectedPhoneFilters;
  Set<String>? _selectedRoleFilters;
  Set<String>? _selectedGenderFilters;
  Set<String>? _selectedClusterFilters;
  Set<String>? _selectedVillageFilters;
  Set<String>? _selectedSchoolFilters;

  List<Map<String, dynamic>> _rawEmployees = [];
  List<Map<String, dynamic>> _filteredEmployees = [];
  RealtimeChannel? _realtimeChannel;

  List<Map<String, dynamic>> get filteredEmployees => _filteredEmployees;
  Set<String> get selectedEmployeeIds => _selectedEmployeeIds;

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  void _setupRealtimeSubscription() {
    _realtimeChannel?.unsubscribe();
    final supabase = ref.read(supabaseClientProvider);
    _realtimeChannel =
        supabase
            .channel('employee-mgmt-channel')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'profiles',
              callback: (payload) {
                if (mounted) setState(() {});
              },
            )
          ..subscribe();
  }

  // Stream provider converting future relational matrix lookups safely without stream.select breaks
  Stream<List<Map<String, dynamic>>> _fetchEmployeesStream() {
    final supabase = ref.watch(supabaseClientProvider);
    _setupRealtimeSubscription();

    return Stream.fromFuture(
      supabase
          .from('profiles')
          .select('*, profile_schools(schools(name, villages:village_id(name, clusters:cluster_id(name))))')
          .or('role.eq.shikshaMitra38,role.eq.shikshaMitra910,role.eq.mentorBV8')
          .then((data) => List<Map<String, dynamic>>.from(data as List)),
    );
  }

  Map<String, String> _extractLocationNames(Map<String, dynamic> row) {
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

  List<String> _extractFlatLocationList(Map<String, dynamic> row, String type) {
    final profileSchoolsList = row['profile_schools'] as List<dynamic>? ?? [];
    final Set<String> items = {};
    for (final relation in profileSchoolsList) {
      final school = relation['schools'] as Map<String, dynamic>?;
      if (school == null) continue;
      if (type == 'school') items.add(school['name']?.toString() ?? "-");
      final village = school['villages'] as Map<String, dynamic>?;
      if (village == null) continue;
      if (type == 'village') items.add(village['name']?.toString() ?? "-");
      final cluster = village['clusters'] as Map<String, dynamic>?;
      if (cluster != null && type == 'cluster') items.add(cluster['name']?.toString() ?? "-");
    }
    return items.isEmpty ? ["-"] : items.toList();
  }

  Future<void> exportExcel() async {
    try {
      if (_filteredEmployees.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No employee data found")));
        return;
      }
      final targetedEmployees = _selectedEmployeeIds.isNotEmpty
          ? _filteredEmployees.where((e) => _selectedEmployeeIds.contains(e['id'].toString())).toList()
          : _filteredEmployees;

      final excel = Excel.createExcel();
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }
      final Sheet sheet = excel['Sheet1'];
      final headers = ['First Name', 'Last Name', 'Phone', 'Role', 'Gender', 'Cluster(s)', 'Village(s)', 'School(s)'];
      sheet.appendRow(headers.map((e) => TextCellValue(e)).toList());

      for (final emp in targetedEmployees) {
        final loc = _extractLocationNames(emp);
        String cleanLoc(String val) => val.replaceAll("[LINE]", "").replaceAll("[SPACE]", "");

        sheet.appendRow([
          TextCellValue(emp['first_name']?.toString() ?? "-"),
          TextCellValue(emp['last_name']?.toString() ?? "-"),
          TextCellValue(emp['phone']?.toString() ?? "-"),
          TextCellValue(UserRole.fromString(emp['role']).label),
          TextCellValue(emp['gender']?.toString() ?? "-"),
          TextCellValue(cleanLoc(loc['cluster'] ?? "-")),
          TextCellValue(cleanLoc(loc['village'] ?? "-")),
          TextCellValue(cleanLoc(loc['school'] ?? "-")),
        ]);
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Failed to generate excel file');
      final dateSuffix = DateFormat('dd-MM-yyyy').format(DateTime.now());
      final String fileName = "Employee_List_$dateSuffix.xlsx";

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

  void _onSort(int columnIndex) {
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
    _filteredEmployees.sort((a, b) {
      String valA = "";
      String valB = "";

      if (_sortColumnIndex >= 5 && _sortColumnIndex <= 7) {
        final locKey = _sortColumnIndex == 5 ? 'cluster' : (_sortColumnIndex == 6 ? 'village' : 'school');
        valA = _extractLocationNames(a)[locKey] ?? "";
        valB = _extractLocationNames(b)[locKey] ?? "";
      } else {
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
            valA = UserRole.fromString(a['role']).label;
            valB = UserRole.fromString(b['role']).label;
            int compare = valA.toLowerCase().compareTo(valB.toLowerCase());
            return _isAscending ? compare : -compare;
          case 4:
            valA = a['gender']?.toString() ?? "";
            break;
        }
        if (_sortColumnIndex != 3) {
          valB = b[_getDatabaseKeyFromColumnIndex(_sortColumnIndex)]?.toString() ?? "";
        }
      }
      int compare = valA.toLowerCase().compareTo(valB.toLowerCase());
      return _isAscending ? compare : -compare;
    });
  }

  String _getDatabaseKeyFromColumnIndex(int index) {
    switch (index) {
      case 0:
        return 'first_name';
      case 1:
        return 'last_name';
      case 2:
        return 'phone';
      case 4:
        return 'gender';
      default:
        return '';
    }
  }

  void _applyAllFilters() {
    final query = widget.searchQuery.toLowerCase().trim();
    setState(() {
      _filteredEmployees = _rawRequestsFilterPass(_rawEmployees, query);
      _applySorting();
    });
  }

  List<Map<String, dynamic>> _rawRequestsFilterPass(List<Map<String, dynamic>> source, String searchStr) {
    return source.where((emp) {
      final firstName = emp['first_name']?.toString() ?? "";
      final lastName = emp['last_name']?.toString() ?? "";
      final fullName = "$firstName $lastName";
      final phone = emp['phone']?.toString() ?? "";
      final roleLabel = UserRole.fromString(emp['role']).label;
      final gender = emp['gender']?.toString() ?? "";

      final empClusters = _extractFlatLocationList(emp, 'cluster');
      final empVillages = _extractFlatLocationList(emp, 'village');
      final empSchools = _extractFlatLocationList(emp, 'school');

      final matchesSearch =
          searchStr.isEmpty ||
          fullName.toLowerCase().contains(searchStr) ||
          phone.toLowerCase().contains(searchStr) ||
          roleLabel.toLowerCase().contains(searchStr) ||
          gender.toLowerCase().contains(searchStr) ||
          empClusters.any((c) => c.toLowerCase().contains(searchStr)) ||
          empVillages.any((v) => v.toLowerCase().contains(searchStr)) ||
          empSchools.any((s) => s.toLowerCase().contains(searchStr));

      if (!matchesSearch) return false;

      if (_selectedFirstNameFilters != null && !_selectedFirstNameFilters!.contains(firstName)) return false;
      if (_selectedLastNameFilters != null && !_selectedLastNameFilters!.contains(lastName)) return false;
      if (_selectedPhoneFilters != null && !_selectedPhoneFilters!.contains(phone)) return false;
      if (_selectedRoleFilters != null && !_selectedRoleFilters!.contains(emp['role']?.toString())) return false;
      if (_selectedGenderFilters != null && !_selectedGenderFilters!.contains(gender)) return false;

      if (_selectedClusterFilters != null && !empClusters.any((c) => _selectedClusterFilters!.contains(c))) return false;
      if (_selectedVillageFilters != null && !empVillages.any((v) => _selectedVillageFilters!.contains(v))) return false;
      if (_selectedSchoolFilters != null && !empSchools.any((s) => _selectedSchoolFilters!.contains(s))) return false;

      return true;
    }).toList();
  }

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
          if (emp['gender'] != null) values.add(emp['gender'].toString());
          break;
        case 5:
          values.addAll(_extractFlatLocationList(emp, 'cluster'));
          break;
        case 6:
          values.addAll(_extractFlatLocationList(emp, 'village'));
          break;
        case 7:
          values.addAll(_extractFlatLocationList(emp, 'school'));
          break;
      }
    }
    return values.toList()..sort();
  }

  Future<void> _showFilterMenu(int columnIndex, String label) async {
    final allValues = _getUniqueValuesForColumn(columnIndex);
    Set<String> currentSelection;

    if (columnIndex == 0)
      currentSelection = _selectedFirstNameFilters != null ? Set.from(_selectedFirstNameFilters!) : Set.from(allValues);
    else if (columnIndex == 1)
      currentSelection = _selectedLastNameFilters != null ? Set.from(_selectedLastNameFilters!) : Set.from(allValues);
    else if (columnIndex == 2)
      currentSelection = _selectedPhoneFilters != null ? Set.from(_selectedPhoneFilters!) : Set.from(allValues);
    else if (columnIndex == 3)
      currentSelection = _selectedRoleFilters != null ? Set.from(_selectedRoleFilters!) : Set.from(allValues);
    else if (columnIndex == 4)
      currentSelection = _selectedGenderFilters != null ? Set.from(_selectedGenderFilters!) : Set.from(allValues);
    else if (columnIndex == 5)
      currentSelection = _selectedClusterFilters != null ? Set.from(_selectedClusterFilters!) : Set.from(allValues);
    else if (columnIndex == 6)
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
                  if (columnIndex == 0) _selectedFirstNameFilters = isAllSelected ? null : Set.from(currentSelection);
                  if (columnIndex == 1) _selectedLastNameFilters = isAllSelected ? null : Set.from(currentSelection);
                  if (columnIndex == 2) _selectedPhoneFilters = isAllSelected ? null : Set.from(currentSelection);
                  if (columnIndex == 3) _selectedRoleFilters = isAllSelected ? null : Set.from(currentSelection);
                  if (columnIndex == 4) _selectedGenderFilters = isAllSelected ? null : Set.from(currentSelection);
                  if (columnIndex == 5) _selectedClusterFilters = isAllSelected ? null : Set.from(currentSelection);
                  if (columnIndex == 6) _selectedVillageFilters = isAllSelected ? null : Set.from(currentSelection);
                  if (columnIndex == 7) _selectedSchoolFilters = isAllSelected ? null : Set.from(currentSelection);
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

  void _clearAllFilters() {
    setState(() {
      _selectedFirstNameFilters = null;
      _selectedLastNameFilters = null;
      _selectedPhoneFilters = null;
      _selectedRoleFilters = null;
      _selectedGenderFilters = null;
      _selectedClusterFilters = null;
      _selectedVillageFilters = null;
      _selectedSchoolFilters = null;
      _applyAllFilters();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _fetchEmployeesStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error resolving rows: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          _rawEmployees = snapshot.data!;

          // Schedules filter execution post render pass safely matching frame loops
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _applyAllFilters();
            }
          });

          bool hasActiveFilters = [
            _selectedFirstNameFilters,
            _selectedLastNameFilters,
            _selectedPhoneFilters,
            _selectedRoleFilters,
            _selectedGenderFilters,
            _selectedClusterFilters,
            _selectedVillageFilters,
            _selectedSchoolFilters,
          ].any((f) => f != null);

          bool isAllRowsSelected = _filteredEmployees.isNotEmpty && _selectedEmployeeIds.length == _filteredEmployees.length;

          return Column(
            children: [
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
                                      label: "Gender",
                                      onSort: () => _onSort(4),
                                      onFilter: () => _showFilterMenu(4, "Gender"),
                                      isSorted: _sortColumnIndex == 4,
                                      isAscending: _isAscending,
                                      hasFilter: _selectedGenderFilters != null,
                                    ),
                                    _SortableHeader(
                                      label: "Cluster",
                                      onSort: () => _onSort(5),
                                      onFilter: () => _showFilterMenu(5, "Cluster"),
                                      isSorted: _sortColumnIndex == 5,
                                      isAscending: _isAscending,
                                      hasFilter: _selectedClusterFilters != null,
                                    ),
                                    _SortableHeader(
                                      label: "Village",
                                      onSort: () => _onSort(6),
                                      onFilter: () => _showFilterMenu(6, "Village"),
                                      isSorted: _sortColumnIndex == 6,
                                      isAscending: _isAscending,
                                      hasFilter: _selectedVillageFilters != null,
                                    ),
                                    _SortableHeader(
                                      label: "School",
                                      onSort: () => _onSort(7),
                                      onFilter: () => _showFilterMenu(7, "School"),
                                      isSorted: _sortColumnIndex == 7,
                                      isAscending: _isAscending,
                                      hasFilter: _selectedSchoolFilters != null,
                                    ),
                                  ],
                                ),
                                ..._filteredEmployees.map((emp) {
                                  final empId = emp['id'].toString();
                                  final isRowSelected = _selectedEmployeeIds.contains(empId);
                                  final locations = _extractLocationNames(emp);

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
                                      _DataCell(text: emp['gender']?.toString() ?? "-"),
                                      _DataCell(text: locations['cluster'] ?? "-"),
                                      _DataCell(text: locations['village'] ?? "-"),
                                      _DataCell(text: locations['school'] ?? "-"),
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
        mainAxisSize: MainAxisSize.min,
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
                  const SizedBox(width: 2),
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
    return TableCell(
      // CHANGE THIS FROM .middle TO .top TO FIX THE ALIGNMENT SHIFT
      verticalAlignment: TableCellVerticalAlignment.top,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: lines.map((line) {
          bool drawDivider = line.startsWith("[LINE]");
          bool addLineSpacing = line.startsWith("[SPACE]");
          String cleanText = line.replaceFirst("[LINE]", "").replaceFirst("[SPACE]", "");

          if (cleanText.isEmpty) {
            cleanText = "\u200B";
          }

          Widget lineWidget = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 3),
            child: Container(
              constraints: const BoxConstraints(minHeight: 22),
              alignment: Alignment.centerLeft,
              child: Text(
                cleanText,
                style: TextStyle(
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                  color: cleanText == "-" || cleanText == "\u200B" ? Colors.transparent : AppTheme.textPrimary,
                ),
              ),
            ),
          );

          if (drawDivider) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Divider(color: Colors.grey.shade300, thickness: 0.8, height: 1),
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
      ),
    );
  }
}
