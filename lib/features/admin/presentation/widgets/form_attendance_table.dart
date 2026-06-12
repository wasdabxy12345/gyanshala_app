import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:intl/intl.dart';

class FormAttendanceTable extends ConsumerStatefulWidget {
  final String formId;
  final String formTitle;
  final String searchQuery;
  final DateTime startDate;
  final DateTime endDate;

  const FormAttendanceTable({
    super.key,
    required this.formId,
    required this.formTitle,
    required this.searchQuery,
    required this.startDate,
    required this.endDate,
  });

  @override
  ConsumerState<FormAttendanceTable> createState() => _FormAttendanceTableState();
}

class _FormAttendanceTableState extends ConsumerState<FormAttendanceTable> {
  Future<Map<String, dynamic>> _getFormAttendanceData() async {
    final supabase = ref.read(supabaseClientProvider);

    final employees =
        ((await supabase.from('profiles').select('id, first_name, last_name').inFilter('role', ['shikshaMitra', 'seniorMentor']))
                as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

    final formAttendanceRecords =
        ((await supabase
                    .from('form_responses')
                    .select('id, form_id, user_id, submitted_at')
                    .eq('form_id', widget.formId)
                    .gte('submitted_at', widget.startDate.toUtc().toIso8601String())
                    .lte('submitted_at', widget.endDate.toUtc().add(const Duration(days: 1)).toIso8601String()))
                as List<dynamic>)
            .map((f) => Map<String, dynamic>.from(f as Map))
            .toList();

    Map<String, Map<String, dynamic>> employeeData = {};

    for (final employee in employees) {
      employeeData[employee['id']] = {
        'user_id': employee['id'],
        'full_name': "${employee['first_name']} ${employee['last_name']}",
        'attendance_map': <String, dynamic>{},
      };
    }

    for (final record in formAttendanceRecords) {
      final userId = record['user_id'];
      if (record['submitted_at'] == null || !employeeData.containsKey(userId)) continue;

      final submittedAt = DateTime.parse(record['submitted_at']).toLocal();
      final dateKey = DateFormat('yyyy-MM-dd').format(submittedAt);

      final currentMap = employeeData[userId]!['attendance_map'] as Map<String, dynamic>;
      currentMap[dateKey] = {'status': 'filled'};
    }

    if (kDebugMode) {
      print("Fetched ${formAttendanceRecords.length} records for range: ${widget.startDate} to ${widget.endDate}");
    }
    return {'employees': employeeData, 'records': formAttendanceRecords};
  }

  bool _isHoliday(DateTime date) {
    return date.weekday == DateTime.sunday;
  }

  List<DateTime> _getDatesInRange(DateTime start, DateTime end) {
    return List.generate(end.difference(start).inDays + 1, (i) => start.add(Duration(days: i)));
  }

  Widget _buildNameCell(String fullName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [Text(fullName)],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _getFormAttendanceData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text("Error loading records: ${snapshot.error}"));
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text("No responses found for this form"));
        }

        final employees =
            ((snapshot.data!['employees'] as Map<String, dynamic>).values
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList())
                .where((m) => m['full_name'].toString().toLowerCase().contains(widget.searchQuery.toLowerCase()))
                .toList();

        if (employees.isEmpty) {
          return const Center(child: Text("No employees found"));
        }

        final dates = _getDatesInRange(widget.startDate, widget.endDate);

        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    border: TableBorder.all(color: Colors.grey),
                    headingRowHeight: 70,
                    columnSpacing: 13,
                    horizontalMargin: 10,
                    columns: [
                      const DataColumn(label: Text('Employee')),
                      ...dates.map(
                        (d) => DataColumn(
                          label: SizedBox(
                            width: 45,
                            child: Center(
                              child: Text(
                                "${DateFormat('MM/dd').format(d)}\n${DateFormat('E').format(d)}",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: _isHoliday(d) ? Colors.grey : Colors.black),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    rows: [
                      ...employees.map((employee) {
                        final attMap = (employee['attendance_map'] as dynamic ?? {}) is Map
                            ? Map<String, dynamic>.from(employee['attendance_map'] as Map)
                            : <String, dynamic>{};

                        return DataRow(
                          cells: [
                            DataCell(_buildNameCell(employee['full_name'] ?? 'Unknown')),
                            ...dates.map((d) {
                              return DataCell(
                                Container(
                                  width: 45,
                                  height: double.infinity,
                                  color: _isHoliday(d) ? Colors.grey.shade200 : null,
                                  alignment: Alignment.center,
                                  child: _isHoliday(d)
                                      ? const Text("-")
                                      : attMap[DateFormat('yyyy-MM-dd').format(d)] != null
                                      ? const Icon(Icons.check, color: Colors.green)
                                      : DateTime(
                                          d.year,
                                          d.month,
                                          d.day,
                                        ).isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day))
                                      ? const Icon(Icons.close, color: Colors.red)
                                      : const Icon(Icons.remove, color: Colors.amber),
                                ),
                              );
                            }),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
