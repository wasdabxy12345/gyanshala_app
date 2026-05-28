import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/features/employees/presentation/controller/employee_attendance_controller.dart';

class AttendanceCard extends ConsumerWidget {
  const AttendanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceState = ref.watch(employeeAttendanceProvider);
    final bool isCheckedIn = attendanceState.value ?? false;
    final bool isLoading = attendanceState.isLoading;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isLoading ? Colors.grey.shade300 : (isCheckedIn ? Colors.green : Colors.blue)),
      ),
      color: isLoading
          ? Colors.grey.shade50
          : (isCheckedIn ? Colors.green.withValues(alpha: 0.05) : Colors.blue.withValues(alpha: 0.05)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Icon(
                isCheckedIn ? Icons.location_on : Icons.location_off,
                size: 32,
                color: isLoading ? Colors.grey : (isCheckedIn ? Colors.green : Colors.blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLoading ? "Processing..." : (isCheckedIn ? "Status: Checked In" : "Status: Off Duty"),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      isCheckedIn ? "Location tracking active" : "Mark attendance to start",
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 80, maxWidth: 100),
                child: ElevatedButton(
                  onPressed: isLoading ? null : () => ref.read(employeeAttendanceProvider.notifier).processCheckIn(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isCheckedIn ? Colors.red : Colors.blue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(isCheckedIn ? "Out" : "In"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
