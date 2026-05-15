import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class BoundaryPicker extends StatefulWidget {
  final List<LatLng> initialPoints;
  final Function(List<LatLng>) onBoundaryChanged;
  const BoundaryPicker({super.key, required this.onBoundaryChanged, this.initialPoints = const []});
  @override
  State<BoundaryPicker> createState() => _BoundaryPickerState();
}

class _BoundaryPickerState extends State<BoundaryPicker> {
  List<LatLng> _points = [];
  final List<List<LatLng>> _history = [];
  int _historyIndex = -1;
  static const LatLng _center = LatLng(23.0225, 72.5714);
  final TextEditingController _coordinateController = TextEditingController();
  GoogleMapController? _mapController;
  int _mapRefreshKey = 0;
  LatLng _mapCenter = _center;
  MapType _mapType = MapType.normal;

  void _saveHistory() {
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(List.from(_points));
    _historyIndex++;
    widget.onBoundaryChanged(_points);
  }

  void _undo() {
    if (_historyIndex > 0) {
      setState(() {
        _historyIndex--;
        _points = List.from(_history[_historyIndex]);
      });
      widget.onBoundaryChanged(_points);
      _refreshMap();
    } else if (_historyIndex == 0) {
      setState(() {
        _historyIndex = -1;
        _points = [];
      });
      widget.onBoundaryChanged(_points);
      _refreshMap();
    }
  }

  void _redo() {
    if (_historyIndex < _history.length - 1) {
      setState(() {
        _historyIndex++;
        _points = List.from(_history[_historyIndex]);
      });
      widget.onBoundaryChanged(_points);
      _refreshMap();
    }
  }

  void _onTap(LatLng point) {
    setState(() {
      _points.add(point);
      _saveHistory();
    });
  }

  void _onMarkerDragEnd(int index, LatLng newPosition) {
    setState(() {
      _points[index] = newPosition;
      _saveHistory();
    });
  }

  void _removePoint(int index) {
    setState(() {
      _points.removeAt(index);
      _saveHistory();
      _mapRefreshKey++;
    });
  }

  void _moveToCoordinates(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) return;
    try {
      final cleaned = text.replaceAll(',', ' ');
      final parts = cleaned.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
      if (parts.length < 2) {
        throw Exception("Invalid format");
      }
      final lat = double.parse(parts[0]);
      final lng = double.parse(parts[1]);
      final target = LatLng(lat, lng);
      setState(() {
        _mapCenter = target;
      });
      _mapController?.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: target, zoom: 22)));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Map centered to pasted coordinates")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid coordinates. Example: 23.0225, 72.5714")));
    }
  }

  void _refreshMap() {
    setState(() {
      _mapRefreshKey++;
    });
  }

  Widget _buildMapTypeButton({required IconData icon, required String label, required MapType type, VoidCallback? onRefresh}) {
    final bool isSelected = _mapType == type;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          if (_mapType == type) return;

          setState(() {
            _mapType = type;

            // force native map rebuild
            _mapController = null;
            _mapRefreshKey++;
          });

          onRefresh?.call();

          debugPrint("Changed map type to $type");
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.indigo : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.black87),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : Colors.black87),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar({bool expanded = false, VoidCallback? onRefresh}) {
    return SizedBox(
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.undo),
                  onPressed: _historyIndex >= 0
                      ? () {
                          _undo();
                          onRefresh?.call();
                        }
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.redo),
                  onPressed: _historyIndex < _history.length - 1
                      ? () {
                          _redo();
                          onRefresh?.call();
                        }
                      : null,
                ),
                Text("${_points.length} points", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                IconButton(
                  icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                  onPressed: () {
                    setState(() {
                      _points.clear();
                      _saveHistory();
                      _mapRefreshKey++;
                    });
                    onRefresh?.call();
                  },
                ),
              ],
            ),
          ),
          Center(
            child: Text(
              "Tip: Tap a pin to delete it. Hold and drag to move it.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey.shade700),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.all(2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildMapTypeButton(icon: Icons.map, label: "Map", type: MapType.normal, onRefresh: onRefresh),
                      _buildMapTypeButton(icon: Icons.satellite_alt, label: "Sat", type: MapType.satellite, onRefresh: onRefresh),
                      _buildMapTypeButton(icon: Icons.layers, label: "Hybrid", type: MapType.hybrid, onRefresh: onRefresh),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(expanded ? Icons.fullscreen_exit : Icons.fullscreen),
                  tooltip: expanded ? "Exit Expanded View" : "Expand Map",
                  onPressed: expanded ? () => Navigator.of(context).pop() : _openExpandedMap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoordinateControls({required TextEditingController controller}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: "Paste coordinates (lat, lng)",
                prefixIcon: const Icon(Icons.location_searching),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
              onSubmitted: (_) => _moveToCoordinates(controller.text),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 80, maxWidth: 120, minHeight: 48),
            child: ElevatedButton.icon(
              onPressed: () => _moveToCoordinates(controller.text),
              icon: const Icon(Icons.my_location),
              label: const Text("Go"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap({double? height}) {
    debugPrint("🗺️ BUILD MAP - mapType=$_mapType key=$_mapRefreshKey");
    return KeyedSubtree(
      key: ValueKey('map_wrapper_${_mapRefreshKey}_${_mapType.name}'),
      child: Container(
        height: height ?? 300,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.indigo.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: GoogleMap(
            mapType: _mapType,
            initialCameraPosition: CameraPosition(target: _mapCenter, zoom: 15),
            onTap: _onTap,
            polygons: {
              if (_points.length > 2)
                Polygon(
                  polygonId: const PolygonId('boundary'),
                  points: _points,
                  fillColor: Colors.indigo.withValues(alpha: 0.2),
                  strokeColor: Colors.indigo,
                  strokeWidth: 2,
                ),
            },
            markers: _points.asMap().entries.map((entry) {
              int idx = entry.key;
              LatLng pos = entry.value;
              return Marker(
                markerId: MarkerId('p_$idx'),
                position: pos,
                draggable: true,
                onDragEnd: (newPos) => _onMarkerDragEnd(idx, newPos),
                onTap: () => _removePoint(idx),
                infoWindow: const InfoWindow(title: "Tap to remove, Drag to move"),
              );
            }).toSet(),
            gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
            onMapCreated: (controller) {
              _mapController = controller;
              debugPrint("✅ GoogleMap CREATED (native view initialized)");
            },
          ),
        ),
      ),
    );
  }

  void _openExpandedMap() async {
    final expandedController = TextEditingController();
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        pageBuilder: (_, _, _) {
          return StatefulBuilder(
            builder: (context, dialogSetState) {
              return Scaffold(
                backgroundColor: Colors.black.withValues(alpha: 0.25),
                body: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Material(
                      elevation: 12,
                      borderRadius: BorderRadius.circular(0),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          Container(
                            color: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: _buildToolbar(expanded: true, onRefresh: () => dialogSetState(() {})),
                          ),
                          Container(
                            color: Colors.white,
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                            child: _buildCoordinateControls(controller: expandedController),
                          ),
                          Expanded(
                            child: GoogleMap(
                              key: ValueKey('expanded_${_mapRefreshKey}_${_mapType.name}'),
                              mapType: _mapType,
                              initialCameraPosition: CameraPosition(target: _mapCenter, zoom: 15),
                              onTap: (point) {
                                dialogSetState(() {
                                  _points.add(point);
                                  _saveHistory();
                                });
                              },
                              polygons: {
                                if (_points.length > 2)
                                  Polygon(
                                    polygonId: const PolygonId('boundary'),
                                    points: _points,
                                    fillColor: Colors.indigo.withValues(alpha: 0.2),
                                    strokeColor: Colors.indigo,
                                    strokeWidth: 2,
                                  ),
                              },
                              markers: _points.asMap().entries.map((entry) {
                                int idx = entry.key;
                                LatLng pos = entry.value;
                                return Marker(
                                  markerId: MarkerId('p_$idx'),
                                  position: pos,
                                  draggable: true,
                                  onDragEnd: (newPos) {
                                    dialogSetState(() {
                                      _points[idx] = newPos;
                                      _saveHistory();
                                    });
                                  },
                                  onTap: () {
                                    dialogSetState(() {
                                      _points.removeAt(idx);
                                      _saveHistory();
                                      _mapRefreshKey++;
                                    });
                                  },
                                  infoWindow: const InfoWindow(title: "Tap to remove, Drag to move"),
                                );
                              }).toSet(),
                              gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
                              onMapCreated: (controller) {
                                _mapController = controller;
                                debugPrint("✅ GoogleMap CREATED (native view initialized)");
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _points = List.from(widget.initialPoints);
    if (_points.isNotEmpty) {
      _mapCenter = _points.first;
      _history.add(List.from(_points));
      _historyIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(),
        _buildCoordinateControls(controller: _coordinateController),
        _buildMap(),
      ],
    );
  }
}
