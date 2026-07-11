import 'package:flutter/material.dart' hide TextDirection;
import 'package:flutter/painting.dart' as painting;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StudentAttendanceRecordsTab extends StatefulWidget {
  final String searchQuery;

  const StudentAttendanceRecordsTab({super.key, required this.searchQuery});

  @override
  State<StudentAttendanceRecordsTab> createState() => _StudentAttendanceRecordsTabState();
}

class _StudentAttendanceRecordsTabState extends State<StudentAttendanceRecordsTab> {
  final SupabaseClient _client = Supabase.instance.client;

  // Date tracking parameters managed internally
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();

  List<DateTime> _holidays = [];
  bool _isInitialLoading = true;
  late Future<List<Map<String, dynamic>>> _attendanceFetchFuture;

  // Scroll controllers for bidirectional layout synchronization
  final ScrollController _horizontalHeaderController = ScrollController();
  final ScrollController _horizontalBodyController = ScrollController();
  final ScrollController _horizontalFooterController = ScrollController();

  @override
  void initState() {
    super.initState();
    _attendanceFetchFuture = _fetchRangeReport();
    _loadHolidays();

    // Cascading listeners linking all horizontally scrolled grid elements together
    _horizontalBodyController.addListener(() {
      if (_horizontalHeaderController.hasClients) {
        _horizontalHeaderController.jumpTo(_horizontalBodyController.offset);
      }
      if (_horizontalFooterController.hasClients) {
        _horizontalFooterController.jumpTo(_horizontalBodyController.offset);
      }
    });
  }

  @override
  void dispose() {
    _horizontalHeaderController.dispose();
    _horizontalBodyController.dispose();
    _horizontalFooterController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StudentAttendanceRecordsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      // Force UI updates if string filtering shifts
      setState(() {});
    }
  }

  Future<void> _loadHolidays() async {
    try {
      final List<dynamic> data = await _client.from('holidays').select('holiday_date');
      final list = data.map((row) {
        final parsed = DateTime.parse(row['holiday_date'] as String);
        return DateTime(parsed.year, parsed.month, parsed.day);
      }).toList();
      if (mounted) {
        setState(() {
          _holidays = list;
          _isInitialLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching holidays: $e");
      if (mounted) setState(() => _isInitialLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRangeReport() async {
    final response = await _client.rpc(
      'get_student_stats',
      params: {
        'p_start_date': _startDate.toIso8601String().split('T')[0],
        'p_end_date': _endDate.toIso8601String().split('T')[0],
      },
    );
    return List<Map<String, dynamic>>.from(response);
  }

  bool _isHoliday(DateTime date) {
    if (date.weekday == DateTime.sunday) return true;
    return _holidays.any((h) => h.year == date.year && h.month == date.month && h.day == date.day);
  }

  List<DateTime> _getDatesInRange(DateTime start, DateTime end) {
    return List.generate(end.difference(start).inDays + 1, (i) => start.add(Duration(days: i)));
  }

  Size calcTextSize(BuildContext context, String text, TextStyle style) {
    final TextPainter textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: painting.TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return textPainter.size;
  }

  Future<void> _selectSingleDate(BuildContext context, {required bool isStart}) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: isStart ? _endDate : DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
        _attendanceFetchFuture = _fetchRangeReport();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final now = DateTime.now();
    final todayNormalized = DateTime(now.year, now.month, now.day);
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 600;

    const double dateCellWidth = 50;
    const double totalColumnWidth = 60;
    final double rowHeight = isMobile ? 42 : 32;
    const double headerHeight = 42;

    return Column(
      children: [
        // Responsive Internal Range Selection Matrix
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              Widget buildDateSelectors() => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dateInkWell(context: context, date: _startDate, isStart: true),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text("to", style: TextStyle(fontWeight: FontWeight.w500)),
                  ),
                  _dateInkWell(context: context, date: _endDate, isStart: false),
                ],
              );

              Widget buildWeekControls() => Row(
                children: [
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _endDate = _startDate.subtract(const Duration(days: 1));
                        _startDate = _endDate.subtract(const Duration(days: 6));
                        _attendanceFetchFuture = _fetchRangeReport();
                      });
                    },
                    icon: const Icon(Icons.arrow_left, size: 32),
                  ),
                  Expanded(
                    child: _quickBtn("This Week", () {
                      setState(() {
                        _startDate = now.subtract(Duration(days: now.weekday - 1));
                        _endDate = _startDate.add(const Duration(days: 6));
                        _attendanceFetchFuture = _fetchRangeReport();
                      });
                    }),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _startDate = _endDate.add(const Duration(days: 1));
                        _endDate = _startDate.add(const Duration(days: 6));
                        _attendanceFetchFuture = _fetchRangeReport();
                      });
                    },
                    icon: const Icon(Icons.arrow_right, size: 32),
                  ),
                ],
              );

              Widget buildMonthControls() => Row(
                children: [
                  IconButton(
                    onPressed: () {
                      setState(() {
                        final prevEnd = DateTime(_startDate.year, _startDate.month, 0);
                        _startDate = DateTime(prevEnd.year, prevEnd.month, 1);
                        _endDate = prevEnd;
                        _attendanceFetchFuture = _fetchRangeReport();
                      });
                    },
                    icon: const Icon(Icons.arrow_left, size: 32),
                  ),
                  Expanded(
                    child: _quickBtn("This Month", () {
                      setState(() {
                        _startDate = DateTime(now.year, now.month, 1);
                        _endDate = DateTime(now.year, now.month + 1, 0);
                        _attendanceFetchFuture = _fetchRangeReport();
                      });
                    }),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _startDate = DateTime(_endDate.year, _endDate.month + 1, 1);
                        _endDate = DateTime(_startDate.year, _startDate.month + 1, 0);
                        _attendanceFetchFuture = _fetchRangeReport();
                      });
                    },
                    icon: const Icon(Icons.arrow_right, size: 32),
                  ),
                ],
              );

              if (constraints.maxWidth < 600) {
                return Column(
                  children: [
                    Center(child: buildDateSelectors()),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(child: buildWeekControls()),
                        const SizedBox(width: 8),
                        Expanded(child: buildMonthControls()),
                      ],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: buildWeekControls()),
                  buildDateSelectors(),
                  Expanded(child: buildMonthControls()),
                ],
              );
            },
          ),
        ),
        const Divider(height: 1),

        // Grid Sheet Segment
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _attendanceFetchFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text("Error fetching records: ${snapshot.error}"));
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text("No tracking datasets discoverable."));
              }

              // Dynamic Search Query parsing across loaded student arrays
              final students = snapshot.data!
                  .where((s) => s['full_name'].toString().toLowerCase().contains(widget.searchQuery.toLowerCase()))
                  .toList();

              if (students.isEmpty) {
                return const Center(child: Text("No records match your query."));
              }

              // Text Width Dimension Scanning
              double maxNameWidth = 0;
              const TextStyle nameStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black);
              for (final student in students) {
                final String fullName = student['full_name'] ?? 'Unknown';
                final parts = fullName.split(' ');
                final String textToMeasure = isMobile && parts.isNotEmpty ? parts[0] : fullName;
                final Size size = calcTextSize(context, textToMeasure, nameStyle);
                final double totalNeeded = size.width + 26.0;
                if (totalNeeded > maxNameWidth) maxNameWidth = totalNeeded;
              }
              if (maxNameWidth < 100) maxNameWidth = 100; // Minimum bound clamp

              final dates = _getDatesInRange(_startDate, _endDate);
              final workingDaysCount = dates.where((d) {
                final cellDateNormalized = DateTime(d.year, d.month, d.day);
                return !_isHoliday(d) && cellDateNormalized.isBefore(todayNormalized);
              }).length;

              // Compile summary aggregates across individual dates
              List<int> dailyTotals = [];
              double grandTotalPresent = 0;
              for (final d in dates) {
                final cellDateNormalized = DateTime(d.year, d.month, d.day);
                final bool isFutureOrToday =
                    cellDateNormalized.isAtSameMomentAs(todayNormalized) || cellDateNormalized.isAfter(todayNormalized);

                if (_isHoliday(d) || isFutureOrToday) {
                  dailyTotals.add(-1);
                } else {
                  int count = 0;
                  final key = DateFormat('yyyy-MM-dd').format(d);
                  for (final s in students) {
                    final attMap = s['attendance_map'] as Map<String, dynamic>? ?? {};
                    if (attMap[key] == 'present') {
                      count++;
                    }
                  }
                  dailyTotals.add(count);
                  grandTotalPresent += count;
                }
              }

              return Container(
                decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!)),
                child: Column(
                  children: [
                    // Synchronized Header Row
                    Container(
                      height: headerHeight,
                      color: Colors.grey[200],
                      child: Row(
                        children: [
                          Container(
                            width: maxNameWidth,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(left: 13),
                            decoration: BoxDecoration(
                              border: Border(right: BorderSide(color: Colors.grey[300]!)),
                            ),
                            child: const Text(
                              'Student Name',
                              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black),
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              controller: _horizontalHeaderController,
                              scrollDirection: Axis.horizontal,
                              physics: const NeverScrollableScrollPhysics(),
                              child: Row(
                                children: dates
                                    .map(
                                      (d) => Container(
                                        width: dateCellWidth,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          border: Border(right: BorderSide(color: Colors.grey[300]!)),
                                        ),
                                        child: Text(
                                          "${DateFormat('dd/MM').format(d)}\n${DateFormat('E').format(d)}",
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: _isHoliday(d) ? Colors.grey : Colors.black,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                          Container(
                            width: totalColumnWidth,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border(left: BorderSide(color: Colors.grey[300]!)),
                            ),
                            child: Text(
                              'Total:\n$workingDaysCount',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.black),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, thickness: 1, color: Colors.grey[300]),

                    // Multi-Scroll Synchronized Body Data List
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Column 1: Sticky Name Column
                            Container(
                              width: maxNameWidth,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                border: Border(right: BorderSide(color: Colors.grey[300]!)),
                              ),
                              child: Column(
                                children: students.map((s) {
                                  final fullName = s['full_name'] ?? 'Unknown';
                                  final parts = fullName.split(' ');
                                  return Container(
                                    height: rowHeight,
                                    padding: const EdgeInsets.symmetric(horizontal: 13),
                                    alignment: Alignment.centerLeft,
                                    decoration: BoxDecoration(
                                      border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        isMobile && parts.isNotEmpty ? "${parts[0]}\n${parts.sublist(1).join(' ')}" : fullName,
                                        maxLines: 2,
                                        style: nameStyle,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),

                            // Column 2: Scrollable Dynamic Matrix Cells
                            Expanded(
                              child: SingleChildScrollView(
                                controller: _horizontalBodyController,
                                scrollDirection: Axis.horizontal,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: students.map((student) {
                                    final attMap = student['attendance_map'] as Map<String, dynamic>? ?? {};
                                    return Container(
                                      height: rowHeight,
                                      decoration: BoxDecoration(
                                        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                                      ),
                                      child: Row(
                                        children: dates.map((d) {
                                          final key = DateFormat('yyyy-MM-dd').format(d);
                                          final status = attMap[key];
                                          final holiday = _isHoliday(d);
                                          final cellDateNormalized = DateTime(d.year, d.month, d.day);
                                          final bool isFutureOrToday =
                                              cellDateNormalized.isAtSameMomentAs(todayNormalized) ||
                                              cellDateNormalized.isAfter(todayNormalized);

                                          return Container(
                                            width: dateCellWidth,
                                            height: double.infinity,
                                            decoration: BoxDecoration(
                                              color: holiday ? Colors.grey[100] : null,
                                              border: Border(right: BorderSide(color: Colors.grey[200]!)),
                                            ),
                                            child: Center(
                                              child: holiday
                                                  ? const Icon(Icons.remove, color: Colors.grey, size: 13)
                                                  : status == 'present'
                                                  ? const Icon(Icons.check, color: Colors.green, size: 26)
                                                  : status == 'absent'
                                                  ? const Icon(Icons.close, color: Colors.red, size: 15)
                                                  : isFutureOrToday
                                                  ? const SizedBox.shrink()
                                                  : const Icon(Icons.close, color: Colors.red, size: 15),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),

                            // Column 3: Summary Totals
                            Container(
                              width: totalColumnWidth,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                border: Border(left: BorderSide(color: Colors.grey[300]!)),
                              ),
                              child: Column(
                                children: students.map((student) {
                                  final attMap = student['attendance_map'] as Map<String, dynamic>? ?? {};
                                  int presentCount = 0;
                                  for (final d in dates) {
                                    final cellDateNormalized = DateTime(d.year, d.month, d.day);
                                    if (!_isHoliday(d) && cellDateNormalized.isBefore(todayNormalized)) {
                                      final key = DateFormat('yyyy-MM-dd').format(d);
                                      if (attMap[key] == 'present') presentCount++;
                                    }
                                  }
                                  return Container(
                                    height: rowHeight,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                                    ),
                                    child: Text(
                                      "$presentCount\n(${workingDaysCount == 0 ? 0 : ((presentCount / workingDaysCount) * 100).toStringAsFixed(0)}%)",
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Colors.black),
                                      textAlign: TextAlign.center,
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Divider(height: 1, thickness: 1, color: Colors.grey[300]),

                    // Synchronized Footer Aggregates Summary Row
                    Container(
                      height: rowHeight,
                      color: Colors.blueGrey[50],
                      child: Row(
                        children: [
                          Container(
                            width: maxNameWidth,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(left: 13),
                            decoration: BoxDecoration(
                              border: Border(right: BorderSide(color: Colors.grey[300]!)),
                            ),
                            child: const Text(
                              "TOTAL",
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black),
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              controller: _horizontalFooterController,
                              scrollDirection: Axis.horizontal,
                              physics: const NeverScrollableScrollPhysics(),
                              child: Row(
                                children: dailyTotals
                                    .map(
                                      (count) => Container(
                                        width: dateCellWidth,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          border: Border(right: BorderSide(color: Colors.grey[200]!)),
                                        ),
                                        child: Text(
                                          count == -1 ? "-" : "$count",
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                          Container(
                            width: totalColumnWidth,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border(left: BorderSide(color: Colors.grey[300]!)),
                            ),
                            child: Text(
                              workingDaysCount == 0 || students.isEmpty
                                  ? "0.0\n(0%)"
                                  : "${(grandTotalPresent / workingDaysCount).toStringAsFixed(1)}\n(${((grandTotalPresent / (students.length * workingDaysCount)) * 100).toStringAsFixed(0)}%)",
                              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _quickBtn(String label, VoidCallback action) {
    return TextButton(
      style: TextButton.styleFrom(
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: action,
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _dateInkWell({required BuildContext context, required DateTime date, required bool isStart}) {
    return InkWell(
      onTap: () => _selectSingleDate(context, isStart: isStart),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.blue[800]!, width: 1),
          color: Colors.white,
        ),
        child: Text(
          '${DateFormat('dd-MM-yyyy').format(date)} (${DateFormat('EEE').format(date)})',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue[800]),
        ),
      ),
    );
  }
}
