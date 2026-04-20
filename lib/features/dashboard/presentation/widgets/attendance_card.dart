import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../attendance/presentation/controller/attendance_controller.dart';

class AttendanceCard extends ConsumerWidget {
  const AttendanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCheckedIn = ref.watch(attendanceProvider);

    return Card(
      // Using Card widget as it handles constraints better
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isCheckedIn ? Colors.green : Colors.blue),
      ),
      color: isCheckedIn
          ? Colors.green.withValues(alpha: 0.05)
          : Colors.blue.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: IntrinsicHeight(
          // Forces children to be only as tall as needed
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                isCheckedIn ? Icons.location_on : Icons.location_off,
                size: 32,
                color: isCheckedIn ? Colors.green : Colors.blue,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isCheckedIn ? "Status: Checked In" : "Status: Off Duty",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      isCheckedIn
                          ? "Location tracking active"
                          : "Mark attendance to start",
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Wrap button in a ConstrainedBox to prevent Infinite Width error
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 80, maxWidth: 100),
                child: ElevatedButton(
                  onPressed: () =>
                      ref.read(attendanceProvider.notifier).processCheckIn(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isCheckedIn ? Colors.red : Colors.blue,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets
                        .zero, // Remove internal padding to prevent expansion
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(isCheckedIn ? "Out" : "In"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
