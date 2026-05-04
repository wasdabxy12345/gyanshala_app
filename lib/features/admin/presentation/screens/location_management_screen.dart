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
  int _sortColumnIndex = 0; // 0 for Cluster, 1 for Village, 2 for School
  final _supabase = Supabase.instance.client;
  List<dynamic> _hierarchy = [];
  bool _isLoading = true;

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

      // Sort Clusters
      _hierarchy.sort((a, b) {
        int compare;
        if (columnIndex == 0) {
          compare = (a['name'] as String).compareTo(b['name'] as String);
        } else {
          // Keep order if not sorting by cluster but sort sub-items
          compare = 0;
        }
        return _isAscending ? compare : -compare;
      });

      // Sort nested items
      for (var cluster in _hierarchy) {
        List villages = cluster['villages'] ?? [];
        villages.sort((a, b) {
          int vCompare = 0;
          if (columnIndex == 1) {
            vCompare = (a['name'] as String).compareTo(b['name'] as String);
          }
          return _isAscending ? vCompare : -vCompare;
        });

        for (var village in villages) {
          List schools = village['schools'] ?? [];
          schools.sort((a, b) {
            int sCompare = 0;
            if (columnIndex == 2) {
              sCompare = (a['name'] as String).compareTo(b['name'] as String);
            }
            return _isAscending ? sCompare : -sCompare;
          });
        }
      }
    });
  }

  Future<void> _fetchHierarchy() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final data = await _supabase
          .from('clusters')
          .select('id, name, villages(id, name, schools(id, name))')
          .order('name');

      if (mounted) setState(() => _hierarchy = data);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Unified Form to ADD
  Future<void> _showAddDialog(String type) async {
    final nameController = TextEditingController();
    String? selectedClusterId;
    String? selectedVillageId;
    List<dynamic> clusters = _hierarchy;
    List<dynamic> villages = [];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text("Add New $type"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (type == 'Village' || type == 'School')
                DropdownButtonFormField<String>(
                  hint: const Text("Select Cluster"),
                  items: clusters
                      .map(
                        (c) => DropdownMenuItem(
                          value: c['id'].toString(),
                          child: Text(c['name']),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    setDialogState(() {
                      selectedClusterId = val;
                      villages =
                          clusters.firstWhere(
                            (c) => c['id'].toString() == val,
                          )['villages'] ??
                          [];
                      selectedVillageId = null;
                    });
                  },
                ),
              if (type == 'School') ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  hint: const Text("Select Village"),
                  initialValue: selectedVillageId,
                  items: villages
                      .map(
                        (v) => DropdownMenuItem(
                          value: v['id'].toString(),
                          child: Text(v['name']),
                        ),
                      )
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => selectedVillageId = val),
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
                  await _supabase.from('villages').insert({
                    'name': name,
                    'cluster_id': selectedClusterId,
                  });
                } else {
                  await _supabase.from('schools').insert({
                    'name': name,
                    'village_id': selectedVillageId,
                  });
                }

                if (ctx.mounted) Navigator.pop(ctx);

                if (!mounted) return;
                _fetchHierarchy();
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  // Unified Form to EDIT

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
    for (var cluster in _hierarchy) {
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
                villageBorder:
                    vIdx > 0, // Village border if not start of cluster
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
                  villageBorder:
                      vIdx > 0 && sIdx == 0, // Village border for new village
                  schoolBorder:
                      sIdx > 0, // School border for subsequent schools
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
    // Determine border type for each specific column
    int clusterColBorder = clusterBorder ? 1 : 0;

    int villageColBorder = 0;
    if (clusterBorder)
      villageColBorder = 1;
    else if (villageBorder)
      villageColBorder = 2;

    int schoolColBorder = 0;
    if (clusterBorder)
      schoolColBorder = 1;
    else if (villageBorder)
      schoolColBorder = 2;
    else if (schoolBorder)
      schoolColBorder = 3;

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
        title: const Text("Location Hierarchy"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchHierarchy,
              child: ListView(
                children: [
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          heroTag: "btn1",
          onPressed: () => _showAddDialog('Cluster'),
          backgroundColor: Colors.indigo,
          child: const Icon(Icons.hub, color: Colors.white),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.small(
          heroTag: "btn2",
          onPressed: () => _showAddDialog('Village'),
          backgroundColor: Colors.orange,
          child: const Icon(Icons.holiday_village, color: Colors.white),
        ),
        const SizedBox(height: 8),
        FloatingActionButton(
          heroTag: "btn3",
          onPressed: () => _showAddDialog('School'),
          backgroundColor: Colors.teal,
          child: const Icon(Icons.school, color: Colors.white),
        ),
      ],
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
                  Navigator.pop(ctx); // Close management dialog
                  _confirmDelete(type, entity); // Open delete confirm
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
  final int
  borderType; // 0: None, 1: Cluster (Thick), 2: Village (Medium), 3: School (Thin)
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
