import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/features/students/controller/student_controller.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DailyMarkingView extends ConsumerStatefulWidget {
  final DateTime date;
  final String searchQuery;
  final Function(DateTime) onDateChanged;

  const DailyMarkingView({
    super.key,
    required this.date,
    required this.searchQuery,
    required this.onDateChanged,
  });

  @override
  ConsumerState<DailyMarkingView> createState() => _DailyMarkingViewState();
}

class _DailyMarkingViewState extends ConsumerState<DailyMarkingView> {
  Map<String, String> statusMap = {};
  List<DateTime> _holidays = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadHolidays();
    _fetchTodayAttendance();
  }

  Future<void> _loadHolidays() async {
    try {
      final list = await ref.read(studentProvider.notifier).getHolidays();
      debugPrint('=== HOLIDAYS LOADED ===');
      debugPrint('Total: ${list.length}');
      for (var h in list) {
        debugPrint(
          '  - ${h.year}-${h.month.toString().padLeft(2, '0')}-${h.day.toString().padLeft(2, '0')} (${h.runtimeType})',
        );
      }
      if (mounted) setState(() => _holidays = list);
    } catch (e, stack) {
      debugPrint('ERROR loading holidays: $e\n$stack');
    }
  }

  bool _isHoliday(DateTime date) {
    // Strip time component for consistent comparison
    final normalizedDate = DateTime(date.year, date.month, date.day);

    // 1. Check if it's a Sunday (0 = Monday, 7 = Sunday)
    if (date.weekday == DateTime.sunday) return true;

    // 2. Check the holiday list
    final isHoliday = _holidays.any(
      (h) =>
          h.year == normalizedDate.year &&
          h.month == normalizedDate.month &&
          h.day == normalizedDate.day,
    );

    // Debug: Always log when checking April 18, 2026
    if (normalizedDate.year == 2026 &&
        normalizedDate.month == 4 &&
        normalizedDate.day == 18) {
      debugPrint('=== CHECKING APRIL 18, 2026 ===');
      debugPrint('Normalized: $normalizedDate');
      debugPrint('Holidays in list: ${_holidays.length}');
      for (var h in _holidays) {
        debugPrint(
          '  - $h (matches: ${h.year == 2026 && h.month == 4 && h.day == 18})',
        );
      }
      debugPrint('Is holiday: $isHoliday');
    }

    return isHoliday;
  }

  @override
  void didUpdateWidget(DailyMarkingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.date != widget.date) {
      _fetchTodayAttendance();
    }
  }

  Future<void> _fetchTodayAttendance() async {
    final client = Supabase.instance.client;
    final dateStr = DateFormat('yyyy-MM-dd').format(widget.date);

    final data = await client
        .from('student_attendance')
        .select('student_id, status')
        .eq('date', dateStr);

    final Map<String, String> existing = {};
    for (var row in data) {
      // Map database 'present'/'absent' to your UI 'P'/'A'
      existing[row['student_id']] = row['status'] == 'present' ? 'P' : 'A';
    }

    if (mounted) {
      setState(() {
        statusMap = existing;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool holidaySelected = _isHoliday(widget.date);

    return Column(
      children: [
        ListTile(
          tileColor: holidaySelected ? Colors.orange.shade50 : null,
          title: Text(
            "Date: ${DateFormat('dd MMM yyyy (EEEE)').format(widget.date)}", // Added EEEE for day name
            style: TextStyle(
              color: holidaySelected ? Colors.orange.shade900 : Colors.black,
              fontWeight: holidaySelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: holidaySelected
              ? const Text("School is closed today")
              : null,
          trailing: const Icon(Icons.calendar_today),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: widget.date,
              firstDate: DateTime(2024),
              lastDate: DateTime.now(),
              selectableDayPredicate: (DateTime val) => !_isHoliday(val),
            );
            if (d != null) widget.onDateChanged(d);
          },
        ),

        const Divider(height: 0),

        // --- THE CHANGE IS HERE ---
        Expanded(
          child: holidaySelected
              ? _buildHolidayPlaceholder() // Show this if it's a holiday
              : _buildStudentList(), // Show the list if it's a working day
        ),

        // Only show the Save Button if it's NOT a holiday
        if (!holidaySelected)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveAttendance,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text("SAVE ATTENDANCE"),
              ),
            ),
          ),
      ],
    );
  }

  // Helper widget for the Holiday view
  Widget _buildHolidayPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy, size: 80, color: Colors.orange.shade200),
          const SizedBox(height: 16),
          const Text(
            "Holiday / Sunday",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const Text("Attendance cannot be marked for this date."),
        ],
      ),
    );
  }

  Widget _buildStudentList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ref.read(studentProvider.notifier).getMyStudents(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final students = snapshot.data!
            .where(
              (s) => s['full_name'].toString().toLowerCase().contains(
                widget.searchQuery.toLowerCase(),
              ),
            )
            .toList();

        if (students.isEmpty) {
          return const Center(child: Text("No students found."));
        }

        return ListView.builder(
          itemCount: students.length,
          itemBuilder: (context, index) {
            final s = students[index];
            final currentStatus = statusMap[s['id']];
            return ListTile(
              title: Text(s['full_name']),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _statusBtn(s['id'], 'P', Colors.green, currentStatus == 'P'),
                  const SizedBox(width: 8),
                  _statusBtn(s['id'], 'A', Colors.red, currentStatus == 'A'),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- MISSING METHODS ADDED BELOW ---

  Widget _statusBtn(String id, String label, Color color, bool isSelected) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(color: isSelected ? Colors.white : Colors.black),
      ),
      selected: isSelected,
      selectedColor: color,
      onSelected: (val) {
        setState(() {
          statusMap[id] = val ? label : '';
        });
      },
    );
  }

  Future<void> _saveAttendance() async {
    if (statusMap.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No attendance marked to save")),
      );
      return;
    }

    setState(() => _isLoading = true);

    final dateStr = DateFormat('yyyy-MM-dd').format(widget.date);
    final mentorId = Supabase.instance.client.auth.currentUser?.id;

    final List<Map<String, dynamic>> records = statusMap.entries.map((e) {
      return {
        'student_id': e.key,
        'date': dateStr,
        'status': e.value == 'P' ? 'present' : 'absent',
        'mentor_id': mentorId,
      };
    }).toList();

    final success = await ref
        .read(studentProvider.notifier)
        .submitAttendance(records);

    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? "Attendance Saved Successfully!"
                : "Failed to save attendance",
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }
}
