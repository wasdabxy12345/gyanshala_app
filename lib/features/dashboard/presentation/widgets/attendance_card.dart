import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/features/attendance/presentation/controller/attendance_controller.dart';

class AttendanceCard extends ConsumerWidget {
  const AttendanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCheckedIn = ref.watch(attendanceProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isCheckedIn ? Colors.green.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isCheckedIn ? Colors.green : Colors.blue),
      ),
      child: Row(
        children: [
          Icon(
            isCheckedIn ? Icons.location_on : Icons.location_off,
            size: 40,
            color: isCheckedIn ? Colors.green : Colors.blue,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCheckedIn ? "Status: Checked In" : "Status: Not Working",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  isCheckedIn
                      ? "Location captured automatically"
                      : "Please check in to start your day",
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () =>
                ref.read(attendanceProvider.notifier).processCheckIn(),
            style: ElevatedButton.styleFrom(
              backgroundColor: isCheckedIn ? Colors.red : Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: Text(isCheckedIn ? "Check Out" : "Check In"),
          ),
        ],
      ),
    );
  }
}
