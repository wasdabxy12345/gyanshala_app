import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:gyanshala_app/features/employees/presentation/screens/attendance_details_page.dart';
import 'package:intl/intl.dart';

class EmployeeAttendanceTable extends ConsumerStatefulWidget {
  final String searchQuery;
  final DateTime startDate;
  final DateTime endDate;

  const EmployeeAttendanceTable({super.key, required this.searchQuery, required this.startDate, required this.endDate});

  @override
  ConsumerState<EmployeeAttendanceTable> createState() => _EmployeeAttendanceTableState();
}

class _EmployeeAttendanceTableState extends ConsumerState<EmployeeAttendanceTable> {
  late Future<Map<String, dynamic>> _attendanceFetchFuture;
  int _buildCounter = 0; // Tracks layout rebuild cycles

  @override
  void initState() {
    super.initState();
    debugPrint("🔍 [PERF] initState called. Initializing data pipeline...");
    _attendanceFetchFuture = _loadDataPipeline();
  }

  @override
  void didUpdateWidget(covariant EmployeeAttendanceTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startDate != widget.startDate || oldWidget.endDate != widget.endDate) {
      debugPrint("🔍 [PERF] Configuration Dates changed! Re-running pipeline...");
      setState(() {
        _attendanceFetchFuture = _loadDataPipeline();
      });
    } else if (oldWidget.searchQuery != widget.searchQuery) {
      debugPrint("🔍 [PERF] Search query changed to: '${widget.searchQuery}'. (Triggers UI-only filtering, no network call)");
    }
  }

  /// Pipeline with precise performance tracking metrics
  Future<Map<String, dynamic>> _loadDataPipeline() async {
    final Stopwatch totalPipelineTimer = Stopwatch()..start();
    final Stopwatch networkTimer = Stopwatch()..start();

    debugPrint("🚀 [PERF] STARTING pipeline fetch for range: ${widget.startDate} to ${widget.endDate}");

    try {
      final supabase = ref.read(supabaseClientProvider);

      // 1. Trace Network Profiles Call
      debugPrint("🛰️ [PERF] Fetching employee profiles from Supabase...");
      final employeesRaw =
          ((await supabase.from('profiles').select('id, first_name, last_name').inFilter('role', [
                    'shikshaMitra',
                    'seniorMentor',
                  ]))
                  as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
      debugPrint("🛰️ [PERF] Profiles fetched. Found: ${employeesRaw.length} rows. Time: ${networkTimer.elapsedMilliseconds}ms");

      // 2. Trace Network Attendance Records Call
      networkTimer.reset();
      final utcRange = toUtcRange(DateTimeRange(start: widget.startDate, end: widget.endDate));
      debugPrint("🛰️ [PERF] Fetching attendance records from Supabase...");

      final attendanceRecordsRaw =
          (await supabase
                  .from('employee_attendance')
                  .select('id, user_id, status, recorded_at, school_id, schools(name)')
                  .gte('recorded_at', utcRange.start.toIso8601String())
                  .lte('recorded_at', utcRange.end.toIso8601String()))
              as List<dynamic>;

      debugPrint(
        "🛰️ [PERF] Attendance records fetched. Found: ${attendanceRecordsRaw.length} records. Time: ${networkTimer.elapsedMilliseconds}ms",
      );
      networkTimer.stop();

      // 3. Trace Isolate Processing Performance
      final Stopwatch isolateTimer = Stopwatch()..start();
      debugPrint("🧬 [PERF] Offloading raw maps to background Isolate via compute()...");

      final processedData = await compute(_processAttendanceData, {'employees': employeesRaw, 'records': attendanceRecordsRaw});

      debugPrint("🧬 [PERF] Isolate complete. Map processing execution time: ${isolateTimer.elapsedMilliseconds}ms");
      isolateTimer.stop();

      debugPrint("🏁 [PERF] PIPELINE COMPLETE. Total End-to-End Latency: ${totalPipelineTimer.elapsedMilliseconds}ms\n---");
      totalPipelineTimer.stop();

      return processedData;
    } catch (e, stackTrace) {
      debugPrint("❌ [PERF ERROR] Pipeline failed: $e\n$stackTrace");
      rethrow;
    }
  }

  static Map<String, dynamic> _processAttendanceData(Map<String, dynamic> rawPayload) {
    final List<Map<String, dynamic>> employees = List<Map<String, dynamic>>.from(rawPayload['employees']);
    final List<dynamic> attendanceRecords = rawPayload['records'];

    Map<String, Map<String, dynamic>> employeeData = {};
    for (final employee in employees) {
      employeeData[employee['id']] = {
        'user_id': employee['id'],
        'full_name': "${employee['first_name']} ${employee['last_name']}",
        'attendance_map': <String, dynamic>{},
      };
    }

    for (final record in attendanceRecords) {
      final userId = record['user_id'];
      final status = record['status'];
      final recordedAt = DateTime.parse(record['recorded_at']).toLocal();
      final dateKey = DateFormat('yyyy-MM-dd').format(recordedAt);
      final schoolData = record['schools'];
      final schoolName = schoolData != null ? schoolData['name'] : "Off-site";

      if (employeeData.containsKey(userId)) {
        final currentMap = employeeData[userId]!['attendance_map'] as Map<String, dynamic>;
        if (status == 'check_in' || !currentMap.containsKey(dateKey)) {
          currentMap[dateKey] = {'status': 'present', 'location': schoolName};
        }
      }
    }

    return {'employees': employeeData, 'records': attendanceRecords};
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

  DataRow _buildFooter(List<Map<String, dynamic>> filteredEmployees, List<DateTime> dates, int totalWorkingDays) {
    final Stopwatch footerTimer = Stopwatch()..start();
    double grandTotalPresent = 0;

    final row = DataRow(
      color: WidgetStateProperty.all(Colors.blueGrey[50]),
      cells: [
        const DataCell(Text("TOTAL", style: TextStyle(fontWeight: FontWeight.bold))),
        ...dates.map((d) {
          if (_isHoliday(d)) return const DataCell(Center(child: Text("-")));
          final key = DateFormat('yyyy-MM-dd').format(d);

          int count = 0;
          for (final m in filteredEmployees) {
            final attMap = m['attendance_map'] as Map<String, dynamic>? ?? {};
            final statusData = attMap[key];
            if (statusData != null && statusData['status'] == 'present') {
              count++;
            }
          }
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
              totalWorkingDays == 0 || filteredEmployees.isEmpty
                  ? "0.0 (0%)"
                  : "${(grandTotalPresent / totalWorkingDays).toStringAsFixed(1)} (${((grandTotalPresent / (filteredEmployees.length * totalWorkingDays)) * 100).toStringAsFixed(0)}%)",
              style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );

    debugPrint("📊 [PERF] Footer computation row cell generation took: ${footerTimer.elapsedMilliseconds}ms");
    footerTimer.stop();
    return row;
  }

  @override
  Widget build(BuildContext context) {
    _buildCounter++;
    final int currentBuildIndex = _buildCounter;
    final Stopwatch buildTimer = Stopwatch()..start();

    debugPrint("🎨 [PERF] Widget build() cycle #$currentBuildIndex invoked. Status: ${snapshotStatus()}");

    return FutureBuilder<Map<String, dynamic>>(
      future: _attendanceFetchFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          debugPrint("⏳ [PERF] FutureBuilder status: WAITING. Displaying Spinner framework.");
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          debugPrint("❌ [PERF] FutureBuilder status: ERROR (${snapshot.error})");
          return Center(child: Text("Error fetching records: ${snapshot.error}"));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          debugPrint("⚠️ [PERF] FutureBuilder status: EMPTY DATA");
          return const Center(child: Text("No attendance data found"));
        }

        final Stopwatch processingTimer = Stopwatch()..start();

        // Trace text matching queries performance loop
        final employees =
            ((snapshot.data!['employees'] as Map<String, dynamic>).values
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList())
                .where((m) => m['full_name'].toString().toLowerCase().contains(widget.searchQuery.toLowerCase()))
                .toList();

        if (employees.isEmpty) {
          processingTimer.stop();
          return const Center(child: Text("No employees found"));
        }

        final dates = _getDatesInRange(widget.startDate, widget.endDate);
        final workingDaysCount = dates.where((d) => !_isHoliday(d)).length;

        debugPrint("⚙️ [PERF] Filtering and data parsing on UI main thread took: ${processingTimer.elapsedMilliseconds}ms");
        processingTimer.stop();

        final Stopwatch layoutRenderTimer = Stopwatch()..start();
        debugPrint("🧱 [PERF] Generating heavy DataTable matrix (${employees.length} rows x ${dates.length} columns)...");

        final widgetTree = Column(
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
                      const DataColumn(label: Text('Employee')),
                      ...dates.map(
                        (d) => DataColumn(
                          label: SizedBox(
                            width: 37,
                            child: Center(
                              child: Text(
                                "${DateFormat('dd/MM').format(d)}\n${DateFormat('E').format(d)}",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: _isHoliday(d) ? Colors.grey : Colors.black),
                              ),
                            ),
                          ),
                        ),
                      ),
                      DataColumn(label: Text('Total: $workingDaysCount')),
                    ],
                    rows: [
                      ...employees.map((employee) {
                        final attMap = employee['attendance_map'] as Map<String, dynamic>? ?? {};
                        int presentCount = 0;
                        final String targetUserId = employee['user_id'] ?? '';

                        return DataRow(
                          cells: [
                            DataCell(_buildNameCell(employee['full_name'] ?? 'Unknown')),
                            ...dates.map((d) {
                              final key = DateFormat('yyyy-MM-dd').format(d);
                              final record = attMap[key];
                              final holiday = _isHoliday(d);
                              final isPresent = record != null && record['status'] == 'present';
                              final location = record != null ? record['location'].toString().toLowerCase() : "";

                              if (!holiday && isPresent) {
                                presentCount++;
                              }

                              return DataCell(
                                InkWell(
                                  onTap: isPresent && targetUserId.isNotEmpty
                                      ? () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => AttendanceDetailsPage(userId: targetUserId, dateString: key),
                                            ),
                                          );
                                        }
                                      : null,
                                  child: Container(
                                    width: 35,
                                    height: double.infinity,
                                    color: holiday ? Colors.grey[100] : (location == "off-site" ? Colors.amber[100] : null),
                                    alignment: Alignment.center,
                                    child: holiday
                                        ? const Text("-", style: TextStyle(color: Colors.grey))
                                        : Text(
                                            isPresent ? 'P' : '-',
                                            style: TextStyle(
                                              fontWeight: isPresent ? FontWeight.bold : FontWeight.normal,
                                              color: isPresent
                                                  ? (location == "off-site" ? Colors.orange[800] : Colors.green)
                                                  : Colors.red,
                                            ),
                                          ),
                                  ),
                                ),
                              );
                            }),
                            DataCell(
                              Center(
                                child: Text(
                                  "$presentCount (${workingDaysCount == 0 ? 0 : ((presentCount / workingDaysCount) * 100).toStringAsFixed(0)}%)",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                      _buildFooter(employees, dates, workingDaysCount),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );

        debugPrint(
          "🧱 [PERF] DataTable compilation tree completed. Engine rendering time: ${layoutRenderTimer.elapsedMilliseconds}ms",
        );
        layoutRenderTimer.stop();

        debugPrint("🏁 [PERF] TOTAL build cycle #$currentBuildIndex time: ${buildTimer.elapsedMilliseconds}ms\n---");
        buildTimer.stop();

        return widgetTree;
      },
    );
  }

  String snapshotStatus() => _attendanceFetchFuture.toString();

  static DateTimeRange toUtcRange(DateTimeRange range) {
    final start = DateTime(range.start.year, range.start.month, range.start.day).toUtc();
    final end = DateTime(range.end.year, range.end.month, range.end.day).add(const Duration(days: 1)).toUtc();
    return DateTimeRange(start: start, end: end);
  }
}
