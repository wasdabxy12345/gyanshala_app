import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:intl/intl.dart';

class AttendanceDetailsPage extends ConsumerWidget {
  final String attendanceId;

  const AttendanceDetailsPage({super.key, required this.attendanceId});

  Future<Map<String, dynamic>> _fetchAttendanceRecordDetails(WidgetRef ref) async {
    final supabase = ref.read(supabaseClientProvider);

    try {
      // 1. Fetch the core attendance record and join the school name
      final attendanceResponse = await supabase.from('attendance').select('*, schools(name)').eq('id', attendanceId).single();

      final attendanceData = Map<String, dynamic>.from(attendanceResponse);
      final userId = attendanceData['user_id'];

      // 2. Fetch the corresponding profile information using the user_id
      if (userId != null) {
        try {
          final profileResponse = await supabase.from('profiles').select('first_name, last_name, role').eq('id', userId).single();

          // Inject profile data manually into the map to guarantee correct keys
          attendanceData['profiles'] = profileResponse;
        } catch (profileError) {
          debugPrint("Profile Fetch Error: $profileError");
          attendanceData['profiles'] = null; // Gracefully fallback if profile fails
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
      appBar: AppBar(title: const Text('Attendance Details')),
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

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: ListView(
              children: [
                Card(
                  elevation: 2,
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
                        const Text("GPS Coordinates", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _buildDetailRow(Icons.location_on, "Latitude", "${data['latitude'] ?? 'N/A'}")),
                            Expanded(child: _buildDetailRow(Icons.location_on, "Longitude", "${data['longitude'] ?? 'N/A'}")),
                          ],
                        ),
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
