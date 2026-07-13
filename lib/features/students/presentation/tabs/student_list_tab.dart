import 'dart:io';

import 'package:excel/excel.dart' hide TextSpan, Border;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide TextDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:gyanshala_app/features/students/controller/student_controller.dart';
import 'package:gyanshala_app/features/students/presentation/views/add_student_screen.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_html/html.dart' as html;

class StudentListTab extends ConsumerStatefulWidget {
  final String searchQuery;
  const StudentListTab({super.key, required this.searchQuery});

  @override
  ConsumerState<StudentListTab> createState() => StudentListTabState();
}

class StudentListTabState extends ConsumerState<StudentListTab> {
  final Set<String> _selectedStudentIds = {};
  int _sortColumnIndex = 0;
  bool _isAscending = true;

  Set<String>? _selectedLocalIdFilters;
  Set<String>? _selectedGradeFilters;
  Set<String>? _selectedGenderFilters;
  Set<String>? _selectedClusterFilters;
  Set<String>? _selectedVillageFilters;
  Set<String>? _selectedSchoolFilters;

  List<Map<String, dynamic>> _rawStudents = [];
  List<Map<String, dynamic>> _filteredStudents = [];
  RealtimeChannel? _realtimeChannel;

  List<Map<String, dynamic>> _allClusters = [];
  Map<String, List<Map<String, dynamic>>> _villagesByCluster = {};
  Map<String, List<Map<String, dynamic>>> _schoolsByVillage = {};

  bool _isMetadataLoaded = false;

  List<Map<String, dynamic>> get filteredStudents => _filteredStudents;
  Set<String> get selectedStudentIds => _selectedStudentIds;

  @override
  void initState() {
    super.initState();
    _loadLocationMetadata();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadLocationMetadata() async {
    try {
      final controller = ref.read(studentProvider.notifier);

      // 1. Fetch all clusters
      final clusters = await controller.getClusters();
      if (clusters.isEmpty || !mounted) return;

      // Extract all cluster IDs
      final List<String> clusterIds = clusters.map((c) => c['id'].toString()).toList();

      // 2. BATCH FETCH: Get ALL villages for these clusters in ONE query
      // (Ensure your controller supports passing a list, or query Supabase using .in_('cluster_id', clusterIds))
      final allVillages = await controller.getVillagesForClusters(clusterIds);

      final List<String> villageIds = allVillages.map((v) => v['id'].toString()).toList();

      // 3. BATCH FETCH: Get ALL schools for these villages in ONE query
      final allSchools = await controller.getSchoolsForVillages(villageIds);

      // 4. Map them locally in-memory (Super fast!)
      Map<String, List<Map<String, dynamic>>> villageMap = {};
      for (var vil in allVillages) {
        final cId = vil['cluster_id'].toString();
        villageMap.putIfAbsent(cId, () => []).add(vil);
      }

      Map<String, List<Map<String, dynamic>>> schoolMap = {};
      for (var sch in allSchools) {
        final vId = sch['village_id'].toString();
        schoolMap.putIfAbsent(vId, () => []).add(sch);
      }

      if (!mounted) return;

      setState(() {
        _allClusters = clusters;
        _villagesByCluster = villageMap;
        _schoolsByVillage = schoolMap;
        _isMetadataLoaded = true;
      });
    } catch (e) {
      debugPrint("Failed to build metadata cache efficiently: $e");
    }
  }

  void _setupRealtimeSubscription() {
    _realtimeChannel?.unsubscribe();
    final supabase = ref.read(supabaseClientProvider);
    _realtimeChannel =
        supabase
            .channel('student-mgmt-channel')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'students',
              callback: (payload) {
                if (mounted) setState(() {});
              },
            )
          ..subscribe();
  }

  Stream<List<Map<String, dynamic>>> _fetchStudentsStream() {
    final supabase = ref.watch(supabaseClientProvider);
    _setupRealtimeSubscription();
    return Stream.fromFuture(
      supabase
          .from('students')
          .select('*, schools(id, name, village_id, villages:village_id(id, name, cluster_id, clusters:cluster_id(id, name)))')
          .then((data) {
            return List<Map<String, dynamic>>.from(data as List);
          }),
    );
  }

  Map<String, String> _extractLocationNames(Map<String, dynamic> row) {
    final school = row['schools'] as Map<String, dynamic>?;
    if (school == null) return {'cluster': '-', 'village': '-', 'school': '-'};
    final schoolName = school['name']?.toString() ?? "-";
    final village = school['villages'] as Map<String, dynamic>?;
    final villageName = village?['name']?.toString() ?? "-";
    final cluster = village?['clusters'] as Map<String, dynamic>?;
    final clusterName = cluster?['name']?.toString() ?? "-";
    return {'cluster': clusterName, 'village': villageName, 'school': schoolName};
  }

  List<String> _extractFlatLocationList(Map<String, dynamic> row, String type) {
    final school = row['schools'] as Map<String, dynamic>?;
    if (school == null) return ["-"];
    if (type == 'school') return [school['name']?.toString() ?? "-"];
    final village = school['villages'] as Map<String, dynamic>?;
    if (village == null) return ["-"];
    if (type == 'village') return [village['name']?.toString() ?? "-"];
    final cluster = village['clusters'] as Map<String, dynamic>?;
    if (cluster != null && type == 'cluster') return [cluster['name']?.toString() ?? "-"];
    return ["-"];
  }

  Future<void> _updateCell(String id, Map<String, dynamic> updateValue) async {
    final controller = ref.read(studentProvider.notifier);
    final scaffold = ScaffoldMessenger.of(context);
    final success = await controller.updateStudent(id, updateValue);
    if (!success) {
      scaffold.showSnackBar(
        const SnackBar(content: Text("Failed to update field metadata. Check RLS or logs."), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteSelectedStudents() async {
    final scaffold = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Deletion"),
        content: Text("Are you sure you want to delete ${_selectedStudentIds.length} selected student(s)?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ref.read(studentProvider.notifier).deleteStudents(_selectedStudentIds.toList());
      if (success) {
        scaffold.showSnackBar(const SnackBar(content: Text("Selected students deleted completely.")));
        setState(() {
          _selectedStudentIds.clear();
        });
      } else {
        scaffold.showSnackBar(
          const SnackBar(content: Text("Deletion operation was not executed successfully."), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> exportExcel() async {
    try {
      if (_filteredStudents.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No student data found")));
        return;
      }
      final targetedStudents = _selectedStudentIds.isNotEmpty
          ? _filteredStudents.where((e) => _selectedStudentIds.contains(e['id'].toString())).toList()
          : _filteredStudents;
      final excel = Excel.createExcel();
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }
      final Sheet sheet = excel['Sheet1'];
      final headers = ['Student Local ID', 'Grade', 'Gender', 'Cluster', 'Village', 'School'];
      sheet.appendRow(headers.map((e) => TextCellValue(e)).toList());
      for (final std in targetedStudents) {
        final loc = _extractLocationNames(std);
        sheet.appendRow([
          TextCellValue(std['student_id_local']?.toString() ?? "-"),
          TextCellValue(std['grade']?.toString() ?? "-"),
          TextCellValue(std['gender']?.toString() ?? "-"),
          TextCellValue(loc['cluster'] ?? "-"),
          TextCellValue(loc['village'] ?? "-"),
          TextCellValue(loc['school'] ?? "-"),
        ]);
      }
      final bytes = excel.encode();
      if (bytes == null) throw Exception('Failed to generate excel file');
      final dateSuffix = DateFormat('dd-MM-yyyy').format(DateTime.now());
      final String fileName = "Student_List_$dateSuffix.xlsx";
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
    _filteredStudents.sort((a, b) {
      String valA = "";
      String valB = "";
      if (_sortColumnIndex >= 3 && _sortColumnIndex <= 5) {
        final locKey = _sortColumnIndex == 3 ? 'cluster' : (_sortColumnIndex == 4 ? 'village' : 'school');
        valA = _extractLocationNames(a)[locKey] ?? "";
        valB = _extractLocationNames(b)[locKey] ?? "";
      } else {
        switch (_sortColumnIndex) {
          case 0:
            valA = a['student_id_local']?.toString() ?? "";
            valB = b['student_id_local']?.toString() ?? "";
            break;
          case 1:
            valA = a['grade']?.toString() ?? "";
            valB = b['grade']?.toString() ?? "";
            break;
          case 2:
            valA = a['gender']?.toString() ?? "";
            valB = b['gender']?.toString() ?? "";
            break;
        }
      }
      int compare = valA.toLowerCase().compareTo(valB.toLowerCase());
      return _isAscending ? compare : -compare;
    });
  }

  void _applyAllFilters() {
    final query = widget.searchQuery.toLowerCase().trim();
    setState(() {
      _filteredStudents = _rawRequestsFilterPass(_rawStudents, query);
      _applySorting();
    });
  }

  List<Map<String, dynamic>> _rawRequestsFilterPass(List<Map<String, dynamic>> source, String searchStr) {
    return source.where((std) {
      final localId = std['student_id_local']?.toString() ?? "";
      final gradeVal = std['grade']?.toString() ?? "";
      final displayGrade = gradeVal == '0' ? 'BV' : gradeVal;
      final gender = std['gender']?.toString() ?? "";
      final stdClusters = _extractFlatLocationList(std, 'cluster');
      final stdVillages = _extractFlatLocationList(std, 'village');
      final stdSchools = _extractFlatLocationList(std, 'school');

      final matchesSearch =
          searchStr.isEmpty ||
          localId.toLowerCase().contains(searchStr) ||
          displayGrade.toLowerCase().contains(searchStr) ||
          gender.toLowerCase().contains(searchStr) ||
          stdClusters.any((c) => c.toLowerCase().contains(searchStr)) ||
          stdVillages.any((v) => v.toLowerCase().contains(searchStr)) ||
          stdSchools.any((s) => s.toLowerCase().contains(searchStr));

      if (!matchesSearch) return false;
      if (_selectedLocalIdFilters != null && !_selectedLocalIdFilters!.contains(localId)) return false;
      if (_selectedGradeFilters != null && !_selectedGradeFilters!.contains(gradeVal)) return false;
      if (_selectedGenderFilters != null && !_selectedGenderFilters!.contains(gender)) return false;
      if (_selectedClusterFilters != null && !stdClusters.any((c) => _selectedClusterFilters!.contains(c))) return false;
      if (_selectedVillageFilters != null && !stdVillages.any((v) => _selectedVillageFilters!.contains(v))) return false;
      if (_selectedSchoolFilters != null && !stdSchools.any((s) => _selectedSchoolFilters!.contains(s))) return false;
      return true;
    }).toList();
  }

  List<String> _getUniqueValuesForColumn(int columnIndex) {
    final Set<String> values = {};
    for (final std in _rawStudents) {
      switch (columnIndex) {
        case 0:
          if (std['student_id_local'] != null) values.add(std['student_id_local'].toString());
          break;
        case 1:
          if (std['grade'] != null) values.add(std['grade'].toString());
          break;
        case 2:
          if (std['gender'] != null) values.add(std['gender'].toString());
          break;
        case 3:
          values.addAll(_extractFlatLocationList(std, 'cluster'));
          break;
        case 4:
          values.addAll(_extractFlatLocationList(std, 'village'));
          break;
        case 5:
          values.addAll(_extractFlatLocationList(std, 'school'));
          break;
      }
    }
    return values.toList()..sort();
  }

  Future<void> _showFilterMenu(int columnIndex, String label) async {
    final allValues = _getUniqueValuesForColumn(columnIndex);
    Set<String> currentSelection;
    if (columnIndex == 0)
      currentSelection = _selectedLocalIdFilters != null ? Set.from(_selectedLocalIdFilters!) : Set.from(allValues);
    else if (columnIndex == 1)
      currentSelection = _selectedGradeFilters != null ? Set.from(_selectedGradeFilters!) : Set.from(allValues);
    else if (columnIndex == 2)
      currentSelection = _selectedGenderFilters != null ? Set.from(_selectedGenderFilters!) : Set.from(allValues);
    else if (columnIndex == 3)
      currentSelection = _selectedClusterFilters != null ? Set.from(_selectedClusterFilters!) : Set.from(allValues);
    else if (columnIndex == 4)
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
                      String itemDisplay = value;
                      if (columnIndex == 1 && value == '0') itemDisplay = 'BV';
                      return CheckboxListTile(
                        dense: true,
                        value: currentSelection.contains(value),
                        title: Text(itemDisplay),
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
                  if (columnIndex == 0) _selectedLocalIdFilters = isAllSelected ? null : Set.from(currentSelection);
                  if (columnIndex == 1) _selectedGradeFilters = isAllSelected ? null : Set.from(currentSelection);
                  if (columnIndex == 2) _selectedGenderFilters = isAllSelected ? null : Set.from(currentSelection);
                  if (columnIndex == 3) _selectedClusterFilters = isAllSelected ? null : Set.from(currentSelection);
                  if (columnIndex == 4) _selectedVillageFilters = isAllSelected ? null : Set.from(currentSelection);
                  if (columnIndex == 5) _selectedSchoolFilters = isAllSelected ? null : Set.from(currentSelection);
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
      _selectedLocalIdFilters = null;
      _selectedGradeFilters = null;
      _selectedGenderFilters = null;
      _selectedClusterFilters = null;
      _selectedVillageFilters = null;
      _selectedSchoolFilters = null;
      _applyAllFilters();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isStudentLoading = ref.watch(studentProvider);
    if (!_isMetadataLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: isStudentLoading
            ? null
            : () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const AddStudentScreen()));
              },
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        child: isStudentLoading ? const SizedBox(child: CircularProgressIndicator(color: Colors.white)) : const Icon(Icons.add),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _fetchStudentsStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error resolving rows: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          _rawStudents = snapshot.data!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _applyAllFilters();
            }
          });
          bool hasActiveFilters = [
            _selectedLocalIdFilters,
            _selectedGradeFilters,
            _selectedGenderFilters,
            _selectedClusterFilters,
            _selectedVillageFilters,
            _selectedSchoolFilters,
          ].any((f) => f != null);
          bool isAllRowsSelected = _filteredStudents.isNotEmpty && _selectedStudentIds.length == _filteredStudents.length;

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
                        '${_selectedStudentIds.length} Selected',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (_selectedStudentIds.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.delete_forever, color: Colors.red),
                        tooltip: "Delete Selected",
                        onPressed: _deleteSelectedStudents,
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
                          _selectedStudentIds.clear();
                        } else {
                          _selectedStudentIds.addAll(_filteredStudents.map((m) => m['id'].toString()));
                        }
                      }),
                      child: Text(isAllRowsSelected ? 'Deselect All' : 'Select All'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        final currentFilteredIds = _filteredStudents.map((m) => m['id'].toString()).toSet();
                        final newSelection = currentFilteredIds.difference(_selectedStudentIds);
                        _selectedStudentIds.clear();
                        _selectedStudentIds.addAll(newSelection);
                      }),
                      child: const Text('Invert Selection'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _filteredStudents.isEmpty
                    ? const Center(child: Text('No students found matching configuration.'))
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
                                          tristate: _selectedStudentIds.isNotEmpty && !isAllRowsSelected,
                                          onChanged: (checked) {
                                            setState(() {
                                              if (checked == true) {
                                                _selectedStudentIds.addAll(_filteredStudents.map((m) => m['id'].toString()));
                                              } else {
                                                _selectedStudentIds.clear();
                                              }
                                            });
                                          },
                                        ),
                                      ),
                                    ),
                                    _SortableHeader(
                                      label: "Student Local ID",
                                      onSort: () => _onSort(0),
                                      onFilter: () => _showFilterMenu(0, "Student Local ID"),
                                      isSorted: _sortColumnIndex == 0,
                                      isAscending: _isAscending,
                                      hasFilter: _selectedLocalIdFilters != null,
                                    ),
                                    _SortableHeader(
                                      label: "Grade",
                                      onSort: () => _onSort(1),
                                      onFilter: () => _showFilterMenu(1, "Grade"),
                                      isSorted: _sortColumnIndex == 1,
                                      isAscending: _isAscending,
                                      hasFilter: _selectedGradeFilters != null,
                                    ),
                                    _SortableHeader(
                                      label: "Gender",
                                      onSort: () => _onSort(2),
                                      onFilter: () => _showFilterMenu(2, "Gender"),
                                      isSorted: _sortColumnIndex == 2,
                                      isAscending: _isAscending,
                                      hasFilter: _selectedGenderFilters != null,
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
                                  ],
                                ),
                                ..._filteredStudents.map((std) {
                                  final stdId = std['id'].toString();
                                  final isRowSelected = _selectedStudentIds.contains(stdId);

                                  // Safely unpack relational joins
                                  final currentSchool = std['schools'] as Map<String, dynamic>?;
                                  final currentVillage = currentSchool?['villages'] as Map<String, dynamic>?;
                                  final currentCluster = currentVillage?['clusters'] as Map<String, dynamic>?;

                                  final clusterId = currentCluster?['id']?.toString();
                                  final villageId = currentVillage?['id']?.toString();
                                  final schoolId = currentSchool?['id']?.toString();

                                  // Filter child arrays out of cache maps
                                  final availableVillages = clusterId != null ? (_villagesByCluster[clusterId] ?? []) : [];
                                  final availableSchools = villageId != null ? (_schoolsByVillage[villageId] ?? []) : [];

                                  return TableRow(
                                    decoration: BoxDecoration(color: isRowSelected ? Colors.blue.withAlpha(10) : null),
                                    children: [
                                      TableCell(
                                        verticalAlignment: TableCellVerticalAlignment.middle,
                                        child: Center(
                                          child: Checkbox(
                                            value: isRowSelected,
                                            onChanged: (checked) {
                                              setState(() {
                                                if (checked == true) {
                                                  _selectedStudentIds.add(stdId);
                                                } else {
                                                  _selectedStudentIds.remove(stdId);
                                                }
                                              });
                                            },
                                          ),
                                        ),
                                      ),
                                      // Local ID: Editable Text Cell
                                      TableCell(
                                        verticalAlignment: TableCellVerticalAlignment.middle,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                          child: SizedBox(
                                            width: 140,
                                            child: TextFormField(
                                              initialValue: std['student_id_local']?.toString() ?? "",
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                              decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                                              onFieldSubmitted: (newVal) =>
                                                  _updateCell(stdId, {'student_id_local': newVal.trim()}),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Grade: Dropdown selector (0 map -> BV)
                                      TableCell(
                                        verticalAlignment: TableCellVerticalAlignment.middle,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                          child: DropdownButton<int>(
                                            value: std['grade'] != null ? int.parse(std['grade'].toString()) : 1,
                                            isDense: true,
                                            underline: const SizedBox(),
                                            items: [
                                              const DropdownMenuItem(value: 0, child: Text('BV')),
                                              ...List.generate(
                                                10,
                                                (idx) => idx + 1,
                                              ).map((g) => DropdownMenuItem(value: g, child: Text('$g'))),
                                            ],
                                            onChanged: (newGrade) {
                                              if (newGrade != null) _updateCell(stdId, {'grade': newGrade});
                                            },
                                          ),
                                        ),
                                      ),
                                      // Gender: Dropdown selector
                                      TableCell(
                                        verticalAlignment: TableCellVerticalAlignment.middle,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                          child: DropdownButton<String>(
                                            value: ['Male', 'Female', 'Other'].contains(std['gender'])
                                                ? std['gender'].toString()
                                                : 'Male',
                                            isDense: true,
                                            underline: const SizedBox(),
                                            items: [
                                              'Male',
                                              'Female',
                                              'Other',
                                            ].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                                            onChanged: (newGender) {
                                              if (newGender != null) _updateCell(stdId, {'gender': newGender});
                                            },
                                          ),
                                        ),
                                      ),
                                      // Cluster Dropdown
                                      TableCell(
                                        verticalAlignment: TableCellVerticalAlignment.middle,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                          child: DropdownButton<String>(
                                            value: _allClusters.any((c) => c['id'].toString() == clusterId) ? clusterId : null,
                                            isDense: true,
                                            hint: const Text("-"),
                                            underline: const SizedBox(),
                                            items: _allClusters
                                                .map(
                                                  (c) =>
                                                      DropdownMenuItem<String>(value: c['id'].toString(), child: Text(c['name'])),
                                                )
                                                .toList(),
                                            onChanged: (newClusterId) async {
                                              if (newClusterId != null && newClusterId != clusterId) {
                                                // Cascade logic: reset lower dependents to valid fallback if possible
                                                final replacementVils = _villagesByCluster[newClusterId] ?? [];
                                                final targetVilId = replacementVils.isNotEmpty
                                                    ? replacementVils.first['id'].toString()
                                                    : null;
                                                final replacementSchs = targetVilId != null
                                                    ? (_schoolsByVillage[targetVilId] ?? [])
                                                    : [];
                                                final targetSchId = replacementSchs.isNotEmpty
                                                    ? replacementSchs.first['id'].toString()
                                                    : null;

                                                if (targetSchId != null) {
                                                  await _updateCell(stdId, {'school_id': targetSchId});
                                                }
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                      // Village Dropdown
                                      TableCell(
                                        verticalAlignment: TableCellVerticalAlignment.middle,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                          child: DropdownButton<String>(
                                            value: availableVillages.any((v) => v['id'].toString() == villageId)
                                                ? villageId
                                                : null,
                                            isDense: true,
                                            hint: const Text("-"),
                                            underline: const SizedBox(),
                                            items: availableVillages
                                                .map(
                                                  (v) =>
                                                      DropdownMenuItem<String>(value: v['id'].toString(), child: Text(v['name'])),
                                                )
                                                .toList(),
                                            onChanged: (newVillageId) async {
                                              if (newVillageId != null && newVillageId != villageId) {
                                                final replacementSchs = _schoolsByVillage[newVillageId] ?? [];
                                                final targetSchId = replacementSchs.isNotEmpty
                                                    ? replacementSchs.first['id'].toString()
                                                    : null;
                                                if (targetSchId != null) {
                                                  await _updateCell(stdId, {'school_id': targetSchId});
                                                }
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                      // School Dropdown
                                      TableCell(
                                        verticalAlignment: TableCellVerticalAlignment.middle,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                          child: DropdownButton<String>(
                                            value: availableSchools.any((s) => s['id'].toString() == schoolId) ? schoolId : null,
                                            isDense: true,
                                            hint: const Text("-"),
                                            underline: const SizedBox(),
                                            items: availableSchools
                                                .map(
                                                  (s) =>
                                                      DropdownMenuItem<String>(value: s['id'].toString(), child: Text(s['name'])),
                                                )
                                                .toList(),
                                            onChanged: (newSchoolId) {
                                              if (newSchoolId != null) {
                                                _updateCell(stdId, {'school_id': newSchoolId});
                                              }
                                            },
                                          ),
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
