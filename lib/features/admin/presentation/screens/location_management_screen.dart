import 'dart:io';

import 'package:excel/excel.dart' hide TextSpan, Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:gyanshala_app/core/utils/excel_parser/excel_parser.dart'
    if (dart.library.js_interop) 'package:gyanshala_app/core/utils/excel_parser/excel_web_parser.dart'
    if (dart.library.io) 'package:gyanshala_app/core/utils/excel_parser/excel_mobile_parser.dart';
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
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
      withData: true,
    );
    if (result == null) return;
    setState(() => _isLoading = true);
    int importedCount = 0;
    try {
      final platformFile = result.files.first;
      List<int> bytes;
      if (platformFile.bytes != null) {
        bytes = platformFile.bytes!;
      } else if (!kIsWeb && platformFile.path != null) {
        bytes = File(platformFile.path!).readAsBytesSync();
      } else {
        throw Exception("Could not read file data");
      }
      debugPrint("Parsing Excel file...");
      final excelData = kIsWeb ? await ExcelParser.parseLocationMatrix(bytes) : _parseExcelDataNative(bytes);
      debugPrint("Excel parsed: ${excelData.length} rows");
      for (final rowData in excelData) {
        try {
          final clusterResp = await _supabase
              .from('clusters')
              .upsert({'name': rowData['cluster']}, onConflict: 'name')
              .select()
              .single();
          final String clusterId = clusterResp['id'].toString();
          String? villageId;
          if (rowData['village'] != null && rowData['village'].isNotEmpty) {
            final villageResp = await _supabase
                .from('villages')
                .upsert({'name': rowData['village'], 'cluster_id': clusterId}, onConflict: 'name, cluster_id')
                .select()
                .single();
            villageId = villageResp['id'].toString();
          }
          if (villageId != null) {
            double? lat = rowData['lat'] != null ? double.tryParse(rowData['lat']) : null;
            double? lng = rowData['lng'] != null ? double.tryParse(rowData['lng']) : null;
            await _supabase.from('schools').upsert({
              'name': rowData['school'],
              'village_id': villageId,
              'latitude': lat,
              'longitude': lng,
              'radius_meters': 50.0,
            }, onConflict: 'name, village_id');
          }
          importedCount++;
        } catch (e) {
          debugPrint("Row processing error: $e");
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

  List<Map<String, dynamic>> _parseExcelDataNative(List<int> bytes) {
    var excel = Excel.decodeBytes(bytes);
    List<Map<String, dynamic>> rows = [];
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
        final rawLat = row.length > 3 ? row[3]?.value?.toString().trim() : null;
        final rawLng = row.length > 4 ? row[4]?.value?.toString().trim() : null;
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
        rows.add({'cluster': lastClusterName, 'village': lastVillageName, 'school': schoolName, 'lat': rawLat, 'lng': rawLng});
      }
    }
    return rows;
  }

  Future<void> _fetchHierarchy() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final data = await _supabase
          .from('clusters')
          .select('id, name, villages(id, name, cluster_id, schools(id, name, village_id, latitude, longitude, radius_meters)))')
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

  Widget _buildMapHeaderControl({
    required BuildContext context,
    required MapType currentType,
    required bool expanded,
    required Function(MapType) onTypeChanged,
    required VoidCallback onToggleFullscreen,
  }) {
    Widget buildTypeButton(String label, IconData icon, MapType type) {
      final bool isSelected = currentType == type;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onTypeChanged(type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primaryBlue : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: isSelected ? Colors.white : Colors.black87),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : Colors.black87),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.all(2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildTypeButton("Map", Icons.map, MapType.normal),
              buildTypeButton("Sat", Icons.satellite_alt, MapType.satellite),
              buildTypeButton("Hybrid", Icons.layers, MapType.hybrid),
            ],
          ),
        ),
        IconButton(
          icon: Icon(expanded ? Icons.fullscreen_exit : Icons.fullscreen, color: AppTheme.primaryBlue),
          onPressed: onToggleFullscreen,
        ),
      ],
    );
  }

  Future<void> _showAddDialog(String type) async {
    final nameController = TextEditingController();
    final latController = TextEditingController();
    final lngController = TextEditingController();
    final radiusController = TextEditingController(text: "50");
    String? selectedClusterId;
    String? selectedVillageId;
    GoogleMapController? mapController;
    LatLng? selectedLatLng;
    MapType dialogMapType = MapType.normal;
    int mapRefreshKey = 0;
    void updateMapLocation() {
      final double? lat = double.tryParse(latController.text.trim());
      final double? lng = double.tryParse(lngController.text.trim());
      if (lat != null && lng != null && mapController != null) {
        mapController!.animateCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
      }
    }

    latController.addListener(updateMapLocation);
    lngController.addListener(updateMapLocation);
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
        builder: (context, setDialogState) {
          Widget buildBaseMap({VoidCallback? onMapTapTrigger}) {
            return GoogleMap(
              key: ValueKey('add_map_${mapRefreshKey}_${dialogMapType.name}'),
              initialCameraPosition: CameraPosition(
                target: selectedLatLng ?? const LatLng(23.0225, 72.5714),
                zoom: selectedLatLng != null ? 14 : 12,
              ),
              mapType: dialogMapType,
              zoomControlsEnabled: true,
              myLocationButtonEnabled: false,
              gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
              onMapCreated: (ctrl) => mapController = ctrl,
              onTap: (latLng) {
                setDialogState(() {
                  selectedLatLng = latLng;
                  latController.text = latLng.latitude.toStringAsFixed(6);
                  lngController.text = latLng.longitude.toStringAsFixed(6);
                });
                if (onMapTapTrigger != null) onMapTapTrigger();
              },
              markers: selectedLatLng == null
                  ? {}
                  : {Marker(markerId: const MarkerId('selected_pin'), position: selectedLatLng!)},
              circles: selectedLatLng == null
                  ? {}
                  : {
                      Circle(
                        circleId: const CircleId('geofence_circle'),
                        center: selectedLatLng!,
                        radius: double.tryParse(radiusController.text.trim()) ?? 50.0,
                        fillColor: AppTheme.primaryBlue,
                        strokeColor: AppTheme.accentBlue,
                        strokeWidth: 2,
                      ),
                    },
            );
          }

          void openFullscreenMap() async {
            await Navigator.of(context).push(
              PageRouteBuilder(
                opaque: false,
                barrierDismissible: true,
                pageBuilder: (_, __, ___) => StatefulBuilder(
                  builder: (fsContext, setFsState) => Scaffold(
                    backgroundColor: Colors.black38,
                    body: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Material(
                          elevation: 12,
                          borderRadius: BorderRadius.circular(8),
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                child: _buildMapHeaderControl(
                                  context: context,
                                  currentType: dialogMapType,
                                  expanded: true,
                                  onTypeChanged: (type) {
                                    setDialogState(() {
                                      dialogMapType = type;
                                      mapRefreshKey++;
                                    });
                                    setFsState(() {});
                                  },
                                  onToggleFullscreen: () => Navigator.of(context).pop(),
                                ),
                              ),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                                  child: buildBaseMap(onMapTapTrigger: () => setFsState(() {})),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            setDialogState(() {});
          }

          return AlertDialog(
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
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(40),
                          foregroundColor: AppTheme.primaryBlue,
                        ),
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
                                ...(_hierarchy.firstWhere((c) => c['id'].toString() == selectedClusterId)['villages'] as List)
                                    .map((v) => DropdownMenuItem(value: v['id'].toString(), child: Text(v['name']))),
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
                    if (type == 'School') ...[
                      const SizedBox(height: 16),
                      _buildMapHeaderControl(
                        context: context,
                        currentType: dialogMapType,
                        expanded: false,
                        onTypeChanged: (type) {
                          setDialogState(() {
                            dialogMapType = type;
                            mapRefreshKey++;
                          });
                        },
                        onToggleFullscreen: openFullscreenMap,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: buildBaseMap(),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: latController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: "Latitude"),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: lngController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: "Longitude"),
                            ),
                          ),
                        ],
                      ),
                      TextField(
                        controller: radiusController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "Geofence Radius (Meters)"),
                        onChanged: (_) => setDialogState(() {}),
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
                      insertData['latitude'] = double.tryParse(latController.text.trim());
                      insertData['longitude'] = double.tryParse(lngController.text.trim());
                      insertData['radius_meters'] = double.tryParse(radiusController.text.trim()) ?? 50.0;
                    }
                    await _supabase.from(table).insert(insertData);
                    if (ctx.mounted) Navigator.pop(ctx);
                    _fetchHierarchy();
                  } catch (e) {
                    debugPrint("Insert Error: $e");
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error saving $type: ${e.toString()}")));
                    }
                  }
                },
                child: const Text("Save"),
              ),
            ],
          );
        },
      ),
    ).then((_) {
      latController.removeListener(updateMapLocation);
      lngController.removeListener(updateMapLocation);
    });
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
      if (mounted) _fetchHierarchy();
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
    String schoolCellText = "-";
    if (school != null) {
      schoolCellText = school['name'];
    }
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
          text: schoolCellText,
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
      if (columnIndex == 0) {
        values.add(clusterName);
      }
      if (columnIndex != 0 && _selectedClusterFilters != null && !_selectedClusterFilters!.contains(clusterName)) {
        continue;
      }

      for (final village in (cluster['villages'] ?? [])) {
        final villageName = village['name'].toString();
        if (columnIndex == 1) {
          values.add(villageName);
        }
        if (columnIndex == 2 && _selectedVillageFilters != null && !_selectedVillageFilters!.contains(villageName)) {
          continue;
        }

        for (final school in (village['schools'] ?? [])) {
          if (columnIndex == 2) {
            values.add(school['name'].toString());
          }
        }
      }
    }

    return values.toList()..sort();
  }

  Future<void> _showFilterMenu({required BuildContext context, required int columnIndex}) async {
    final allValues = _getUniqueValues(columnIndex);
    Set<String> currentSelection = (columnIndex == 0)
        ? (_selectedClusterFilters != null ? Set.from(_selectedClusterFilters!) : Set.from(allValues))
        : (columnIndex == 1)
        ? (_selectedVillageFilters != null ? Set.from(_selectedVillageFilters!) : Set.from(allValues))
        : (_selectedSchoolFilters != null ? Set.from(_selectedSchoolFilters!) : Set.from(allValues));
    final dialogSearchController = TextEditingController();
    List<String> filteredValues = List.from(allValues);
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text("Filter"),
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
                  if (columnIndex == 0)
                    _selectedClusterFilters = currentSelection.length == allValues.length ? null : Set.from(currentSelection);
                  if (columnIndex == 1)
                    _selectedVillageFilters = currentSelection.length == allValues.length ? null : Set.from(currentSelection);
                  if (columnIndex == 2)
                    _selectedSchoolFilters = currentSelection.length == allValues.length ? null : Set.from(currentSelection);
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

  Future<void> _showManageDialog(String type, dynamic entity) async {
    final nameController = TextEditingController(text: entity['name']);
    final latController = TextEditingController(text: entity['latitude']?.toString() ?? '');
    final lngController = TextEditingController(text: entity['longitude']?.toString() ?? '');
    final radiusController = TextEditingController(text: entity['radius_meters']?.toString() ?? '50');
    String? selectedParentId = (type == 'Village') ? entity['cluster_id']?.toString() : entity['village_id']?.toString();
    GoogleMapController? mapController;
    MapType dialogMapType = MapType.normal;
    int mapRefreshKey = 0;
    double initialLat = entity['latitude'] != null ? double.tryParse(entity['latitude'].toString()) ?? 23.0225 : 23.0225;
    double initialLng = entity['longitude'] != null ? double.tryParse(entity['longitude'].toString()) ?? 72.5714 : 72.5714;
    LatLng? selectedLatLng = entity['latitude'] != null && entity['longitude'] != null ? LatLng(initialLat, initialLng) : null;
    void updateMapLocation() {
      final double? lat = double.tryParse(latController.text.trim());
      final double? lng = double.tryParse(lngController.text.trim());
      if (lat != null && lng != null && mapController != null) {
        mapController!.animateCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
      }
    }

    latController.addListener(updateMapLocation);
    lngController.addListener(updateMapLocation);
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget buildBaseMap({VoidCallback? onMapTapTrigger}) {
            return GoogleMap(
              key: ValueKey('manage_map_${mapRefreshKey}_${dialogMapType.name}'),
              initialCameraPosition: CameraPosition(target: LatLng(initialLat, initialLng), zoom: 14),
              mapType: dialogMapType,
              zoomControlsEnabled: true,
              myLocationButtonEnabled: false,
              gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
              onMapCreated: (ctrl) => mapController = ctrl,
              onTap: (latLng) {
                setDialogState(() {
                  selectedLatLng = latLng;
                  latController.text = latLng.latitude.toStringAsFixed(6);
                  lngController.text = latLng.longitude.toStringAsFixed(6);
                });
                if (onMapTapTrigger != null) onMapTapTrigger();
              },
              markers: selectedLatLng == null ? {} : {Marker(markerId: const MarkerId('edit_pin'), position: selectedLatLng!)},
              circles: selectedLatLng == null
                  ? {}
                  : {
                      Circle(
                        circleId: const CircleId('edit_geofence_circle'),
                        center: selectedLatLng!,
                        radius: double.tryParse(radiusController.text.trim()) ?? 50.0,
                        fillColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
                        strokeColor: AppTheme.primaryBlue,
                        strokeWidth: 2,
                      ),
                    },
            );
          }

          void openFullscreenMap() async {
            await Navigator.of(context).push(
              PageRouteBuilder(
                opaque: false,
                barrierDismissible: true,
                pageBuilder: (_, __, ___) => StatefulBuilder(
                  builder: (fsContext, setFsState) => Scaffold(
                    backgroundColor: Colors.black38,
                    body: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Material(
                          elevation: 12,
                          borderRadius: BorderRadius.circular(8),
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                child: _buildMapHeaderControl(
                                  context: context,
                                  currentType: dialogMapType,
                                  expanded: true,
                                  onTypeChanged: (type) {
                                    setDialogState(() {
                                      dialogMapType = type;
                                      mapRefreshKey++;
                                    });
                                    setFsState(() {});
                                  },
                                  onToggleFullscreen: () => Navigator.of(context).pop(),
                                ),
                              ),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                                  child: buildBaseMap(onMapTapTrigger: () => setFsState(() {})),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            setDialogState(() {});
          }

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.settings, color: AppTheme.primaryBlue),
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
                        items: _hierarchy
                            .map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['name'])))
                            .toList(),
                        onChanged: (val) => setDialogState(() => selectedParentId = val),
                      ),
                    if (type == 'School') ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: selectedParentId,
                        decoration: const InputDecoration(labelText: "Move to Village"),
                        onChanged: (val) => setDialogState(() => selectedParentId = val),
                        items: _hierarchy.expand((cluster) {
                          return (cluster['villages'] as List).map((village) {
                            return DropdownMenuItem<String>(
                              value: village['id'].toString(),
                              child: Text("${village['name']} (${cluster['name']})"),
                            );
                          });
                        }).toList(),
                      ),
                    ],
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(labelText: "$type Name"),
                    ),
                    if (type == 'School') ...[
                      const SizedBox(height: 16),
                      _buildMapHeaderControl(
                        context: context,
                        currentType: dialogMapType,
                        expanded: false,
                        onTypeChanged: (type) {
                          setDialogState(() {
                            dialogMapType = type;
                            mapRefreshKey++;
                          });
                        },
                        onToggleFullscreen: openFullscreenMap,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: buildBaseMap(),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: latController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: "Latitude"),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: lngController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: "Longitude"),
                            ),
                          ),
                        ],
                      ),
                      TextField(
                        controller: radiusController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "Geofence Radius (Meters)"),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Divider(),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _confirmDelete(type, entity);
                      },
                      icon: const Icon(Icons.delete, color: Colors.red),
                      label: Text("Delete this $type", style: const TextStyle(color: Colors.red)),
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
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    final Map<String, dynamic> updateData = {'name': name};
                    String table = type == 'Cluster' ? 'clusters' : (type == 'Village' ? 'villages' : 'schools');
                    if (type == 'Village') updateData['cluster_id'] = selectedParentId;
                    if (type == 'School') {
                      updateData['village_id'] = selectedParentId;
                      updateData['latitude'] = double.tryParse(latController.text.trim());
                      updateData['longitude'] = double.tryParse(lngController.text.trim());
                      updateData['radius_meters'] = double.tryParse(radiusController.text.trim()) ?? 50.0;
                    }
                    await _supabase.from(table).update(updateData).eq('id', entity['id']);
                    if (ctx.mounted) Navigator.pop(ctx);
                    _fetchHierarchy();
                    messenger.showSnackBar(SnackBar(content: Text("$type updated!")));
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text("Error: $e")));
                  }
                },
                child: const Text("Save Changes"),
              ),
            ],
          );
        },
      ),
    ).then((_) {
      latController.removeListener(updateMapLocation);
      lngController.removeListener(updateMapLocation);
    });
  }

  void _applyAllFilters() {
    final query = _searchController.text.toLowerCase().trim();
    final List<dynamic> result = [];
    for (final cluster in _hierarchy) {
      final clusterName = cluster['name'].toString();
      if (_selectedClusterFilters != null && !_selectedClusterFilters!.contains(clusterName)) continue;
      final List<dynamic> filteredVillages = [];
      for (final village in (cluster['villages'] ?? [])) {
        final villageName = village['name'].toString();
        if (_selectedVillageFilters != null && !_selectedVillageFilters!.contains(villageName)) continue;
        final List<dynamic> filteredSchools = [];
        for (final school in (village['schools'] ?? [])) {
          final schoolName = school['name'].toString();
          if (_selectedSchoolFilters != null && !_selectedSchoolFilters!.contains(schoolName)) continue;
          final matchesSearch =
              query.isEmpty ||
              clusterName.toLowerCase().contains(query) ||
              villageName.toLowerCase().contains(query) ||
              schoolName.toLowerCase().contains(query);
          if (matchesSearch) filteredSchools.add(school);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Locations Management"),
        backgroundColor: AppTheme.primaryBlue,
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
      floatingActionButton: FloatingActionButton(
        heroTag: "add_location_btn",
        onPressed: () => _showAddDialog('School'),
        backgroundColor: AppTheme.primaryBlue,
        child: const Icon(Icons.add_location_alt, color: Colors.white),
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
                    color: isSorted ? AppTheme.primaryBlue : Colors.grey,
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
                color: hasFilter ? AppTheme.primaryBlue.withAlpha(30) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.filter_alt, size: 18, color: hasFilter ? AppTheme.primaryBlue : Colors.grey.shade700),
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
      topSide = BorderSide(color: Colors.grey.shade900, width: 1.5);
    } else if (borderType == 2) {
      topSide = BorderSide(color: Colors.grey.shade600, width: 1.0);
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
                    color: (text.isEmpty || text == "-") ? Colors.grey : AppTheme.textPrimary,
                    decoration: (text.isEmpty || text == "-") ? null : TextDecoration.underline,
                    decorationStyle: TextDecorationStyle.dotted,
                  ),
                ),
              ),
              if (text.isNotEmpty && text != "-") const Icon(Icons.edit, size: 14, color: AppTheme.textPrimary),
            ],
          ),
        ),
      ),
    );
  }
}
