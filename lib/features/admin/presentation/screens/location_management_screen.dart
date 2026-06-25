import 'dart:io';
import 'dart:math' as math;

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
              'radius': 50.0,
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
        final rawLng = row.length > 3 ? row[3]?.value?.toString().trim() : null;
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
          .select('id, name, villages(id, name, cluster_id, schools(id, name, village_id, latitude, longitude, radius)))')
          .order('name', ascending: true);
      if (mounted) {
        setState(() {
          _hierarchy = data;
          _applyAllFilters();
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
            style: const TextStyle(color: Colors.black, fontSize: 13),
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
            height: 350,
            child: Column(
              children: [
                TextField(
                  controller: dialogSearchController,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search)),
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

  Future<void> _showLocationFormDialog(LocationFormConfig config) async {
    final nameController = TextEditingController(text: config.isEditMode ? config.entity['name'] : '');
    final latController = TextEditingController(text: config.isEditMode ? config.entity['latitude']?.toString() ?? '' : '');
    final lngController = TextEditingController(text: config.isEditMode ? config.entity['longitude']?.toString() ?? '' : '');
    final radiusController = TextEditingController(text: config.isEditMode ? config.entity['radius']?.toString() ?? '50' : '50');

    String? selectedClusterId = config.isEditMode && config.type == 'Village' ? config.entity['cluster_id']?.toString() : null;
    String? selectedVillageId = config.isEditMode && config.type == 'School' ? config.entity['village_id']?.toString() : null;

    if (config.isEditMode && config.type == 'School' && selectedVillageId != null) {
      try {
        final matchingCluster = _hierarchy.firstWhere(
          (c) => (c['villages'] as List).any((v) => v['id'].toString() == selectedVillageId),
        );
        selectedClusterId = matchingCluster['id'].toString();
      } catch (_) {}
    }

    GoogleMapController? mapController;
    MapType dialogMapType = MapType.normal;
    int mapRefreshKey = 0;

    double initialLat = config.isEditMode && config.entity['latitude'] != null
        ? double.tryParse(config.entity['latitude'].toString()) ?? 0
        : 0;
    double initialLng = config.isEditMode && config.entity['longitude'] != null
        ? double.tryParse(config.entity['longitude'].toString()) ?? 0
        : 0;
    LatLng? selectedLatLng = initialLat != 0 || initialLng != 0 ? LatLng(initialLat, initialLng) : null;

    void updateMapLocation() {
      final double? lat = double.tryParse(latController.text.trim());
      final double? lng = double.tryParse(lngController.text.trim());
      final double radius = double.tryParse(radiusController.text.trim()) ?? 50;

      if (lat != null && lng != null && mapController != null) {
        _fitCircleInView(controller: mapController!, center: LatLng(lat, lng), radiusMeters: radius);
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
          final double currentRadius = double.tryParse(radiusController.text.trim()) ?? 50.0;

          Widget buildUnifiedMapCanvas({VoidCallback? onTapOverride}) {
            return _LocationMapCanvas(
              refreshKey: mapRefreshKey,
              mapType: dialogMapType,
              selectedLatLng: selectedLatLng,
              initialLat: initialLat,
              initialLng: initialLng,
              currentRadius: currentRadius,
              onMapCreated: (ctrl) async {
                mapController = ctrl;
                if (selectedLatLng != null) {
                  await Future.delayed(const Duration(milliseconds: 150));
                  await _fitCircleInView(controller: ctrl, center: selectedLatLng!, radiusMeters: currentRadius);
                }
              },
              onTap: (latLng) async {
                setDialogState(() {
                  selectedLatLng = latLng;
                  latController.text = latLng.latitude.toStringAsFixed(6);
                  lngController.text = latLng.longitude.toStringAsFixed(6);
                });
                if (onTapOverride != null) onTapOverride();
                updateMapLocation();
                if (mapController != null) {
                  await _fitCircleInView(controller: mapController!, center: latLng, radiusMeters: currentRadius);
                }
              },
            );
          }

          void handleFullscreenPipeline() async {
            await Navigator.of(context).push(
              PageRouteBuilder(
                opaque: false,
                barrierDismissible: true,
                pageBuilder: (_, __, ___) => StatefulBuilder(
                  builder: (fsCtx, setFsState) => Scaffold(
                    backgroundColor: Colors.black38,
                    body: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Material(
                          elevation: 13,
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
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
                              Expanded(child: buildUnifiedMapCanvas(onTapOverride: () => setFsState(() {}))),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            setDialogState(() {
              mapRefreshKey++;
            });
          }

          double sizeMultiplier = config.type == 'School' ? 0.9 : 0.3;

          return AlertDialog(
            title: config.isEditMode ? null : Text("Add New ${config.type}"),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * sizeMultiplier,
              height: MediaQuery.of(context).size.height * sizeMultiplier,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 1,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!config.isEditMode && config.type == 'School') ...[
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _importFromExcel();
                              },
                              icon: const Icon(Icons.upload_file),
                              label: const Text("Import Schools via Excel"),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(37),
                                foregroundColor: AppTheme.primaryBlue,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(),
                              child: Row(
                                children: [
                                  Expanded(child: Divider()),
                                  Padding(
                                    padding: EdgeInsets.symmetric(),
                                    child: Text("OR MANUALLY", style: TextStyle(fontSize: 13, color: Colors.grey)),
                                  ),
                                  Expanded(child: Divider()),
                                ],
                              ),
                            ),
                          ],
                          if (config.type == 'Village' || config.type == 'School')
                            DropdownButtonFormField<String>(
                              initialValue: selectedClusterId,
                              hint: const Text("Select Cluster"),
                              decoration: config.isEditMode ? const InputDecoration(labelText: "Cluster") : null,
                              items: [
                                if (!config.isEditMode)
                                  const DropdownMenuItem(
                                    value: "ADD_NEW",
                                    child: Text(
                                      "+ Add New Cluster...",
                                      style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold),
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
                          if (config.type == 'School') ...[
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              initialValue: selectedVillageId,
                              hint: const Text("Select Village"),
                              disabledHint: const Text("Select a Cluster first"),
                              decoration: config.isEditMode ? const InputDecoration(labelText: "Village") : null,
                              items: selectedClusterId == null
                                  ? []
                                  : [
                                      if (!config.isEditMode)
                                        const DropdownMenuItem(
                                          value: "ADD_NEW",
                                          child: Text(
                                            "+ Add New Village...",
                                            style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ...(_hierarchy.firstWhere((c) => c['id'].toString() == selectedClusterId)['villages']
                                              as List)
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
                          const SizedBox(height: 13),
                          TextField(
                            controller: nameController,
                            decoration: InputDecoration(labelText: config.isEditMode ? config.type : "${config.type} Name"),
                          ),
                          if (config.type == 'School') ...[
                            const SizedBox(height: 13),
                            TextField(
                              controller: latController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: "Latitude"),
                            ),
                            const SizedBox(height: 13),
                            TextField(
                              controller: lngController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: "Longitude"),
                            ),
                            const SizedBox(height: 13),
                            TextField(
                              controller: radiusController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: "Radius"),
                              onChanged: (_) async {
                                setDialogState(() {});
                                updateMapLocation();
                                if (mapController != null && selectedLatLng != null) {
                                  await _fitCircleInView(
                                    controller: mapController!,
                                    center: selectedLatLng!,
                                    radiusMeters: currentRadius,
                                  );
                                }
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (config.type == 'School') ...[
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
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
                            onToggleFullscreen: handleFullscreenPipeline,
                          ),
                          const SizedBox(height: 13),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
                              clipBehavior: Clip.antiAlias,
                              child: buildUnifiedMapCanvas(),
                            ),
                          ),
                          const SizedBox(height: 13),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              Row(
                children: [
                  if (config.isEditMode)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _confirmDelete(config.type, config.entity);
                      },
                      icon: const Icon(Icons.delete, color: Colors.red),
                      label: const Text("Delete", style: TextStyle(color: Colors.red)),
                    ),
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                  const SizedBox(width: 13),
                  ElevatedButton(
                    onPressed: () async {
                      final name = nameController.text.trim();
                      if (name.isEmpty) return;
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        final Map<String, dynamic> dataPayload = {'name': name};
                        String table = config.type == 'Cluster'
                            ? 'clusters'
                            : (config.type == 'Village' ? 'villages' : 'schools');

                        if (config.type == 'Village') dataPayload['cluster_id'] = selectedClusterId;
                        if (config.type == 'School') {
                          dataPayload['village_id'] = selectedVillageId;
                          dataPayload['latitude'] = double.tryParse(latController.text.trim());
                          dataPayload['longitude'] = double.tryParse(lngController.text.trim());
                          dataPayload['radius'] = double.tryParse(radiusController.text.trim()) ?? 50.0;
                        }

                        if (config.isEditMode) {
                          await _supabase.from(table).update(dataPayload).eq('id', config.entity['id']);
                        } else {
                          await _supabase.from(table).insert(dataPayload);
                        }

                        if (ctx.mounted) Navigator.pop(ctx);
                        _fetchHierarchy();
                        messenger.showSnackBar(SnackBar(content: Text("${config.type} saved successfully!")));
                      } catch (e) {
                        messenger.showSnackBar(SnackBar(content: Text("Error: $e")));
                      }
                    },
                    child: Text(config.isEditMode ? "Save Changes" : "Save"),
                  ),
                ],
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

  Future<void> _showAddDialog(String type) async {
    await _showLocationFormDialog(LocationFormConfig(type: type, isEditMode: false));
  }

  Future<void> _showManageDialog(String type, dynamic entity) async {
    await _showLocationFormDialog(LocationFormConfig(type: type, isEditMode: true, entity: entity));
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
          onTap: () => onTypeChanged(type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(color: isSelected ? AppTheme.primaryBlue : Colors.transparent),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: isSelected ? Colors.white : Colors.black),
                const SizedBox(width: 3),
                Text(
                  label,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : Colors.black),
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
          decoration: BoxDecoration(color: Colors.grey.shade300),
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

  Future<void> _fitCircleInView({
    required GoogleMapController controller,
    required LatLng center,
    required double radiusMeters,
  }) async {
    final latOffset = radiusMeters / 111320.0;

    final lngOffset = radiusMeters / (111320.0 * math.cos(center.latitude * math.pi / 180));

    final bounds = LatLngBounds(
      southwest: LatLng(center.latitude - latOffset, center.longitude - lngOffset),
      northeast: LatLng(center.latitude + latOffset, center.longitude + lngOffset),
    );

    await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 37));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Location Management"),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchHierarchy, tooltip: "Refresh")],
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
                  const Padding(padding: EdgeInsets.all(13)),
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
        child: const Icon(Icons.add_location, color: Colors.white),
      ),
    );
  }
}

class _LocationMapCanvas extends StatelessWidget {
  final int refreshKey;
  final MapType mapType;
  final LatLng? selectedLatLng;
  final double initialLat;
  final double initialLng;
  final double currentRadius;
  final ArgumentCallback<GoogleMapController> onMapCreated;
  final ArgumentCallback<LatLng> onTap;

  const _LocationMapCanvas({
    required this.refreshKey,
    required this.mapType,
    required this.selectedLatLng,
    required this.initialLat,
    required this.initialLng,
    required this.currentRadius,
    required this.onMapCreated,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      key: ValueKey('unified_canvas_${refreshKey}_${mapType.name}'),
      initialCameraPosition: CameraPosition(target: selectedLatLng ?? LatLng(initialLat, initialLng), zoom: 13),
      mapType: mapType,
      zoomControlsEnabled: true,
      myLocationButtonEnabled: true,
      gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
      onMapCreated: onMapCreated,
      onTap: onTap,
      markers: selectedLatLng == null ? {} : {Marker(markerId: const MarkerId('canvas_pin'), position: selectedLatLng!)},
      circles: selectedLatLng == null
          ? {}
          : {
              Circle(
                circleId: const CircleId('canvas_geofence'),
                center: selectedLatLng!,
                radius: currentRadius,
                fillColor: Colors.blue.withAlpha(37),
                strokeColor: Colors.blue,
                strokeWidth: 2,
              ),
            },
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
                  const SizedBox(width: 3),
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
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: hasFilter ? AppTheme.primaryBlue.withAlpha(30) : Colors.transparent),
              child: Icon(Icons.filter_alt, size: 13, color: hasFilter ? AppTheme.primaryBlue : Colors.grey.shade700),
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
                    decorationStyle: TextDecorationStyle.dotted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LocationFormConfig {
  final String type;
  final bool isEditMode;
  final dynamic entity;

  LocationFormConfig({required this.type, this.isEditMode = false, this.entity});
}
