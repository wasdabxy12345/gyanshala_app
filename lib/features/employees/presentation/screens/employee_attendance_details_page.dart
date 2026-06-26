import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:intl/intl.dart';

class EmployeeAttendanceDetailsPage extends ConsumerWidget {
  final String userId;
  final String dateString;
  const EmployeeAttendanceDetailsPage({super.key, required this.userId, required this.dateString});

  Future<Map<String, dynamic>> _fetchPageData(WidgetRef ref) async {
    final supabase = ref.read(supabaseClientProvider);
    try {
      final futures = await Future.wait([
        supabase
            .from('employee_attendance')
            .select('*, schools(name)')
            .eq('user_id', userId)
            .gte('recorded_at', '$dateString 00:00:00+00')
            .lte('recorded_at', '$dateString 23:59:59+00')
            .order('recorded_at', ascending: true),
        supabase.from('schools').select('id, name, latitude, longitude, radius'),
      ]);
      final List<Map<String, dynamic>> logs = List<Map<String, dynamic>>.from(futures[0]);
      final List<Map<String, dynamic>> schools = List<Map<String, dynamic>>.from(futures[1]);

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
      return {'logs': logs, 'schools': schools};
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

  Map<String, dynamic>? _checkSchoolGeofence(double? lat, double? lng, List<Map<String, dynamic>> schools) {
    if (lat == null || lng == null) return null;
    for (var school in schools) {
      final double? sLat = school['latitude'] != null ? double.tryParse(school['latitude'].toString()) : null;
      final double? sLng = school['longitude'] != null ? double.tryParse(school['longitude'].toString()) : null;
      final double radius = double.tryParse(school['radius'].toString()) ?? 50.0;
      if (sLat != null && sLng != null) {
        final distance = _coordinateDistance(lat, lng, sLat, sLng);
        if (distance <= radius) {
          return school;
        }
      }
    }
    return null;
  }

  double _coordinateDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var c = math.cos;
    var a = 0.5 - c((lat2 - lat1) * p) / 2 + c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * math.asin(math.sqrt(a)) * 1000;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool useWideLayout = screenWidth > 850;

    return Scaffold(
      appBar: AppBar(title: const Text('Daily Attendance Summary')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _fetchPageData(ref),
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
          final data = snapshot.data;
          final List<Map<String, dynamic>> logs = data?['logs'] ?? [];
          final List<Map<String, dynamic>> schools = data?['schools'] ?? [];

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

          Widget logsDetailsPanel() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(employeeName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 13),
                Text("Role: $role", style: TextStyle(color: Colors.grey[600])),
                const Divider(height: 13),
                Text("Date: $formattedDate"),
                Text("Total Time Active: $totalHours"),
                const Divider(height: 13),
                ...logs.map((log) {
                  final isCheckIn = log['status'] == 'check_in';
                  final timeStr = DateFormat('hh:mm:ss a').format(DateTime.parse(log['recorded_at']).toLocal());
                  final double? lat = log['latitude'] != null ? double.tryParse(log['latitude'].toString()) : null;
                  final double? lng = log['longitude'] != null ? double.tryParse(log['longitude'].toString()) : null;

                  // Geofence Check and Location Safety Fallbacks
                  final matchingSchool = _checkSchoolGeofence(lat, lng, schools);
                  final bool isAtSchool = matchingSchool != null;
                  final String presenceSubtitle = isAtSchool ? "At: ${matchingSchool['name']}" : "off-site";

                  // Extracting Time Variances with Fallback Logic
                  final String variance = log['attendance_time_variance']?.toString() ?? "99:99:99";
                  final bool isOnTime = variance == "00:00:00" || variance == "00:00:00.000";

                  // Evaluating Context Matrix Styling Configuration Variables
                  IconData statusIcon;
                  Color statusColor;
                  String statusLabel;

                  if (isAtSchool && isOnTime) {
                    statusIcon = Icons.check;
                    statusColor = Colors.green;
                    statusLabel = isCheckIn ? "On-Time Check In" : "On-Time Check Out";
                  } else if (isAtSchool && !isOnTime) {
                    statusIcon = Icons.access_time;
                    statusColor = Colors.amber;
                    statusLabel = variance == "99:99:99" ? "Timing Untracked" : "Wrong Time (Variance: $variance)";
                  } else if (!isAtSchool && isOnTime) {
                    statusIcon = Icons.wrong_location;
                    statusColor = Colors.amber;
                    statusLabel = "Off-Site Check";
                  } else {
                    statusIcon = Icons.warning;
                    statusColor = Colors.purple; // Deep Purple Warning Configuration
                    statusLabel = variance == "99:99:99" ? "Off-Site & Untracked" : "Off-Site & Wrong Time ($variance)";
                  }

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(statusIcon, color: statusColor, size: 26),
                    title: Row(
                      children: [
                        Text(isCheckIn ? "Check In" : "Check Out", style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            border: Border.all(color: statusColor, width: 0.5),
                          ),
                          child: Text(
                            isAtSchool ? "at a school" : "Off-Site",
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: statusColor),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(presenceSubtitle),
                        Text(
                          statusLabel,
                          style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    trailing: Text(timeStr, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  );
                }),
              ],
            );
          }

          return Padding(
            padding: const EdgeInsets.all(13.0),
            child: Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(13.0),
                child: useWideLayout
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 1, child: logsDetailsPanel()),
                          const SizedBox(width: 13),
                          Expanded(
                            flex: 2,
                            child: AttendanceMultiMapView(logs: logs, schools: schools, employeeName: employeeName),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          logsDetailsPanel(),
                          const Divider(height: 13),
                          AttendanceMultiMapView(logs: logs, schools: schools, employeeName: employeeName),
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class AttendanceMultiMapView extends StatefulWidget {
  final List<Map<String, dynamic>> logs;
  final List<Map<String, dynamic>> schools;
  final String employeeName;
  final double height;
  const AttendanceMultiMapView({
    super.key,
    required this.logs,
    required this.schools,
    required this.employeeName,
    this.height = 280,
  });

  @override
  State<AttendanceMultiMapView> createState() => _AttendanceMultiMapViewState();
}

class _AttendanceMultiMapViewState extends State<AttendanceMultiMapView> {
  MapType _mapType = MapType.normal;
  int _mapRefreshKey = 0;
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Circle> _circles = {};
  final Set<Polyline> _polylines = {};
  LatLngBounds? _mapBounds;
  bool _isLoadingIcons = true;

  @override
  void initState() {
    super.initState();
    _initializeMapData();
  }

  Future<BitmapDescriptor> _createCustomMarkerBitmap({required String text, required Color badgeColor}) async {
    const int width = 60;
    const int height = 50;
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    final paint = Paint()
      ..color = badgeColor
      ..style = PaintingStyle.fill;

    final RRect rRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble() - 10),
      const Radius.circular(8),
    );
    canvas.drawRRect(rRect, paint);

    final path = Path();
    path.moveTo(width / 2 - 10, height - 10);
    path.lineTo(width / 2 + 10, height - 10);
    path.lineTo(width / 2, height.toDouble());
    path.close();
    canvas.drawPath(path, paint);

    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr, textAlign: TextAlign.center);
    textPainter.text = TextSpan(
      text: text,
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
    );
    textPainter.layout(minWidth: 0, maxWidth: width.toDouble());

    final offset = Offset((width - textPainter.width) / 2, ((height - 10) - textPainter.height) / 2);
    textPainter.paint(canvas, offset);

    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final Uint8List uint8list = byteData!.buffer.asUint8List();
    return BitmapDescriptor.bytes(uint8list);
  }

  Future<void> _initializeMapData() async {
    List<LatLng> tracePoints = [];
    final BitmapDescriptor checkInIcon = await _createCustomMarkerBitmap(text: "IN", badgeColor: Colors.blue);
    final BitmapDescriptor checkOutIcon = await _createCustomMarkerBitmap(text: "OUT", badgeColor: Colors.blue);

    for (var school in widget.schools) {
      final double? sLat = school['latitude'] != null ? double.tryParse(school['latitude'].toString()) : null;
      final double? sLng = school['longitude'] != null ? double.tryParse(school['longitude'].toString()) : null;
      final double radius = double.tryParse(school['radius'].toString()) ?? 50;
      if (sLat != null && sLng != null) {
        final schoolPoint = LatLng(sLat, sLng);
        _markers.add(
          Marker(
            markerId: MarkerId('school_${school['id']}'),
            position: schoolPoint,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
            infoWindow: InfoWindow(title: school['name'] ?? 'School', snippet: 'Radius: ${radius.toStringAsFixed(0)}m'),
          ),
        );
        _circles.add(
          Circle(
            circleId: CircleId('circle_${school['id']}'),
            center: schoolPoint,
            radius: radius,
            fillColor: AppTheme.primaryBlue.withValues(alpha: 0.13),
            strokeColor: AppTheme.primaryBlue.withValues(alpha: 0.5),
            strokeWidth: 2,
          ),
        );
      }
    }

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
            icon: isCheckIn ? checkInIcon : checkOutIcon,
            anchor: const Offset(0.5, 1.0),
          ),
        );
      }
    }

    if (tracePoints.length > 1) {
      _polylines.add(Polyline(polylineId: const PolylineId('route_trace'), points: tracePoints, color: Colors.black54, width: 3));
    }

    final pointsToBound = tracePoints.isNotEmpty ? tracePoints : _markers.map((m) => m.position).toList();
    if (pointsToBound.isNotEmpty) {
      double minLat = pointsToBound.first.latitude;
      double maxLat = pointsToBound.first.latitude;
      double minLng = pointsToBound.first.longitude;
      double maxLng = pointsToBound.first.longitude;

      for (var p in pointsToBound) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      _mapBounds = LatLngBounds(
        southwest: LatLng(minLat - 0.002, minLng - 0.002),
        northeast: LatLng(maxLat + 0.002, maxLng + 0.002),
      );
    }

    if (mounted) {
      setState(() {
        _isLoadingIcons = false;
      });
    }
  }

  Widget _buildMapTypeButton({required IconData icon, required String label, required MapType type, VoidCallback? onRefresh}) {
    final bool isSelected = _mapType == type;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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

  Widget _buildMapHeader({bool expanded = false, VoidCallback? onRefresh}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          decoration: BoxDecoration(color: Colors.grey.shade200),
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
          icon: Icon(expanded ? Icons.fullscreen_exit : Icons.fullscreen, color: AppTheme.primaryBlue),
          onPressed: expanded ? () => Navigator.of(context).pop() : _openExpandedView,
        ),
      ],
    );
  }

  Widget _buildBaseMapWidget() {
    if (_isLoadingIcons || _markers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return GoogleMap(
      key: ValueKey('multi_attendance_map_${_mapRefreshKey}_${_mapType.name}'),
      mapType: _mapType,
      initialCameraPosition: CameraPosition(target: _markers.first.position, zoom: 20),
      markers: _markers,
      circles: _circles,
      polylines: _polylines,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: true,
      gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
      onMapCreated: (controller) {
        _mapController = controller;
        if (_mapBounds != null) {
          _mapController?.animateCamera(CameraUpdate.newLatLngBounds(_mapBounds!, 60));
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
                padding: const EdgeInsets.all(3),
                child: Material(
                  elevation: 13,
                  child: Column(
                    children: [
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                        child: _buildMapHeader(
                          expanded: true,
                          onRefresh: () {
                            if (mounted) setState(() {});
                          },
                        ),
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
    setState(() {
      _mapRefreshKey++;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_markers.isEmpty && !_isLoadingIcons) return const SizedBox();
    return LayoutBuilder(
      builder: (context, constraints) {
        final Widget mapContainer = Container(
          width: double.infinity,
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
          clipBehavior: Clip.antiAlias,
          child: _buildBaseMapWidget(),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMapHeader(),
            const SizedBox(height: 8),
            if (constraints.maxHeight != double.infinity)
              Expanded(child: mapContainer)
            else
              SizedBox(height: widget.height, child: mapContainer),
          ],
        );
      },
    );
  }
}
