import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:gyanshala_app/features/students/presentation/controller/student_controller.dart';

class AttendanceTab extends ConsumerStatefulWidget {
  const AttendanceTab({super.key});

  @override
  ConsumerState<AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends ConsumerState<AttendanceTab> {
  String _reportView = 'Daily';
  final Map<String, String> _dailyStatus = {};

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 1. Top Toggle for Daily/Weekly/Monthly
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'Daily',
                label: Text('Daily'),
                icon: Icon(Icons.edit_calendar),
              ),
              ButtonSegment(
                value: 'Weekly',
                label: Text('Weekly'),
                icon: Icon(Icons.view_week),
              ),
              ButtonSegment(
                value: 'Monthly',
                label: Text('Monthly'),
                icon: Icon(Icons.calendar_month),
              ),
            ],
            selected: {_reportView},
            onSelectionChanged: (val) =>
                setState(() => _reportView = val.first),
          ),
        ),

        const Divider(height: 1),

        // 2. Dynamic Content Area
        Expanded(
          child: _reportView == 'Daily'
              ? _buildDailyMarkingView()
              : Center(child: Text("$_reportView Report View coming soon...")),
        ),

        // 3. Save Button (Only shows on Daily view)
        if (_reportView == 'Daily')
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _submitDailyAttendance,
                icon: const Icon(Icons.cloud_upload),
                label: const Text("Save Today's Attendance"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade50,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDailyMarkingView() {
    return FutureBuilder(
      future: ref.read(studentProvider.notifier).getMyStudents(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final students = snapshot.data!;

        return ListView.separated(
          itemCount: students.length,
          separatorBuilder: (context, index) => const Divider(indent: 70),
          itemBuilder: (context, index) {
            final s = students[index];
            final id = s['id'];
            final isPresent = _dailyStatus[id] == 'present';

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: isPresent
                    ? Colors.green.shade100
                    : Colors.grey.shade200,
                child: Text(
                  s['full_name'][0],
                  style: TextStyle(
                    color: isPresent ? Colors.green : Colors.black54,
                  ),
                ),
              ),
              title: Text(
                s['full_name'],
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              // The Marking Way: A simple Switch or a custom Toggle
              trailing: ChoiceChip(
                label: Text(isPresent ? "PRESENT" : "ABSENT"),
                selected: isPresent,
                selectedColor: Colors.green.shade400,
                labelStyle: TextStyle(
                  color: isPresent ? Colors.white : Colors.black,
                ),
                onSelected: (selected) {
                  setState(() {
                    _dailyStatus[id] = selected ? 'present' : 'absent';
                  });
                },
              ),
            );
          },
        );
      },
    );
  }

  void _submitDailyAttendance() async {
    final mentorId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    final today = DateTime.now().toIso8601String().split('T')[0];

    final records = _dailyStatus.entries
        .map(
          (e) => {
            'student_id': e.key,
            'mentor_id': mentorId,
            'status': e.value,
            'date': today,
          },
        )
        .toList();

    if (records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No attendance marked yet!")),
      );
      return;
    }

    final success = await ref
        .read(studentProvider.notifier)
        .submitAttendance(records);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Attendance synced to cloud!")),
      );
    }
  }
}
