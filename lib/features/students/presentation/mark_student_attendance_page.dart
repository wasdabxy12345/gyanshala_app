import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MarkStudentAttendancePage extends StatefulWidget {
  const MarkStudentAttendancePage({super.key});

  @override
  State<MarkStudentAttendancePage> createState() => _MarkStudentAttendancePageState();
}

class _MarkStudentAttendancePageState extends State<MarkStudentAttendancePage> {
  final SupabaseClient _client = Supabase.instance.client;

  final DateTime _selectedDate = DateTime.now();
  String _searchQuery = "";
  int? _selectedGrade;
  bool _isLoading = false;

  Map<String, String> _statusMap = {};
  List<DateTime> _holidays = [];
  List<Map<String, dynamic>> _allStudents = [];
  bool _isFetchingStudents = true;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await _loadHolidays();
    await _fetchMyStudents();
    await _fetchAttendanceForSelectedDate();
  }

  Future<void> _loadHolidays() async {
    try {
      final List<dynamic> data = await _client.from('holidays').select('holiday_date');
      final list = data.map((row) {
        final parsed = DateTime.parse(row['holiday_date'] as String);
        return DateTime(parsed.year, parsed.month, parsed.day);
      }).toList();
      if (mounted) setState(() => _holidays = list);
    } catch (e) {
      debugPrint("Error loading holidays: $e");
    }
  }

  Future<void> _fetchMyStudents() async {
    try {
      if (!mounted) return;
      setState(() => _isFetchingStudents = true);

      final data = await _client
          .from('students')
          .select('id, student_id_local, grade')
          .order('student_id_local', ascending: true);

      if (mounted) {
        setState(() {
          _allStudents = List<Map<String, dynamic>>.from(data);

          final List<int> grades = _allStudents.where((s) => s['grade'] != null).map((s) => s['grade'] as int).toList();
          if (_selectedGrade != null && !grades.contains(_selectedGrade)) {
            _selectedGrade = null;
          }
          _isFetchingStudents = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching students via RLS boundary: $e");
      if (mounted) setState(() => _isFetchingStudents = false);
    }
  }

  Future<void> _fetchAttendanceForSelectedDate() async {
    try {
      final targetDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

      final data = await _client
          .from('student_attendance')
          .select('student_id, status')
          .gte('created_at', '${targetDateStr}T00:00:00.000+05:30')
          .lte('created_at', '${targetDateStr}T23:59:59.999+05:30');

      final Map<String, String> existing = {};
      for (var row in data) {
        final studentUuid = row['student_id']?.toString();
        final dbStatus = row['status'].toString();
        if (studentUuid == null) continue;

        if (dbStatus == 'present') {
          existing[studentUuid] = 'P';
        } else if (dbStatus == 'absent') {
          existing[studentUuid] = 'A';
        } else if (dbStatus == 'late') {
          existing[studentUuid] = 'L';
        }
      }

      if (mounted) {
        setState(() {
          _statusMap = existing;
        });
      }
    } catch (e) {
      debugPrint("Error fetching attendance: $e");
    }
  }

  bool _isHoliday(DateTime date) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    if (date.weekday == DateTime.sunday) return true;
    return _holidays.any((h) => h.year == normalizedDate.year && h.month == normalizedDate.month && h.day == normalizedDate.day);
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  Future<void> _saveAttendance() async {
    if (!_isToday(_selectedDate)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("You can only save attendance for today")));
      return;
    }
    if (_statusMap.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No attendance marked to save")));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final targetDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final shikshaMitraId = _client.auth.currentUser?.id;

      final List<String> studentIdsToUpdate = _statusMap.keys.toList();

      await _client
          .from('student_attendance')
          .delete()
          .inFilter('student_id', studentIdsToUpdate)
          .gte('created_at', '${targetDateStr}T00:00:00.000+05:30')
          .lte('created_at', '${targetDateStr}T23:59:59.999+05:30');

      final List<Map<String, dynamic>> records = _statusMap.entries.map((e) {
        String dbStatus = 'absent';
        if (e.value == 'P') dbStatus = 'present';
        if (e.value == 'L') dbStatus = 'late';

        return {'student_id': e.key, 'status': dbStatus, 'shiksha_mitra_id': shikshaMitraId};
      }).toList();

      await _client.from('student_attendance').insert(records);

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Attendance Saved Successfully!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      debugPrint("Attendance deletion/submission pipeline failed: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Failed to save attendance"), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool holidaySelected = _isHoliday(_selectedDate);
    final bool isCurrentDay = _isToday(_selectedDate);

    final List<int> gradeOptions = _allStudents.where((s) => s['grade'] != null).map((s) => s['grade'] as int).toSet().toList();
    gradeOptions.sort((a, b) => a.compareTo(b));

    final filteredStudents = _selectedGrade == null
        ? <Map<String, dynamic>>[]
        : _allStudents.where((s) {
            final localIdStr = s['student_id_local']?.toString().toLowerCase() ?? '';
            final matchesSearch = localIdStr.contains(_searchQuery.toLowerCase());
            return matchesSearch && s['grade'] == _selectedGrade;
          }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Mark Student Attendance"),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _initializeData)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: "Search by Local Student ID...",
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: _isFetchingStudents
                ? const Center(child: CircularProgressIndicator())
                : holidaySelected
                ? _buildHolidayPlaceholder()
                : _buildStudentListSection(gradeOptions, filteredStudents, isCurrentDay),
          ),
          if (!holidaySelected && isCurrentDay)
            Padding(
              padding: const EdgeInsets.all(13),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveAttendance,
                  child: _isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text("Save Attendance"),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHolidayPlaceholder() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy, size: 80, color: Colors.amber),
          SizedBox(height: 16),
          Text(
            "Holiday / Sunday",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          Text("Attendance cannot be marked for this date."),
        ],
      ),
    );
  }

  Widget _buildStudentListSection(List<int> gradeOptions, List<Map<String, dynamic>> filteredStudents, bool isEditable) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(13),
          child: DropdownButtonFormField<int>(
            initialValue: _selectedGrade,
            hint: const Text("Select grade", style: TextStyle(color: Colors.black45)),
            items: gradeOptions.map((grade) {
              return DropdownMenuItem<int>(value: grade, child: Text("Grade ${grade == 0 ? "BV" : "$grade"}"));
            }).toList(),
            onChanged: (newValue) {
              setState(() {
                _selectedGrade = newValue;
              });
            },
          ),
        ),
        Expanded(
          child: _selectedGrade == null
              ? const Center(child: Text("Select a grade to mark attendance"))
              : filteredStudents.isEmpty
              ? const Center(child: Text("No students found in this grade"))
              : ListView.builder(
                  itemCount: filteredStudents.length,
                  itemBuilder: (context, index) {
                    final s = filteredStudents[index];
                    final studentUuid = s['id'].toString();
                    final currentStatus = _statusMap[studentUuid];
                    final displayId = "Student ID: ${s['student_id_local'] ?? 'N/A'}";

                    return ListTile(
                      title: Text(displayId),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _statusBtn(studentUuid, 'P', Colors.green, currentStatus == 'P', isEditable),
                          const SizedBox(width: 5),
                          _statusBtn(studentUuid, 'L', Colors.blue, currentStatus == 'L', isEditable),
                          const SizedBox(width: 5),
                          _statusBtn(studentUuid, 'A', Colors.red, currentStatus == 'A', isEditable),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _statusBtn(String id, String label, Color color, bool isSelected, bool isEditable) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(color: isSelected ? Colors.white : Colors.black, fontWeight: FontWeight.bold),
      ),
      selected: isSelected,
      selectedColor: color,
      onSelected: isEditable
          ? (val) {
              setState(() {
                if (val) {
                  _statusMap[id] = label;
                } else {
                  _statusMap.remove(id);
                }
              });
            }
          : null,
    );
  }
}
