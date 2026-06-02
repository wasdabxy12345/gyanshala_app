import 'dart:io';

import 'package:excel/excel.dart' hide TextSpan, Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocationManagementScreen extends StatefulWidget {
  const LocationManagementScreen({super.key});
  @override
  State<LocationManagementScreen> createState() => _LocationManagementScreenState();
}

class _LocationManagementScreenState extends State<LocationManagementScreen> {
  bool _isAscending = true;
  int _sortColumnIndex = 0;
  final _supabase = Supabase.instance.client;
  List<dynamic> _hierarchy = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  List<dynamic> _filteredHierarchy = [];
  Set<String>? _selectedClusterFilters;
  Set<String>? _selectedVillageFilters;
  Set<String>? _selectedSchoolFilters;
  @override
  void initState() {
    super.initState();
    _fetchHierarchy();
  }

  void _onSort(int columnIndex) {
    setState(() {
      if (_sortColumnIndex == columnIndex) {
        _isAscending = !_isAscending;
      } else {
        _sortColumnIndex = columnIndex;
        _isAscending = true;
      }
      _hierarchy.sort((a, b) {
        int compare = (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase());
        return _isAscending ? compare : -compare;
      });
      for (var cluster in _hierarchy) {
        List villages = cluster['villages'] ?? [];
        if (columnIndex == 1) {
          villages.sort((a, b) {
            int vCompare = (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase());
            return _isAscending ? vCompare : -vCompare;
          });
        }
        for (var village in villages) {
          List schools = village['schools'] ?? [];
          if (columnIndex == 2) {
            schools.sort((a, b) {
              int sCompare = (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase());
              return _isAscending ? sCompare : -sCompare;
            });
          }
        }
        _applyAllFilters();
      }
    });
  }

  Future<void> _importFromExcel() async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Excel import is not supported on web. Please use the manual boundary picker instead.")),
        );
      }
      return;
    }
    FilePickerResult? result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv']);
    if (result == null) return;
    setState(() => _isLoading = true);
    int importedCount = 0;
    try {
      var bytes = File(result.files.first.path!).readAsBytesSync();
      var excel = Excel.decodeBytes(bytes);
      String? lastClusterName;
      String? lastVillageName;
      for (var table in excel.tables.keys) {
        var sheet = excel.tables[table];
        if (sheet == null) continue;
        for (int i = 0; i < sheet.maxRows; i++) {
          var row = sheet.rows[i];
          if (row.length < 3) continue;
          final rawCluster = row[0]?.value?.toString().trim();
          final rawVillage = row[1]?.value?.toString().trim();
          final schoolName = row[2]?.value?.toString().trim();
          if (rawCluster?.toLowerCase() == 'cluster' && schoolName?.toLowerCase() == 'school') {
            continue;
          }
          if (rawCluster != null && rawCluster.isNotEmpty) {
            lastClusterName = rawCluster;
          }
          if (rawVillage != null && rawVillage.isNotEmpty) {
            lastVillageName = rawVillage;
          }
          if (lastClusterName == null || lastClusterName.isEmpty) continue;
          if (schoolName == null || schoolName.isEmpty) continue;
          final clusterResp = await _supabase
              .from('clusters')
              .upsert({'name': lastClusterName}, onConflict: 'name')
              .select()
              .single();
          final String clusterId = clusterResp['id'].toString();
          String? villageId;
          if (lastVillageName != null && lastVillageName.isNotEmpty) {
            final villageResp = await _supabase
                .from('villages')
                .upsert({'name': lastVillageName, 'cluster_id': clusterId}, onConflict: 'name, cluster_id')
                .select()
                .single();
            villageId = villageResp['id'].toString();
          }
          if (villageId != null) {
            await _supabase.from('schools').upsert({'name': schoolName, 'village_id': villageId}, onConflict: 'name, village_id');
          }
          importedCount++;
        }
      }
      await _fetchHierarchy();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Successfully processed $importedCount rows")));
      }
    } catch (e) {
      debugPrint("Import Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Import Error: ${e.toString()}")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchHierarchy() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final data = await _supabase
          .from('clusters')
          .select('id, name, villages(id, name, cluster_id, schools(id, name, village_id, boundary))')
          .order('name', ascending: true);
      if (mounted) {
        setState(() {
          _hierarchy = data;
          _sortColumnIndex = 0;
          _isAscending = true;
          if (_searchController.text.isNotEmpty) {
            _applyAllFilters();
          } else {
            _filteredHierarchy = data;
          }
        });
      }
    } catch (e) {
      debugPrint("Fetch error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error fetching data: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showAddDialog(String type) async {
    final nameController = TextEditingController();
    String? selectedClusterId;
    String? selectedVillageId;
    List<LatLng> schoolBoundary = [];
    Future<String?> showQuickAdd(String parentType) async {
      final quickController = TextEditingController();
      return showDialog<String>(
        context: context,
        builder: (qCtx) => AlertDialog(
          title: Text("Quick Add $parentType"),
          content: TextField(
            controller: quickController,
            decoration: InputDecoration(labelText: "$parentType Name"),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(qCtx), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () async {
                final name = quickController.text.trim();
                if (name.isEmpty) return;
                final table = parentType == 'Cluster' ? 'clusters' : 'villages';
                final Map<String, dynamic> insertData = {'name': name};
                if (parentType == 'Village') {
                  insertData['cluster_id'] = selectedClusterId;
                }
                final response = await _supabase.from(table).insert(insertData).select().single();
                await _fetchHierarchy();
                if (qCtx.mounted) Navigator.pop(qCtx, response['id'].toString());
              },
              child: const Text("Create"),
            ),
          ],
        ),
      );
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text("Add New $type"),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (type == 'School') ...[
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _importFromExcel();
                      },
                      icon: const Icon(Icons.upload_file),
                      label: const Text("Import Schools via Excel"),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40), foregroundColor: Colors.teal),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text("OR MANUALLY", style: TextStyle(fontSize: 10, color: Colors.grey)),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                    ),
                    const Text(
                      "Draw School Boundary (Tap 3+ points)",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (type == 'Village' || type == 'School')
                    DropdownButtonFormField<String>(
                      initialValue: selectedClusterId,
                      hint: const Text("Select Cluster"),
                      items: [
                        const DropdownMenuItem(
                          value: "ADD_NEW",
                          child: Text(
                            "+ Add New Cluster...",
                            style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                          ),
                        ),
                        ..._hierarchy.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['name']))),
                      ],
                      onChanged: (val) async {
                        if (val == "ADD_NEW") {
                          final newId = await showQuickAdd("Cluster");
                          if (newId != null) setDialogState(() => selectedClusterId = newId);
                        } else {
                          setDialogState(() {
                            selectedClusterId = val;
                            selectedVillageId = null;
                          });
                        }
                      },
                    ),
                  if (type == 'School') ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedVillageId,
                      hint: const Text("Select Village"),
                      disabledHint: const Text("Select a Cluster first"),
                      items: selectedClusterId == null
                          ? []
                          : [
                              const DropdownMenuItem(
                                value: "ADD_NEW",
                                child: Text(
                                  "+ Add New Village...",
                                  style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                                ),
                              ),
                              ...(_hierarchy.firstWhere((c) => c['id'].toString() == selectedClusterId)['villages'] as List).map(
                                (v) => DropdownMenuItem(value: v['id'].toString(), child: Text(v['name'])),
                              ),
                            ],
                      onChanged: selectedClusterId == null
                          ? null
                          : (val) async {
                              if (val == "ADD_NEW") {
                                final newId = await showQuickAdd("Village");
                                if (newId != null) setDialogState(() => selectedVillageId = newId);
                              } else {
                                setDialogState(() => selectedVillageId = val);
                              }
                            },
                    ),
                  ],
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(labelText: "$type Name"),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                final Map<String, dynamic> insertData = {'name': name};
                String table = '';
                try {
                  if (type == 'Cluster') {
                    table = 'clusters';
                  } else if (type == 'Village') {
                    if (selectedClusterId == null) return;
                    table = 'villages';
                    insertData['cluster_id'] = selectedClusterId;
                  } else if (type == 'School') {
                    if (selectedVillageId == null) return;
                    table = 'schools';
                    insertData['village_id'] = selectedVillageId;
                    if (schoolBoundary.length >= 3) {
                      var coords = schoolBoundary.map((p) => [p.longitude, p.latitude]).toList();
                      coords.add(coords.first);
                      insertData['boundary'] = {
                        'type': 'Polygon',
                        'coordinates': [coords],
                      };
                    } else {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text("Please draw a valid boundary with at least 3 points.")));
                      return;
                    }
                  }
                  try {
                    await _supabase.from(table).insert(insertData);
                    if (ctx.mounted) Navigator.pop(ctx);
                    _fetchHierarchy();
                  } catch (e) {
                    debugPrint("Insert Error: $e");
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error saving $type: ${e.toString()}")));
                    }
                  }
                } catch (e) {
                  debugPrint("Save Error: $e");
                }
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(String type, dynamic entity) async {
    String warning = "";
    if (type == 'Cluster') {
      warning = "\n\nWarning: Deleting this Cluster will also delete ALL associated Villages and Schools!";
    } else if (type == 'Village') {
      warning = "\n\nWarning: Deleting this Village will also delete ALL associated Schools!";
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Delete $type?"),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(color: Colors.black, fontSize: 16),
            children: [
              const TextSpan(text: "Are you sure you want to delete "),
              TextSpan(
                text: "'${entity['name']}'",
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
              ),
              TextSpan(text: "?$warning"),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete Everything", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed == true) {
      String table = type == 'Cluster' ? 'clusters' : (type == 'Village' ? 'villages' : 'schools');
      await _supabase.from(table).delete().eq('id', entity['id']);
      if (mounted) {
        _fetchHierarchy();
      }
    }
  }

  List<TableRow> _generateRows() {
    List<TableRow> rows = [];
    for (var cluster in _filteredHierarchy) {
      List villages = cluster['villages'] ?? [];
      if (villages.isEmpty) {
        rows.add(_buildSingleRow(cluster, null, null, showClusterActions: true, clusterBorder: true));
      } else {
        for (int vIdx = 0; vIdx < villages.length; vIdx++) {
          var village = villages[vIdx];
          List schools = village['schools'] ?? [];
          if (schools.isEmpty) {
            rows.add(
              _buildSingleRow(
                cluster,
                village,
                null,
                showClusterActions: vIdx == 0,
                showVillageActions: true,
                clusterBorder: vIdx == 0,
                villageBorder: vIdx > 0,
              ),
            );
          } else {
            for (int sIdx = 0; sIdx < schools.length; sIdx++) {
              rows.add(
                _buildSingleRow(
                  cluster,
                  village,
                  schools[sIdx],
                  showClusterActions: vIdx == 0 && sIdx == 0,
                  showVillageActions: sIdx == 0,
                  showSchoolActions: true,
                  clusterBorder: vIdx == 0 && sIdx == 0,
                  villageBorder: vIdx > 0 && sIdx == 0,
                  schoolBorder: sIdx > 0,
                ),
              );
            }
          }
        }
      }
    }
    return rows;
  }

  TableRow _buildSingleRow(
    dynamic cluster,
    dynamic village,
    dynamic school, {
    bool showClusterActions = false,
    bool showVillageActions = false,
    bool showSchoolActions = false,
    bool clusterBorder = false,
    bool villageBorder = false,
    bool schoolBorder = false,
  }) {
    int clusterColBorder = clusterBorder ? 1 : 0;
    int villageColBorder = clusterBorder ? 1 : (villageBorder ? 2 : 0);
    int schoolColBorder = clusterBorder ? 1 : (villageBorder ? 2 : (schoolBorder ? 3 : 0));
    return TableRow(
      children: [
        _ActionCell(
          text: showClusterActions ? cluster['name'] : "",
          isBold: true,
          borderType: clusterColBorder,
          onTap: () => _showManageDialog('Cluster', cluster),
        ),
        _ActionCell(
          text: showVillageActions ? village['name'] : "",
          borderType: villageColBorder,
          onTap: () => _showManageDialog('Village', village),
        ),
        _ActionCell(
          text: school != null ? school['name'] : "-",
          borderType: schoolColBorder,
          onTap: school != null ? () => _showManageDialog('School', school) : null,
        ),
      ],
    );
  }

  List<String> _getUniqueValues(int columnIndex) {
    final Set<String> values = {};
    for (final cluster in _hierarchy) {
      final clusterName = cluster['name'].toString();
      if (_selectedClusterFilters != null && !_selectedClusterFilters!.contains(clusterName)) {
        continue;
      }
      if (columnIndex == 0) {
        values.add(clusterName);
      }
      for (final village in (cluster['villages'] ?? [])) {
        final villageName = village['name'].toString();
        if (_selectedVillageFilters != null && !_selectedVillageFilters!.contains(villageName) && columnIndex == 2) {
          continue;
        }
        if (columnIndex == 1) {
          values.add(villageName);
        }
        for (final school in (village['schools'] ?? [])) {
          final schoolName = school['name'].toString();
          if (columnIndex == 2) {
            values.add(schoolName);
          }
        }
      }
    }
    return values.toList()..sort();
  }

  Future<void> _showFilterMenu({required BuildContext context, required int columnIndex}) async {
    final allValues = _getUniqueValues(columnIndex);
    Set<String> currentSelection;
    if (columnIndex == 0) {
      currentSelection = _selectedClusterFilters != null ? Set.from(_selectedClusterFilters!) : Set.from(allValues);
    } else if (columnIndex == 1) {
      currentSelection = _selectedVillageFilters != null ? Set.from(_selectedVillageFilters!) : Set.from(allValues);
    } else {
      currentSelection = _selectedSchoolFilters != null ? Set.from(_selectedSchoolFilters!) : Set.from(allValues);
    }
    final searchController = TextEditingController();
    List<String> filteredValues = List.from(allValues);
    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Filter"),
              content: SizedBox(
                width: 320,
                height: 450,
                child: Column(
                  children: [
                    TextField(
                      controller: searchController,
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
                      value:
                          currentSelection.length == allValues.length ||
                          (columnIndex == 0 && _selectedClusterFilters == null) ||
                          (columnIndex == 1 && _selectedVillageFilters == null) ||
                          (columnIndex == 2 && _selectedSchoolFilters == null),
                      title: const Text("Select All"),
                      onChanged: (checked) {
                        setStateDialog(() {
                          if (checked == true) {
                            currentSelection = Set.from(allValues);
                          } else {
                            currentSelection.clear();
                          }
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
                                if (checked == true) {
                                  currentSelection.add(value);
                                } else {
                                  currentSelection.remove(value);
                                }
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
                      if (columnIndex == 0) {
                        _selectedClusterFilters = currentSelection.length == allValues.length ? null : Set.from(currentSelection);
                      } else if (columnIndex == 1) {
                        _selectedVillageFilters = currentSelection.length == allValues.length ? null : Set.from(currentSelection);
                      } else {
                        _selectedSchoolFilters = currentSelection.length == allValues.length ? null : Set.from(currentSelection);
                      }
                      _applyAllFilters();
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text("Apply"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Locations Management"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade300, height: 1),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchHierarchy,
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => _applyAllFilters(),
                      decoration: InputDecoration(
                        hintText: "Search clusters, villages, or schools...",
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  _applyAllFilters();
                                },
                              )
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                  ),
                  Table(
                    border: TableBorder(
                      verticalInside: BorderSide(color: Colors.grey.shade300),
                      bottom: BorderSide(color: Colors.grey.shade300),
                      left: BorderSide(color: Colors.grey.shade300),
                      right: BorderSide(color: Colors.grey.shade300),
                    ),
                    columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1.2)},
                    children: [
                      TableRow(
                        decoration: BoxDecoration(color: Colors.grey.shade200),
                        children: [
                          _SortableHeader(
                            label: "Cluster",
                            onSort: () => _onSort(0),
                            onFilter: () => _showFilterMenu(context: context, columnIndex: 0),
                            isSorted: _sortColumnIndex == 0,
                            isAscending: _isAscending,
                            hasFilter: _selectedClusterFilters != null,
                          ),
                          _SortableHeader(
                            label: "Village",
                            onSort: () => _onSort(1),
                            onFilter: () => _showFilterMenu(context: context, columnIndex: 1),
                            isSorted: _sortColumnIndex == 1,
                            isAscending: _isAscending,
                            hasFilter: _selectedVillageFilters != null,
                          ),
                          _SortableHeader(
                            label: "School",
                            onSort: () => _onSort(2),
                            onFilter: () => _showFilterMenu(context: context, columnIndex: 2),
                            isSorted: _sortColumnIndex == 2,
                            isAscending: _isAscending,
                            hasFilter: _selectedSchoolFilters != null,
                          ),
                        ],
                      ),
                      ..._generateRows(),
                    ],
                  ),
                ],
              ),
            ),
      floatingActionButton: _buildSpeedDial(),
    );
  }

  Widget _buildSpeedDial() {
    return FloatingActionButton(
      heroTag: "add_location_btn",
      onPressed: () => _showAddDialog('School'),
      backgroundColor: Colors.teal,
      child: const Icon(Icons.add_location_alt, color: Colors.white),
    );
  }

  Future<void> _showManageDialog(String type, dynamic entity) async {
    final nameController = TextEditingController(text: entity['name']);
    String? selectedParentId;
    List<LatLng> schoolBoundary = [];
    if (type == 'School' && entity['boundary'] != null) {
      try {
        var coords = entity['boundary']['coordinates'][0] as List;
        schoolBoundary = coords
            .take(coords.length > 3 ? coords.length - 1 : coords.length)
            .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
            .toList();
      } catch (e) {
        debugPrint("Error parsing boundary: $e");
      }
    }
    if (type == 'Village') {
      selectedParentId = entity['cluster_id']?.toString();
    } else if (type == 'School') {
      selectedParentId = entity['village_id']?.toString();
    }
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.settings, color: Colors.indigo),
              const SizedBox(width: 10),
              Text("Manage $type"),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (type == 'Village')
                    DropdownButtonFormField<String>(
                      initialValue: selectedParentId,
                      decoration: const InputDecoration(labelText: "Move to Cluster"),
                      items: _hierarchy.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['name']))).toList(),
                      onChanged: (val) => setDialogState(() => selectedParentId = val),
                    ),
                  if (type == 'School') ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedParentId,
                      decoration: const InputDecoration(labelText: "Move to Village"),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedParentId = val;
                        });
                      },
                      items: _hierarchy.expand((cluster) {
                        return (cluster['villages'] as List).map((village) {
                          return DropdownMenuItem<String>(
                            value: village['id'].toString(),
                            child: Text("${village['name']} (${cluster['name']})"),
                          );
                        });
                      }).toList(),
                    ),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(labelText: "$type Name"),
                    ),
                    const SizedBox(height: 8),
                    const Text("Edit School Boundary", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    const Divider(),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _confirmDelete(type, entity);
                      },
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      label: Text("Delete this $type", style: const TextStyle(color: Colors.red)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final Map<String, dynamic> updateData = {'name': name};
                  String table = type == 'Cluster' ? 'clusters' : (type == 'Village' ? 'villages' : 'schools');
                  if (type == 'Village') updateData['cluster_id'] = selectedParentId;
                  if (type == 'School') {
                    updateData['village_id'] = selectedParentId;
                    if (schoolBoundary.length >= 3) {
                      var coords = schoolBoundary.map((p) => [p.longitude, p.latitude]).toList();
                      coords.add(coords.first);
                      updateData['boundary'] = {
                        'type': 'Polygon',
                        'coordinates': [coords],
                      };
                    }
                  }
                  await _supabase.from(table).update(updateData).eq('id', entity['id']);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (!mounted) return;
                  _fetchHierarchy();
                  messenger.showSnackBar(SnackBar(content: Text("$type updated!")));
                } catch (e) {
                  if (!mounted) return;
                  messenger.showSnackBar(SnackBar(content: Text("Error: $e")));
                }
              },
              child: const Text("Save Changes"),
            ),
          ],
        ),
      ),
    );
  }

  void _applyAllFilters() {
    final query = _searchController.text.toLowerCase().trim();
    final List<dynamic> result = [];
    for (final cluster in _hierarchy) {
      final clusterName = cluster['name'].toString();
      if (_selectedClusterFilters != null && !_selectedClusterFilters!.contains(clusterName)) {
        continue;
      }
      final List<dynamic> filteredVillages = [];
      for (final village in (cluster['villages'] ?? [])) {
        final villageName = village['name'].toString();
        if (_selectedVillageFilters != null && !_selectedVillageFilters!.contains(villageName)) {
          continue;
        }
        final List<dynamic> filteredSchools = [];
        for (final school in (village['schools'] ?? [])) {
          final schoolName = school['name'].toString();
          if (_selectedSchoolFilters != null && !_selectedSchoolFilters!.contains(schoolName)) {
            continue;
          }
          final matchesSearch =
              query.isEmpty ||
              clusterName.toLowerCase().contains(query) ||
              villageName.toLowerCase().contains(query) ||
              schoolName.toLowerCase().contains(query);
          if (matchesSearch) {
            filteredSchools.add(school);
          }
        }
        final villageMatchesSearch =
            query.isEmpty || clusterName.toLowerCase().contains(query) || villageName.toLowerCase().contains(query);
        if (filteredSchools.isNotEmpty || villageMatchesSearch) {
          filteredVillages.add({...village, 'schools': filteredSchools});
        }
      }
      final clusterMatchesSearch = query.isEmpty || clusterName.toLowerCase().contains(query);
      if (filteredVillages.isNotEmpty || clusterMatchesSearch) {
        result.add({...cluster, 'villages': filteredVillages});
      }
    }
    setState(() {
      _filteredHierarchy = result;
    });
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onSort,
              child: Row(
                children: [
                  Flexible(
                    child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isSorted ? (isAscending ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more,
                    size: 16,
                    color: isSorted ? Colors.indigo : Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: onFilter,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: hasFilter ? Colors.indigo.withValues(alpha: 0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.filter_alt, size: 18, color: hasFilter ? Colors.indigo : Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCell extends StatelessWidget {
  final String text;
  final bool isBold;
  final int borderType;
  final VoidCallback? onTap;
  const _ActionCell({required this.text, this.isBold = false, this.borderType = 0, this.onTap});
  @override
  Widget build(BuildContext context) {
    BorderSide? topSide;
    if (borderType == 1) {
      topSide = BorderSide(color: Colors.grey.shade900, width: 2.5);
    } else if (borderType == 2) {
      topSide = BorderSide(color: Colors.grey.shade500, width: 1.0);
    } else if (borderType == 3) {
      topSide = BorderSide(color: Colors.grey.shade300, width: 0.5);
    }
    return Container(
      decoration: BoxDecoration(border: topSide != null ? Border(top: topSide) : null),
      child: InkWell(
        onTap: (text.isEmpty || text == "-") ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                    color: text == "-" ? Colors.grey : Colors.indigo.shade900,
                    decoration: (text.isEmpty || text == "-") ? null : TextDecoration.underline,
                    decorationStyle: TextDecorationStyle.dotted,
                  ),
                ),
              ),
              if (text.isNotEmpty && text != "-") const Icon(Icons.edit_note, size: 14, color: Colors.indigo),
            ],
          ),
        ),
      ),
    );
  }
}
