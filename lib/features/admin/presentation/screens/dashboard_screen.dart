import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  int _totalStudents = 0;
  int _totalStaff = 0;
  int _todayStudentAttendanceCount = 0;
  int _todayStaffAttendanceCount = 0;

  // Key: Cluster Name -> List of Villages with details
  List<Map<String, dynamic>> _hierarchySummary = [];

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  Future<void> _fetchDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now().toUtc();
      final startOfDay = DateTime.utc(now.year, now.month, now.day).toIso8601String();

      // 1. Fetch Total Students Count
      final studentsCountResponse = await _supabase.from('students').select('id');
      _totalStudents = (studentsCountResponse as List).length;

      // 2. Fetch Active Staff Count
      final staffCountResponse = await _supabase.from('profiles').select('id').eq('account_status', 'active');
      _totalStaff = (staffCountResponse as List).length;

      // 3. Fetch Today's Attendance Entries Count
      final studentAttendanceToday = await _supabase.from('student_attendance').select('id').gte('created_at', startOfDay);
      _todayStudentAttendanceCount = (studentAttendanceToday as List).length;

      final staffAttendanceToday = await _supabase.from('employee_attendance').select('id').gte('recorded_at', startOfDay);
      _todayStaffAttendanceCount = (staffAttendanceToday as List).length;

      // 4. Fetch Structured Breakdown (Clusters -> Villages -> Schools -> Counts)
      final clustersData = await _supabase.from('clusters').select('''
        id,
        name,
        villages (
          id,
          name,
          schools (
            id,
            name,
            grade_offering,
            students (id)
          )
        )
      ''');

      _hierarchySummary = List<Map<String, dynamic>>.from(clustersData);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading dashboard: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Overview Dashboard'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchDashboardData)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchDashboardData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Overview Metric Cards
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isDesktop = constraints.maxWidth > 700;
                        return GridView.count(
                          crossAxisCount: isDesktop ? 4 : 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          shrinkWrap: true,
                          childAspectRatio: isDesktop ? 1.8 : 1.3,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _buildMetricCard('Total Students', '$_totalStudents', Icons.school, Colors.blue),
                            _buildMetricCard('Total Staff', '$_totalStaff', Icons.badge, Colors.green),
                            _buildMetricCard(
                              "Student Entries Today",
                              '$_todayStudentAttendanceCount',
                              Icons.how_to_reg,
                              Colors.orange,
                            ),
                            _buildMetricCard(
                              "Staff Entries Today",
                              '$_todayStaffAttendanceCount',
                              Icons.access_time_filled,
                              Colors.purple,
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    // Section Title: Hierarchy Entry Breakdown
                    const Text(
                      'Cluster & Village Wise Entry Summary',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ketli entries che ane kai reet ni entry che (Cluster / Village / School breakdown):',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 12),

                    // Nested Hierarchy Expansion List
                    _buildHierarchyBreakdown(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHierarchyBreakdown() {
    if (_hierarchySummary.isEmpty) {
      return const Card(
        child: Padding(padding: EdgeInsets.all(16.0), child: Text('No cluster hierarchy data available.')),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _hierarchySummary.length,
      itemBuilder: (context, clusterIdx) {
        final cluster = _hierarchySummary[clusterIdx];
        final List villages = cluster['villages'] ?? [];

        int clusterStudentCount = 0;
        for (var v in villages) {
          final List schools = v['schools'] ?? [];
          for (var s in schools) {
            clusterStudentCount += ((s['students'] as List?) ?? []).length;
          }
        }

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ExpansionTile(
            leading: const Icon(Icons.hub, color: Colors.indigo),
            title: Text('Cluster: ${cluster['name'] ?? 'Unnamed'}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Villages: ${villages.length} | Students: $clusterStudentCount'),
            children: villages.map<Widget>((village) {
              final List schools = village['schools'] ?? [];

              return Padding(
                padding: const EdgeInsets.only(left: 16.0, right: 8.0, bottom: 8.0),
                child: ExpansionTile(
                  leading: const Icon(Icons.location_city, color: Colors.teal),
                  title: Text('Village: ${village['name']}'),
                  subtitle: Text('Schools: ${schools.length}'),
                  children: schools.map<Widget>((school) {
                    final studentList = (school['students'] as List?) ?? [];
                    final gradeOffering = school['grade_offering'] ?? 'N/A';

                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: 32, right: 16),
                      leading: const Icon(Icons.school_outlined, size: 20),
                      title: Text(school['name'] ?? 'School'),
                      subtitle: Text('Grades: $gradeOffering'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                        child: Text(
                          '${studentList.length} Students',
                          style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
