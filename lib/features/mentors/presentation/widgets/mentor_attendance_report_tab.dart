import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:intl/intl.dart';

class MentorAttendanceReportTab extends ConsumerStatefulWidget {
  final String searchQuery;
  final DateTime startDate;
  final DateTime endDate;

  const MentorAttendanceReportTab({super.key, required this.searchQuery, required this.startDate, required this.endDate});

  @override
  ConsumerState<MentorAttendanceReportTab> createState() => _MentorAttendanceReportTabState();
}

class _MentorAttendanceReportTabState extends ConsumerState<MentorAttendanceReportTab> {
  Future<Map<String, dynamic>> _getMentorAttendanceData() async {
    final supabase = ref.read(supabaseClientProvider);

    final mentorsResponse = await supabase.from('profiles').select('id, first_name, last_name').inFilter('role', [
      'mentor',
      'seniorMentor',
    ]);

    final mentors = (mentorsResponse as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    final attendanceResponse = await supabase
        .from('attendance')
        .select('user_id, status, recorded_at')
        .gte('recorded_at', widget.startDate.toUtc().toIso8601String())
        .lte('recorded_at', widget.endDate.toUtc().add(const Duration(days: 1)).toIso8601String());
    final attendanceRecords = (attendanceResponse as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    Map<String, Map<String, dynamic>> mentorData = {};

    for (final mentor in mentors) {
      mentorData[mentor['id']] = {
        'full_name': "${mentor['first_name']} ${mentor['last_name']}",
        'attendance_map': <String, dynamic>{},
      };
    }

    for (final record in attendanceRecords) {
      final userId = record['user_id'];
      final status = record['status'];
      final recordedAt = DateTime.parse(record['recorded_at']).toUtc();
      final dateKey = DateFormat('yyyy-MM-dd').format(recordedAt);

      if (mentorData.containsKey(userId)) {
        final currentMap = mentorData[userId]!['attendance_map'] as Map<String, dynamic>;
        if (status == 'check_in') {
          currentMap[dateKey] = 'present';
        } else if (currentMap[dateKey] != 'present') {
          currentMap[dateKey] = status;
        }
      }
    }
    if (kDebugMode) {
      print("Fetched ${attendanceRecords.length} records for range: ${widget.startDate} to ${widget.endDate}");
    }
    return {'mentors': mentorData, 'records': attendanceRecords};
  }

  bool _isHoliday(DateTime date) {
    return date.weekday == DateTime.sunday;
  }

  List<DateTime> _getDatesInRange(DateTime start, DateTime end) {
    return List.generate(end.difference(start).inDays + 1, (i) => start.add(Duration(days: i)));
  }

  Widget _buildNameCell(String fullName) {
    final parts = fullName.split(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(parts[0], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        if (parts.length > 1)
          Text(
            parts.sublist(1).join(' '),
            style: const TextStyle(fontSize: 10, color: Colors.grey),
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  DataRow _buildFooter(List<Map<String, dynamic>> mentors, List<DateTime> dates, int totalWorkingDays) {
    double grandTotalPresent = 0;

    return DataRow(
      color: WidgetStateProperty.all(Colors.blueGrey[50]),
      cells: [
        const DataCell(Text("TOTAL", style: TextStyle(fontWeight: FontWeight.bold))),
        ...dates.map((d) {
          if (_isHoliday(d)) return const DataCell(Center(child: Text("-")));

          final key = DateFormat('yyyy-MM-dd').format(d);
          int count = mentors.where((m) {
            final attMap = (m['attendance_map'] as dynamic ?? {}) is Map
                ? Map<String, dynamic>.from(m['attendance_map'] as Map)
                : <String, dynamic>{};
            final status = attMap[key];
            return status == 'check_in' || status == 'present';
          }).length;
          grandTotalPresent += count;
          return DataCell(
            Center(
              child: Text("$count", style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          );
        }),
        DataCell(
          Center(
            child: Text(
              totalWorkingDays == 0
                  ? "0.0\n0%"
                  : "${(grandTotalPresent / totalWorkingDays).toStringAsFixed(1)}\n"
                        "${((grandTotalPresent / (mentors.length * totalWorkingDays)) * 100).toStringAsFixed(0)}%",
              style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _getMentorAttendanceData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text("No attendance data found."));
        }

        final mentorDataMap = snapshot.data!['mentors'] as Map<String, dynamic>;
        final mentorsList = mentorDataMap.values.map((e) => Map<String, dynamic>.from(e as Map)).toList();

        final mentors = mentorsList
            .where((m) => m['full_name'].toString().toLowerCase().contains(widget.searchQuery.toLowerCase()))
            .toList();

        if (mentors.isEmpty) {
          return const Center(child: Text("No mentors matching search."));
        }

        final dates = _getDatesInRange(widget.startDate, widget.endDate);
        final workingDaysCount = dates.where((d) => !_isHoliday(d)).length;

        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    border: TableBorder.all(color: Colors.grey[300]!),
                    headingRowHeight: 70,
                    columnSpacing: 12,
                    horizontalMargin: 10,
                    columns: [
                      const DataColumn(label: Text('Mentor\nName')),
                      ...dates.map(
                        (d) => DataColumn(
                          label: SizedBox(
                            width: 35,
                            child: Center(
                              child: Text(
                                "${DateFormat('MM/dd').format(d)}\n${DateFormat('E').format(d)}",
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 11, color: _isHoliday(d) ? Colors.grey : Colors.black),
                              ),
                            ),
                          ),
                        ),
                      ),
                      DataColumn(label: Text('Total\n($workingDaysCount)')),
                    ],
                    rows: [
                      ...mentors.map((mentor) {
                        final attMap = (mentor['attendance_map'] as dynamic ?? {}) is Map
                            ? Map<String, dynamic>.from(mentor['attendance_map'] as Map)
                            : <String, dynamic>{};
                        int presentCount = 0;

                        return DataRow(
                          cells: [
                            DataCell(_buildNameCell(mentor['full_name'] ?? 'Unknown')),
                            ...dates.map((d) {
                              final key = DateFormat('yyyy-MM-dd').format(d.toUtc());
                              final status = attMap[key];
                              final holiday = _isHoliday(d);
                              final isPresent = status == 'present' || status == 'check_in';
                              if (!holiday && isPresent) {
                                presentCount++;
                              }

                              return DataCell(
                                Container(
                                  width: 35,
                                  color: holiday ? Colors.grey[100] : null,
                                  alignment: Alignment.center,
                                  child: holiday
                                      ? const Text("-", style: TextStyle(color: Colors.grey))
                                      : Text(
                                          isPresent ? 'P' : (status == 'absent' ? 'A' : '-'),
                                          style: TextStyle(
                                            color: isPresent ? Colors.green : Colors.red,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              );
                            }),
                            DataCell(
                              Center(
                                child: Text(
                                  "$presentCount\n${workingDaysCount == 0 ? 0 : ((presentCount / workingDaysCount) * 100).toStringAsFixed(0)}%",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                      _buildFooter(mentors, dates, workingDaysCount),
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
