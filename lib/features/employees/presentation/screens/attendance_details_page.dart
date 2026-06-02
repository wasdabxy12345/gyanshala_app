import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:intl/intl.dart';

class AttendanceDetailsPage extends ConsumerWidget {
  final String userId;
  final String dateString;
  const AttendanceDetailsPage({super.key, required this.userId, required this.dateString});
  Future<List<Map<String, dynamic>>> _fetchDailyAttendanceLogs(WidgetRef ref) async {
    final supabase = ref.read(supabaseClientProvider);
    try {
      final response = await supabase
          .from('attendance')
          .select('*, schools(name)')
          .eq('user_id', userId)
          .gte('recorded_at', '$dateString 00:00:00+00')
          .lte('recorded_at', '$dateString 23:59:59+00')
          .order('recorded_at', ascending: true);
      final List<Map<String, dynamic>> logs = List<Map<String, dynamic>>.from(response);
      if (logs.isNotEmpty) {
        try {
          final profileResponse = await supabase.from('profiles').select('first_name, last_name, role').eq('id', userId).single();
          for (var log in logs) {
            log['profiles'] = profileResponse;
          }
        } catch (profileError) {
          debugPrint("Profile Fetch Error: $profileError");
        }
      }
      return logs;
    } catch (e, stackTrace) {
      debugPrint("Database Exception in AttendanceDetailsPage: $e");
      debugPrint("Stacktrace: $stackTrace");
      rethrow;
    }
  }

  String _calculateTotalHours(List<Map<String, dynamic>> logs) {
    Map<String, dynamic>? checkInLog;
    Map<String, dynamic>? checkOutLog;
    for (var log in logs) {
      if (log['status'] == 'check_in' && checkInLog == null) {
        checkInLog = log;
      }
      if (log['status'] == 'check_out') {
        checkOutLog = log;
      }
    }
    if (checkInLog != null && checkOutLog != null) {
      final start = DateTime.parse(checkInLog['recorded_at']);
      final end = DateTime.parse(checkOutLog['recorded_at']);
      final difference = end.difference(start);

      final hours = difference.inHours;
      final minutes = difference.inMinutes.remainder(60);
      final seconds = difference.inSeconds.remainder(60);

      if (hours > 0) {
        return "$hours hr $minutes min";
      } else if (minutes > 0) {
        return "$minutes min $seconds sec";
      } else {
        return "$seconds sec";
      }
    }
    return "Incomplete Cycle";
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Attendance Summary'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchDailyAttendanceLogs(ref),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Error loading details:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            );
          }

          final logs = snapshot.data ?? [];
          if (logs.isEmpty) {
            return const Center(child: Text('No details available for this day.'));
          }

          final profile = logs.first['profiles'] as Map<String, dynamic>?;
          final employeeName = profile != null
              ? "${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}".trim()
              : "Unknown Employee";
          final role = profile?['role'] ?? 'N/A';

          final formattedDate = DateFormat('dd MMMM yyyy').format(DateTime.parse(logs.first['recorded_at']).toLocal());
          final totalHours = _calculateTotalHours(logs);

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
                        Text(employeeName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text("Role: $role", style: TextStyle(color: Colors.grey[600])),
                        const Divider(height: 24),
                        _buildDetailRow(Icons.calendar_today, "Date Summary", formattedDate),
                        _buildDetailRow(Icons.timelapse, "Total Time Active", totalHours, valueColor: Colors.teal.shade700),
                        const Divider(height: 24),
                        const Text(
                          "Activity Timeline",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        ...logs.map((log) {
                          final isCheckIn = log['status'] == 'check_in';
                          final timeStr = DateFormat('hh:mm:ss a').format(DateTime.parse(log['recorded_at']).toLocal());
                          final schoolName = log['schools']?['name'] ?? "Off-site Location";
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              isCheckIn ? Icons.login_rounded : Icons.logout_rounded,
                              color: isCheckIn ? Colors.green : Colors.orange,
                            ),
                            title: Text(
                              isCheckIn ? "Checked In" : "Checked Out",
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(schoolName),
                            trailing: Text(
                              timeStr,
                              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w500),
                            ),
                          );
                        }),
                        const Divider(height: 24),
                        AttendanceMultiMapView(logs: logs, employeeName: employeeName),
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

  Widget _buildDetailRow(IconData icon, String label, String value, {Color? valueColor}) {
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
              Text(
                value,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: valueColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AttendanceMultiMapView extends StatefulWidget {
  final List<Map<String, dynamic>> logs;
  final String employeeName;

  const AttendanceMultiMapView({super.key, required this.logs, required this.employeeName});

  @override
  State<AttendanceMultiMapView> createState() => _AttendanceMultiMapViewState();
}

class _AttendanceMultiMapViewState extends State<AttendanceMultiMapView> {
  MapType _mapType = MapType.normal;
  int _mapRefreshKey = 0;
  GoogleMapController? _mapController;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  LatLngBounds? _mapBounds;

  @override
  void initState() {
    super.initState();
    _processGeometries();
  }

  void _processGeometries() {
    List<LatLng> tracePoints = [];

    for (var log in widget.logs) {
      final double? lat = log['latitude'] != null ? double.tryParse(log['latitude'].toString()) : null;
      final double? lng = log['longitude'] != null ? double.tryParse(log['longitude'].toString()) : null;

      if (lat != null && lng != null) {
        final point = LatLng(lat, lng);
        tracePoints.add(point);

        final bool isCheckIn = log['status'] == 'check_in';
        _markers.add(
          Marker(
            markerId: MarkerId(log['id'].toString()),
            position: point,
            icon: BitmapDescriptor.defaultMarkerWithHue(isCheckIn ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueOrange),
            infoWindow: InfoWindow(
              title: isCheckIn ? "Check-In Point" : "Check-Out Point",
              snippet: DateFormat('hh:mm a').format(DateTime.parse(log['recorded_at']).toLocal()),
            ),
          ),
        );
      }
    }
    if (tracePoints.length > 1) {
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route_trace'),
          points: tracePoints,
          color: Colors.indigo.withValues(alpha: 0.7),
          width: 4,
        ),
      );
    }
    if (tracePoints.isNotEmpty) {
      double minLat = tracePoints.first.latitude;
      double maxLat = tracePoints.first.latitude;
      double minLng = tracePoints.first.longitude;
      double maxLng = tracePoints.first.longitude;
      for (var p in tracePoints) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      _mapBounds = LatLngBounds(
        southwest: LatLng(minLat - 0.001, minLng - 0.001),
        northeast: LatLng(maxLat + 0.001, maxLng + 0.001),
      );
    }
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
              onPressed: expanded ? () => Navigator.of(context).pop() : _openExpandedView,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBaseMapWidget() {
    if (_markers.isEmpty) return const SizedBox();

    return GoogleMap(
      key: ValueKey('multi_attendance_map_${_mapRefreshKey}_${_mapType.name}'),
      mapType: _mapType,
      initialCameraPosition: CameraPosition(target: _markers.first.position, zoom: 15.0),
      markers: _markers,
      polylines: _polylines,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: true,
      gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
      onMapCreated: (controller) {
        _mapController = controller;
        if (_mapBounds != null) {
          _mapController?.animateCamera(CameraUpdate.newLatLngBounds(_mapBounds!, 50));
        }
      },
    );
  }

  void _openExpandedView() async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        pageBuilder: (_, _, _) {
          return Scaffold(
            backgroundColor: Colors.black38,
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
                        child: _buildMapHeader(expanded: true, onRefresh: () => setState(() {})),
                      ),
                      Expanded(child: _buildBaseMapWidget()),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_markers.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMapHeader(),
        const SizedBox(height: 8),
        Container(
          height: 250,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          clipBehavior: Clip.antiAlias,
          child: _buildBaseMapWidget(),
        ),
      ],
    );
  }
}
