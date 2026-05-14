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

  LatLng _mapCenter = _center;

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
    } else if (_historyIndex == 0) {
      setState(() {
        _historyIndex = -1;

        _points = [];
      });

      widget.onBoundaryChanged(_points);
    }
  }

  void _redo() {
    if (_historyIndex < _history.length - 1) {
      setState(() {
        _historyIndex++;

        _points = List.from(_history[_historyIndex]);
      });

      widget.onBoundaryChanged(_points);
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
    });
  }

  void _moveToCoordinates() {
    final text = _coordinateController.text.trim();

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

      _mapController?.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: target, zoom: 18)));

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Map centered to pasted coordinates")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid coordinates. Example: 23.0225, 72.5714")));
    }
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
        Row(
          children: [
            IconButton(icon: const Icon(Icons.undo), onPressed: _historyIndex >= 0 ? _undo : null, tooltip: "Undo"),

            IconButton(
              icon: const Icon(Icons.redo),

              onPressed: _historyIndex < _history.length - 1 ? _redo : null,

              tooltip: "Redo",
            ),

            const Spacer(),

            Text("${_points.length} points", style: const TextStyle(fontSize: 12, color: Colors.grey)),

            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),

              onPressed: () => setState(() {
                _points.clear();

                _saveHistory();
              }),

              tooltip: "Clear All",
            ),
          ],
        ),

        Padding(
          padding: const EdgeInsets.only(bottom: 10),

          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _coordinateController,

                  decoration: InputDecoration(
                    hintText: "Paste coordinates (lat, lng)",

                    prefixIcon: const Icon(Icons.location_searching),

                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),

                    isDense: true,
                  ),

                  onSubmitted: (_) => _moveToCoordinates(),
                ),
              ),

              const SizedBox(width: 8),

              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 80, maxWidth: 120, minHeight: 48),

                child: ElevatedButton.icon(
                  onPressed: _moveToCoordinates,

                  icon: const Icon(Icons.my_location),

                  label: const Text("Go"),
                ),
              ),
            ],
          ),
        ),

        Container(
          height: 300,

          decoration: BoxDecoration(
            border: Border.all(color: Colors.indigo.withValues(alpha: 0.3)),

            borderRadius: BorderRadius.circular(12),
          ),

          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),

            child: GoogleMap(
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
              },
            ),
          ),
        ),

        const Padding(
          padding: EdgeInsets.only(top: 4),

          child: Text(
            "Tip: Tap a pin to delete it. Hold and drag to move it.",

            style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic),
          ),
        ),
      ],
    );
  }
}
