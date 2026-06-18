import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:gyanshala_app/features/admin/presentation/tabs/employee_attendance_tab.dart';
import 'package:gyanshala_app/features/admin/presentation/tabs/employees_list_tab.dart';

class EmployeeHubPage extends ConsumerStatefulWidget {
  const EmployeeHubPage({super.key});
  @override
  ConsumerState<EmployeeHubPage> createState() => _EmployeeHubPageState();
}

class _EmployeeHubPageState extends ConsumerState<EmployeeHubPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final String _searchQuery = "";
  bool _isExporting = false;

  DateTimeRange _selectedRange = DateTimeRange(
    start: DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1)),
    end: DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1)).add(const Duration(days: 6)),
  );

  final GlobalKey<EmployeeAttendanceTabState> _attendanceTabKey = GlobalKey<EmployeeAttendanceTabState>();
  final GlobalKey<EmployeeListTabState> _employeeListKey = GlobalKey<EmployeeListTabState>();

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
        await _employeeListKey.currentState?.exportExcel();
      }
    } catch (e) {
      // Local recovery or metrics hooks if needed
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Employees"),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: CircleAvatar(
              foregroundColor: Colors.white,
              backgroundColor: _isExporting ? Colors.grey[400] : AppTheme.primaryBlue,
              child: _isExporting
                  ? const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                  : IconButton(icon: const Icon(Icons.download), onPressed: _triggerExportPipeline),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Column(
            children: [
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: "Employee Attendance"),
                  Tab(text: "Employee List"),
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
          EmployeeAttendanceTab(
            key: _attendanceTabKey,
            range: _selectedRange,
            searchQuery: _searchQuery,
            onRangeChanged: (r) => setState(() => _selectedRange = r),
          ),
          EmployeeListTab(key: _employeeListKey, searchQuery: _searchQuery),
        ],
      ),
    );
  }
}
