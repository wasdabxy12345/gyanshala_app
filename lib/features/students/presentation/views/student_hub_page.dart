import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:gyanshala_app/features/students/presentation/tabs/student_attendance_tab.dart';
import 'package:gyanshala_app/features/students/presentation/tabs/student_list_tab.dart';

class StudentHubPage extends ConsumerStatefulWidget {
  const StudentHubPage({super.key});

  @override
  ConsumerState<StudentHubPage> createState() => _StudentHubPageState();
}

class _StudentHubPageState extends ConsumerState<StudentHubPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final String _searchQuery = "";
  bool _isExporting = false;

  DateTimeRange _selectedRange = DateTimeRange(
    start: DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1)),
    end: DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1)).add(const Duration(days: 6)),
  );

  final GlobalKey<StudentAttendanceTabState> _attendanceTabKey = GlobalKey<StudentAttendanceTabState>();
  final GlobalKey<StudentListTabState> _studentListKey = GlobalKey<StudentListTabState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _triggerExportPipeline() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    try {
      if (_tabController.index == 0) {
        await _attendanceTabKey.currentState?.exportCurrentTable();
      } else {
        await _studentListKey.currentState?.exportExcel();
      }
    } catch (e) {
      // Error handling can be caught implicitly within tab implementations
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _triggerRefreshPipeline() {
    if (_tabController.index == 0) {
      // Calls the inner method to re-fetch data for the attendance pipeline
      _attendanceTabKey.currentState?.refreshData();
    } else {
      // Calls the inner refresh or state update for the student list pipeline
      _studentListKey.currentState?.refreshData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Students Hub"),
        actions: [
          // Action 1: Universal Refresh Button
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh Data",
            onPressed: _isExporting ? null : _triggerRefreshPipeline,
          ),

          // Action 2: Export Button / Progress Indicator
          if (_isExporting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.0),
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(color: AppTheme.primaryBlue, strokeWidth: 2),
              ),
            )
          else
            IconButton(icon: const Icon(Icons.download), tooltip: "Export to Excel", onPressed: _triggerExportPipeline),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Column(
            children: [
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: "Student Attendance"),
                  Tab(text: "Student List"),
                ],
              ),
              const Padding(padding: EdgeInsets.all(3)),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          StudentAttendanceTab(
            key: _attendanceTabKey,
            range: _selectedRange,
            searchQuery: _searchQuery,
            onRangeChanged: (r) => setState(() => _selectedRange = r),
          ),
          StudentListTab(key: _studentListKey, searchQuery: _searchQuery),
        ],
      ),
    );
  }
}
