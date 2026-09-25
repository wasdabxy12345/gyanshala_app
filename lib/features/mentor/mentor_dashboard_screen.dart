import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MentorDashboardScreen extends StatefulWidget {
  const MentorDashboardScreen({Key? key}) : super(key: key);
  @override
  State<MentorDashboardScreen> createState() => _MentorDashboardScreenState();
}

class _MentorDashboardScreenState extends State<MentorDashboardScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoadingSchools = true;
  bool _isLoadingMetrics = false;
  List<Map<String, dynamic>> _assignedSchools = [];
  String? _selectedSchoolId;
  late DateTimeRange _dateRange;
  Map<String, dynamic>? _shikshaMitraProfile;
  int _totalWorkingDays = 0;
  int _daysPresent = 0;
  double _attendancePercentage = 0.0;
  double? _attendanceChangePercentage;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final lastWeekStart = now.subtract(const Duration(days: 7));
    _dateRange = DateTimeRange(start: lastWeekStart, end: now);
    _fetchAssignedSchools();
  }

  Future<void> _fetchAssignedSchools() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final response = await _supabase
          .from('profile_schools')
          .select('schools(id, name, village_id, villages(id, cluster_id))')
          .eq('user_id', user.id);
      final List<Map<String, dynamic>> schools = [];
      for (var row in response as List) if (row['schools'] != null) schools.add(row['schools']);
      setState(() {
        _assignedSchools = schools;
        if (_assignedSchools.isNotEmpty) _selectedSchoolId = _assignedSchools.first['id'];
        _isLoadingSchools = false;
      });
      if (_selectedSchoolId != null) await _fetchShikshaMitraAndAttendance();
    } catch (e) {
      setState(() => _isLoadingSchools = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading schools: $e')));
    }
  }

  Future<void> _fetchShikshaMitraAndAttendance() async {
    if (_selectedSchoolId == null) return;
    setState(() => _isLoadingMetrics = true);
    try {
      final user = _supabase.auth.currentUser;
      // 1. Fetch Shiksha Mitra profile for the selected school
      final shikshaMitraRes = await _supabase
          .from('profile_schools')
          .select('profiles!inner(id, first_name, last_name, role)')
          .eq('school_id', _selectedSchoolId!)
          .filter('profiles.role', 'in', '("shikshaMitra38")')
          .maybeSingle();
      if (shikshaMitraRes == null || shikshaMitraRes['profiles'] == null) {
        setState(() {
          _shikshaMitraProfile = null;
          _totalWorkingDays = 0;
          _daysPresent = 0;
          _attendancePercentage = 0.0;
          _attendanceChangePercentage = null;
          _isLoadingMetrics = false;
        });
        return;
      }
      _shikshaMitraProfile = shikshaMitraRes['profiles'];
      final shikshaMitraId = _shikshaMitraProfile!['id'];
      final shikshaMitraRole = _shikshaMitraProfile!['role'];
      final schoolData = _assignedSchools.firstWhere((s) => s['id'] == _selectedSchoolId);
      final villageId = schoolData['village_id'];
      final clusterId = schoolData['villages']?['cluster_id'];
      // 2. Calculate standard working days & attendance for selected date range
      final workingDays = await _calculateWorkingDays(
        _dateRange.start,
        _dateRange.end,
        shikshaMitraRole,
        _selectedSchoolId!,
        villageId,
        clusterId,
      );
      final queryStartUtc = _dateRange.start.subtract(const Duration(days: 1)).toUtc().toIso8601String();
      final queryEndUtc = _dateRange.end.add(const Duration(days: 2)).toUtc().toIso8601String();
      final attendanceRes = await _supabase
          .from('employee_attendance')
          .select('recorded_at')
          .eq('user_id', shikshaMitraId)
          .gte('recorded_at', queryStartUtc)
          .lte('recorded_at', queryEndUtc);
      Set<String> presentDaysSet = {};
      final dateFormat = DateFormat('yyyy-MM-dd');
      final rangeStartDate = DateTime(_dateRange.start.year, _dateRange.start.month, _dateRange.start.day);
      final rangeEndDate = DateTime(_dateRange.end.year, _dateRange.end.month, _dateRange.end.day);
      for (var record in (attendanceRes as List))
        if (record['recorded_at'] != null) {
          DateTime utcTime = DateTime.parse(record['recorded_at']);
          DateTime istTime = utcTime.add(const Duration(hours: 5, minutes: 30));
          DateTime istDateOnly = DateTime(istTime.year, istTime.month, istTime.day);
          if (!istDateOnly.isBefore(rangeStartDate) && !istDateOnly.isAfter(rangeEndDate))
            presentDaysSet.add(dateFormat.format(istDateOnly));
        }
      // 3. Calculate attendance change percentage based on mentor's last 3 visits
      double? calculatedChange;
      if (user != null) {
        final mentorVisitsRes = await _supabase
            .from('employee_attendance')
            .select('recorded_at')
            .eq('user_id', user.id)
            .eq('school_id', _selectedSchoolId!)
            .order('recorded_at', ascending: false);

        // Convert attendance records into unique IST calendar dates.
        // A mentor can have check_in + check_out on the same day,
        // but that should count as ONE visit.
        final Set<String> uniqueVisitDates = {};

        for (final record in (mentorVisitsRes as List)) {
          if (record['recorded_at'] == null) continue;

          final utcTime = DateTime.parse(record['recorded_at']);
          final istTime = utcTime.add(const Duration(hours: 5, minutes: 30));

          final dateOnly = DateTime(istTime.year, istTime.month, istTime.day);

          uniqueVisitDates.add(DateFormat('yyyy-MM-dd').format(dateOnly));
        }

        // Convert the unique dates back to DateTime and sort newest first.
        final visits = uniqueVisitDates.map((date) => DateTime.parse(date)).toList()..sort((a, b) => b.compareTo(a));

        // Only now take the latest 3 unique visit days.
        final lastThreeVisits = visits.take(3).toList();

        if (lastThreeVisits.length >= 3) {
          final currentVisit = lastThreeVisits[0];
          final lastVisit = lastThreeVisits[1];
          final secondLastVisit = lastThreeVisits[2];
          // Period 1: between 2nd last visit and last visit
          final p1WorkingDays = await _calculateWorkingDays(
            secondLastVisit,
            lastVisit,
            shikshaMitraRole,
            _selectedSchoolId!,
            villageId,
            clusterId,
          );
          final p1StartUtc = secondLastVisit.subtract(const Duration(days: 1)).toUtc().toIso8601String();
          final p1EndUtc = lastVisit.add(const Duration(days: 2)).toUtc().toIso8601String();
          final p1AttendanceRes = await _supabase
              .from('employee_attendance')
              .select('recorded_at')
              .eq('user_id', shikshaMitraId)
              .gte('recorded_at', p1StartUtc)
              .lte('recorded_at', p1EndUtc);
          Set<String> p1PresentDays = {};
          final p1Start = DateTime(secondLastVisit.year, secondLastVisit.month, secondLastVisit.day);
          final p1End = DateTime(lastVisit.year, lastVisit.month, lastVisit.day);
          for (var record in (p1AttendanceRes as List))
            if (record['recorded_at'] != null) {
              DateTime utcTime = DateTime.parse(record['recorded_at']);
              DateTime istTime = utcTime.add(const Duration(hours: 5, minutes: 30));
              DateTime istDateOnly = DateTime(istTime.year, istTime.month, istTime.day);
              if (!istDateOnly.isBefore(p1Start) && !istDateOnly.isAfter(p1End))
                p1PresentDays.add(dateFormat.format(istDateOnly));
            }
          final rate1 = p1WorkingDays > 0 ? (p1PresentDays.length / p1WorkingDays) * 100 : 0.0;
          // Period 2: between last visit and current visit
          final p2WorkingDays = await _calculateWorkingDays(
            lastVisit,
            currentVisit,
            shikshaMitraRole,
            _selectedSchoolId!,
            villageId,
            clusterId,
          );
          final p2StartUtc = lastVisit.subtract(const Duration(days: 1)).toUtc().toIso8601String();
          final p2EndUtc = currentVisit.add(const Duration(days: 2)).toUtc().toIso8601String();
          final p2AttendanceRes = await _supabase
              .from('employee_attendance')
              .select('recorded_at')
              .eq('user_id', shikshaMitraId)
              .gte('recorded_at', p2StartUtc)
              .lte('recorded_at', p2EndUtc);
          Set<String> p2PresentDays = {};
          final p2Start = DateTime(lastVisit.year, lastVisit.month, lastVisit.day);
          final p2End = DateTime(currentVisit.year, currentVisit.month, currentVisit.day);
          for (var record in (p2AttendanceRes as List))
            if (record['recorded_at'] != null) {
              DateTime utcTime = DateTime.parse(record['recorded_at']);
              DateTime istTime = utcTime.add(const Duration(hours: 5, minutes: 30));
              DateTime istDateOnly = DateTime(istTime.year, istTime.month, istTime.day);
              if (!istDateOnly.isBefore(p2Start) && !istDateOnly.isAfter(p2End))
                p2PresentDays.add(dateFormat.format(istDateOnly));
            }
          final rate2 = p2WorkingDays > 0 ? (p2PresentDays.length / p2WorkingDays) * 100 : 0.0;
          print('rate1: ${rate1}; rate2: ${rate2}');
          calculatedChange = rate1 == 0
              ? rate2 == 0
                    ? 0.0
                    : 100.0
              : ((rate2 - rate1) / rate1) * 100;
        }
      }
      setState(() {
        _totalWorkingDays = workingDays;
        _daysPresent = presentDaysSet.length;
        _attendancePercentage = workingDays > 0 ? (_daysPresent / _totalWorkingDays) * 100 : 0.0;
        _attendanceChangePercentage = calculatedChange;
        _isLoadingMetrics = false;
      });
    } catch (e) {
      setState(() => _isLoadingMetrics = false);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error calculating attendance: $e')));
    }
  }

  Future<int> _calculateWorkingDays(
    DateTime start,
    DateTime end,
    String shikshaMitraRole,
    String schoolId,
    String? villageId,
    String? clusterId,
  ) async {
    final holidaysRes = await _supabase
        .from('special_dates')
        .select('id, start_date, end_date, roles, special_dates_locations(school_id, village_id, cluster_id)')
        .eq('type', 'holiday')
        .lte('start_date', DateFormat('yyyy-MM-dd').format(end))
        .gte('end_date', DateFormat('yyyy-MM-dd').format(start));
    List<DateTime> holidayDates = [];
    for (var holiday in (holidaysRes as List)) {
      final rolesList = holiday['roles'] as List?;
      if (rolesList != null && !rolesList.contains(shikshaMitraRole)) continue;
      final locations = holiday['special_dates_locations'] as List?;
      bool locationMatches = false;
      if (locations == null || locations.isEmpty)
        locationMatches = true;
      else
        for (var loc in locations)
          if (loc['school_id'] == schoolId || loc['village_id'] == villageId || loc['cluster_id'] == clusterId) {
            locationMatches = true;
            break;
          }
      if (locationMatches) {
        DateTime hStart = DateTime.parse(holiday['start_date']);
        DateTime hEnd = DateTime.parse(holiday['end_date']);
        for (var d = hStart; !d.isAfter(hEnd); d = d.add(const Duration(days: 1)))
          holidayDates.add(DateTime(d.year, d.month, d.day));
      }
    }
    int workingDays = 0;
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1)))
      if (d.weekday != DateTime.sunday) {
        DateTime normalizedDate = DateTime(d.year, d.month, d.day);
        if (!holidayDates.contains(normalizedDate)) workingDays++;
      }
    return workingDays;
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() {
        _dateRange = picked;
      });
      await _fetchShikshaMitraAndAttendance();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mentor Dashboard')),
      body: _isLoadingSchools
          ? const Center(child: CircularProgressIndicator())
          : _assignedSchools.isEmpty
          ? const Center(child: Text('No schools assigned to your mentor profile.'))
          : Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _selectedSchoolId,
                    decoration: const InputDecoration(
                      labelText: 'Select Assigned School',
                      border: OutlineInputBorder(),
                    ),
                    items: _assignedSchools.map((school) {
                      return DropdownMenuItem<String>(
                        value: school['id'] as String,
                        child: Text(school['name'] ?? 'Unknown School'),
                      );
                    }).toList(),
                    onChanged: (value) async {
                      setState(() => _selectedSchoolId = value);
                      await _fetchShikshaMitraAndAttendance();
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Range: ${DateFormat('MMM dd, yyyy').format(_dateRange.start)} - ${DateFormat('MMM dd, yyyy').format(_dateRange.end)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _selectDateRange(context),
                        icon: const Icon(Icons.date_range),
                        label: const Text('Change Range'),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  Expanded(
                    child: _isLoadingMetrics
                        ? const Center(child: CircularProgressIndicator())
                        : _shikshaMitraProfile == null
                        ? const Center(child: Text('No shiksha mitra found for this school'))
                        : ListView(
                            children: [
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Center(
                                        child: Text.rich(
                                          TextSpan(
                                            children: [
                                              const TextSpan(text: 'Shiksha Mitra: '),
                                              TextSpan(
                                                text:
                                                    '${_shikshaMitraProfile!['first_name'] ?? ''} ${_shikshaMitraProfile!['last_name'] ?? ''}',
                                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: _MetricCard(
                                      title: '% change: ',
                                      value: _attendanceChangePercentage == null
                                          ? '-'
                                          : '${(_attendanceChangePercentage! >= 0 ? '+' : '')}${_attendanceChangePercentage!.toStringAsFixed(0)}%',
                                      color: _attendanceChangePercentage == null
                                          ? Colors.black
                                          : _attendanceChangePercentage! >= 0
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _MetricCard(
                                      title: 'Attendance %: ',
                                      value: '${_attendancePercentage.toStringAsFixed(0)}%',
                                      color: _attendancePercentage >= 66.67
                                          ? Colors.green
                                          : _attendancePercentage >= 33.33
                                          ? Colors.amber
                                          : Colors.red,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _MetricCard(
                                      title: 'Days Present: ',
                                      value: '$_daysPresent / $_totalWorkingDays',
                                      color: Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  const _MetricCard({required this.title, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Center(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: title),
                TextSpan(
                  text: value,
                  style: TextStyle(color: color, fontSize: 22),
                ),
              ],
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}
