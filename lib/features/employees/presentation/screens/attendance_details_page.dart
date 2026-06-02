import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:intl/intl.dart';

class AttendanceDetailsPage extends ConsumerWidget {
  final String attendanceId;

  const AttendanceDetailsPage({super.key, required this.attendanceId});

  Future<Map<String, dynamic>> _fetchAttendanceRecordDetails(WidgetRef ref) async {
    final supabase = ref.read(supabaseClientProvider);

    try {
      final attendanceResponse = await supabase.from('attendance').select('*, schools(name)').eq('id', attendanceId).single();

      final attendanceData = Map<String, dynamic>.from(attendanceResponse);
      final userId = attendanceData['user_id'];

      if (userId != null) {
        try {
          final profileResponse = await supabase.from('profiles').select('first_name, last_name, role').eq('id', userId).single();

          attendanceData['profiles'] = profileResponse;
        } catch (profileError) {
          debugPrint("Profile Fetch Error: $profileError");
          attendanceData['profiles'] = null;
        }
      }

      return attendanceData;
    } catch (e, stackTrace) {
      debugPrint("Database Exception in AttendanceDetailsPage: $e");
      debugPrint("Stacktrace: $stackTrace");
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance Details'), backgroundColor: Colors.indigo, foregroundColor: Colors.white),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _fetchAttendanceRecordDetails(ref),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Failed to load details.\nError: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('No details available for this record.'));
          }

          final data = snapshot.data!;
          final profile = data['profiles'] as Map<String, dynamic>?;
          final school = data['schools'] as Map<String, dynamic>?;

          final employeeName = profile != null
              ? "${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}".trim()
              : "Unknown Employee";

          final role = profile?['role'] ?? 'N/A';
          final recordedAtRaw = data['recorded_at'];
          final parsedDate = recordedAtRaw != null ? DateTime.parse(recordedAtRaw).toLocal() : DateTime.now();

          final double? lat = data['latitude'] != null ? double.tryParse(data['latitude'].toString()) : null;
          final double? lng = data['longitude'] != null ? double.tryParse(data['longitude'].toString()) : null;
          LatLng? checkInLocation;
          if (lat != null && lng != null) {
            checkInLocation = LatLng(lat, lng);
          }

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: ListView(
              children: [
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          employeeName.isEmpty ? "Unknown Employee" : employeeName,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text("Role: $role", style: TextStyle(color: Colors.grey[600])),
                        const Divider(height: 24),

                        _buildDetailRow(Icons.calendar_today, "Date", DateFormat('dd MMMM yyyy').format(parsedDate)),
                        _buildDetailRow(Icons.access_time, "Time", DateFormat('hh:mm a').format(parsedDate)),
                        _buildDetailRow(Icons.check_circle, "Status", data['status']?.toString().toUpperCase() ?? 'N/A'),
                        _buildDetailRow(Icons.school, "School/Location", school?['name'] ?? "Off-site"),

                        const Divider(height: 24),

                        if (checkInLocation != null) ...[
                          AttendanceMapView(location: checkInLocation, employeeName: employeeName),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(child: _buildDetailRow(Icons.location_on, "Latitude", "$lat")),
                              Expanded(child: _buildDetailRow(Icons.location_on, "Longitude", "$lng")),
                            ],
                          ),
                        ] else ...[
                          Container(
                            height: 120,
                            width: double.infinity,
                            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                            child: const Center(
                              child: Text(
                                "No GPS Coordinates Captured for this Record",
                                style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.blueGrey, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }
}

class AttendanceMapView extends StatefulWidget {
  final LatLng location;
  final String employeeName;

  const AttendanceMapView({super.key, required this.location, required this.employeeName});

  @override
  State<AttendanceMapView> createState() => _AttendanceMapViewState();
}

class _AttendanceMapViewState extends State<AttendanceMapView> {
  MapType _mapType = MapType.normal;
  int _mapRefreshKey = 0;
  GoogleMapController? _mapController; // Linter warning resolved below!

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
            _mapController = null;
            _mapRefreshKey++;
          });
          onRefresh?.call();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? Colors.indigo : Colors.transparent,
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

  Widget _buildMapHeader({bool expanded = false, VoidCallback? onRefresh}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          "Verification Map",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
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
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(expanded ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.indigo),
              tooltip: expanded ? "Exit Fullscreen" : "Fullscreen View",
              onPressed: expanded ? () => Navigator.of(context).pop() : _openExpandedView,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBaseMapWidget({bool isExpanded = false}) {
    return GoogleMap(
      key: ValueKey('attendance_map_${isExpanded ? "exp" : "base"}_${_mapRefreshKey}_${_mapType.name}'),
      mapType: _mapType,
      initialCameraPosition: CameraPosition(target: widget.location, zoom: 16.0),
      markers: {
        Marker(
          markerId: const MarkerId('checkInPoint'),
          position: widget.location,
          infoWindow: InfoWindow(title: widget.employeeName, snippet: "Checked-in here"),
        ),
      },
      myLocationButtonEnabled: false,
      zoomControlsEnabled: true,
      gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
      onMapCreated: (controller) {
        _mapController = controller;
        // USING IT HERE: Automatically centers camera position contextually on compile initialization
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(widget.location, 16.0));
      },
    );
  }

  void _openExpandedView() async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        pageBuilder: (_, _, _) {
          return StatefulBuilder(
            builder: (context, dialogSetState) {
              return Scaffold(
                backgroundColor: Colors.black.withValues(alpha: 0.3),
                body: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Material(
                      elevation: 12,
                      child: Column(
                        children: [
                          Container(
                            color: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: _buildMapHeader(expanded: true, onRefresh: () => dialogSetState(() {})),
                          ),
                          Expanded(child: _buildBaseMapWidget(isExpanded: true)),
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
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMapHeader(),
        const SizedBox(height: 8),
        Container(
          height: 220,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          clipBehavior: Clip.antiAlias,
          child: _buildBaseMapWidget(isExpanded: false),
        ),
      ],
    );
  }
}
