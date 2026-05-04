import 'dart:io';

import 'package:excel/excel.dart' hide TextSpan, Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocationManagementScreen extends StatefulWidget {
  const LocationManagementScreen({super.key});

  @override
  State<LocationManagementScreen> createState() =>
      _LocationManagementScreenState();
}

class _LocationManagementScreenState extends State<LocationManagementScreen> {
  bool _isAscending = true;
  int _sortColumnIndex = 0;
  final _supabase = Supabase.instance.client;
  List<dynamic> _hierarchy = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  List<dynamic> _filteredHierarchy = [];

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
        int compare = (a['name'] as String).toLowerCase().compareTo(
          (b['name'] as String).toLowerCase(),
        );
        return _isAscending ? compare : -compare;
      });

      for (var cluster in _hierarchy) {
        List villages = cluster['villages'] ?? [];
        if (columnIndex == 1) {
          villages.sort((a, b) {
            int vCompare = (a['name'] as String).toLowerCase().compareTo(
              (b['name'] as String).toLowerCase(),
            );
            return _isAscending ? vCompare : -vCompare;
          });
        }

        for (var village in villages) {
          List schools = village['schools'] ?? [];
          if (columnIndex == 2) {
            schools.sort((a, b) {
              int sCompare = (a['name'] as String).toLowerCase().compareTo(
                (b['name'] as String).toLowerCase(),
              );
              return _isAscending ? sCompare : -sCompare;
            });
          }
        }
        _runSearch(_searchController.text);
      }
    });
  }

  Future<void> _importFromExcel() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
    );

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

          if (rawCluster?.toLowerCase() == 'cluster' &&
              schoolName?.toLowerCase() == 'school') {
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
                .upsert({
                  'name': lastVillageName,
                  'cluster_id': clusterId,
                }, onConflict: 'name, cluster_id')
                .select()
                .single();
            villageId = villageResp['id'].toString();
          }

          if (villageId != null) {
            await _supabase.from('schools').upsert({
              'name': schoolName,
              'village_id': villageId,
            }, onConflict: 'name, village_id');
          }
          importedCount++;
        }
      }

      await _fetchHierarchy();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Successfully processed $importedCount rows")),
        );
      }
    } catch (e) {
      debugPrint("Import Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Import Error: ${e.toString()}")),
        );
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
          .select(
            'id, name, villages(id, name, cluster_id, schools(id, name, village_id))',
          )
          .order('name', ascending: true);

      if (mounted) {
        setState(() {
          _hierarchy = data;
          _sortColumnIndex = 0;
          _isAscending = true;
          if (_searchController.text.isNotEmpty) {
            _runSearch(_searchController.text);
          } else {
            _filteredHierarchy = data;
          }
        });
      }
    } catch (e) {
      debugPrint("Fetch error: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error fetching data: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showAddDialog(String type) async {
    final nameController = TextEditingController();
    String? selectedClusterId;
    String? selectedVillageId;

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
            TextButton(
              onPressed: () => Navigator.pop(qCtx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = quickController.text.trim();
                if (name.isEmpty) return;

                final table = parentType == 'Cluster' ? 'clusters' : 'villages';
                final Map<String, dynamic> insertData = {'name': name};

                if (parentType == 'Village') {
                  insertData['cluster_id'] = selectedClusterId;
                }

                final response = await _supabase
                    .from(table)
                    .insert(insertData)
                    .select()
                    .single();
                await _fetchHierarchy();
                if (qCtx.mounted)
                  Navigator.pop(qCtx, response['id'].toString());
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
          content: Column(
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
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(40),
                    foregroundColor: Colors.teal,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text(
                          "OR MANUALLY",
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                ),
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
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ..._hierarchy.map(
                      (c) => DropdownMenuItem(
                        value: c['id'].toString(),
                        child: Text(c['name']),
                      ),
                    ),
                  ],
                  onChanged: (val) async {
                    if (val == "ADD_NEW") {
                      final newId = await showQuickAdd("Cluster");
                      if (newId != null)
                        setDialogState(() => selectedClusterId = newId);
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
                              style: TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          ...(_hierarchy.firstWhere(
                                    (c) =>
                                        c['id'].toString() == selectedClusterId,
                                  )['villages']
                                  as List)
                              .map(
                                (v) => DropdownMenuItem(
                                  value: v['id'].toString(),
                                  child: Text(v['name']),
                                ),
                              ),
                        ],
                  onChanged: selectedClusterId == null
                      ? null
                      : (val) async {
                          if (val == "ADD_NEW") {
                            final newId = await showQuickAdd("Village");
                            if (newId != null)
                              setDialogState(() => selectedVillageId = newId);
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                if (type == 'Cluster') {
                  await _supabase.from('clusters').insert({'name': name});
                } else if (type == 'Village') {
                  if (selectedClusterId == null) return;
                  await _supabase.from('villages').insert({
                    'name': name,
                    'cluster_id': selectedClusterId,
                  });
                } else {
                  if (selectedVillageId == null) return;
                  await _supabase.from('schools').insert({
                    'name': name,
                    'village_id': selectedVillageId,
                  });
                }

                if (ctx.mounted) Navigator.pop(ctx);
                _fetchHierarchy();
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
      warning =
          "\n\nWarning: Deleting this Cluster will also delete ALL associated Villages and Schools!";
    } else if (type == 'Village') {
      warning =
          "\n\nWarning: Deleting this Village will also delete ALL associated Schools!";
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
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              TextSpan(text: "?$warning"),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "Delete Everything",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (confirmed == true) {
      String table = type == 'Cluster'
          ? 'clusters'
          : (type == 'Village' ? 'villages' : 'schools');
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
        rows.add(
          _buildSingleRow(
            cluster,
            null,
            null,
            showClusterActions: true,
            clusterBorder: true,
          ),
        );
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
    int schoolColBorder = clusterBorder
        ? 1
        : (villageBorder ? 2 : (schoolBorder ? 3 : 0));

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
          onTap: school != null
              ? () => _showManageDialog('School', school)
              : null,
        ),
      ],
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
                      onChanged: _runSearch,
                      decoration: InputDecoration(
                        hintText: "Search clusters, villages, or schools...",
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  _runSearch('');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
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
                    columnWidths: const {
                      0: FlexColumnWidth(1),
                      1: FlexColumnWidth(1),
                      2: FlexColumnWidth(1.2),
                    },
                    children: [
                      TableRow(
                        decoration: BoxDecoration(color: Colors.grey.shade200),
                        children: [
                          _SortableHeader(
                            label: "Cluster",
                            onSort: () => _onSort(0),
                            isSorted: _sortColumnIndex == 0,
                            isAscending: _isAscending,
                          ),
                          _SortableHeader(
                            label: "Village",
                            onSort: () => _onSort(1),
                            isSorted: _sortColumnIndex == 1,
                            isAscending: _isAscending,
                          ),
                          _SortableHeader(
                            label: "School",
                            onSort: () => _onSort(2),
                            isSorted: _sortColumnIndex == 2,
                            isAscending: _isAscending,
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (type == 'Village')
                DropdownButtonFormField<String>(
                  initialValue: selectedParentId,
                  decoration: const InputDecoration(
                    labelText: "Move to Cluster",
                  ),
                  items: _hierarchy
                      .map(
                        (c) => DropdownMenuItem(
                          value: c['id'].toString(),
                          child: Text(c['name']),
                        ),
                      )
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => selectedParentId = val),
                ),
              if (type == 'School')
                DropdownButtonFormField<String>(
                  initialValue: selectedParentId,
                  decoration: const InputDecoration(
                    labelText: "Move to Village",
                  ),
                  items: _hierarchy
                      .expand((c) => (c['villages'] as List))
                      .map(
                        (v) => DropdownMenuItem(
                          value: v['id'].toString(),
                          child: Text(v['name']),
                        ),
                      )
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => selectedParentId = val),
                ),
              TextField(
                controller: nameController,
                decoration: InputDecoration(labelText: "$type Name"),
              ),
              const SizedBox(height: 20),
              const Divider(),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _confirmDelete(type, entity);
                },
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                label: Text(
                  "Delete this $type",
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final Map<String, dynamic> updateData = {'name': name};
                  String table = type == 'Cluster'
                      ? 'clusters'
                      : (type == 'Village' ? 'villages' : 'schools');
                  if (type == 'Village')
                    updateData['cluster_id'] = selectedParentId;
                  if (type == 'School')
                    updateData['village_id'] = selectedParentId;

                  await _supabase
                      .from(table)
                      .update(updateData)
                      .eq('id', entity['id']);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (!mounted) return;
                  _fetchHierarchy();
                  messenger.showSnackBar(
                    SnackBar(content: Text("$type updated!")),
                  );
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

  void _runSearch(String query) {
    final lowercaseQuery = query.toLowerCase();

    if (lowercaseQuery.isEmpty) {
      setState(() {
        _filteredHierarchy = _hierarchy;
      });
      return;
    }

    setState(() {
      _filteredHierarchy = _hierarchy
          .map((cluster) {
            final clusterName = cluster['name'].toString().toLowerCase();
            final bool clusterMatches = clusterName.contains(lowercaseQuery);

            final villages = List.from(cluster['villages'] ?? []);

            final filteredVillages = villages
                .map((village) {
                  final villageName = village['name'].toString().toLowerCase();
                  final bool villageMatches = villageName.contains(
                    lowercaseQuery,
                  );

                  final schools = List.from(village['schools'] ?? []);

                  final filteredSchools = schools.where((school) {
                    if (clusterMatches || villageMatches) return true;
                    return school['name'].toString().toLowerCase().contains(
                      lowercaseQuery,
                    );
                  }).toList();

                  final villageCopy = Map<String, dynamic>.from(village);
                  villageCopy['schools'] = filteredSchools;
                  return villageCopy;
                })
                .where((v) {
                  final villageName = v['name'].toString().toLowerCase();
                  final schools = v['schools'] as List;

                  return clusterMatches ||
                      villageName.contains(lowercaseQuery) ||
                      schools.isNotEmpty;
                })
                .toList();

            final clusterCopy = Map<String, dynamic>.from(cluster);
            clusterCopy['villages'] = filteredVillages;
            return clusterCopy;
          })
          .where((c) {
            final clusterName = c['name'].toString().toLowerCase();
            final villages = c['villages'] as List;

            return clusterName.contains(lowercaseQuery) || villages.isNotEmpty;
          })
          .toList();
    });
  }
}

class _SortableHeader extends StatelessWidget {
  final String label;
  final VoidCallback onSort;
  final bool isSorted;
  final bool isAscending;

  const _SortableHeader({
    required this.label,
    required this.onSort,
    required this.isSorted,
    required this.isAscending,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSort,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Icon(
              isSorted
                  ? (isAscending ? Icons.arrow_upward : Icons.arrow_downward)
                  : Icons.sort,
              size: 16,
              color: isSorted ? Colors.indigo : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCell extends StatelessWidget {
  final String text;
  final bool isBold;
  final int borderType;
  final VoidCallback? onTap;

  const _ActionCell({
    required this.text,
    this.isBold = false,
    this.borderType = 0,
    this.onTap,
  });

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
      decoration: BoxDecoration(
        border: topSide != null ? Border(top: topSide) : null,
      ),
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
                    decoration: (text.isEmpty || text == "-")
                        ? null
                        : TextDecoration.underline,
                    decorationStyle: TextDecorationStyle.dotted,
                  ),
                ),
              ),
              if (text.isNotEmpty && text != "-")
                const Icon(Icons.edit_note, size: 14, color: Colors.indigo),
            ],
          ),
        ),
      ),
    );
  }
}
