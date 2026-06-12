import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/features/admin/presentation/screens/form_attendance_tab.dart';

class FormResponseHub extends ConsumerStatefulWidget {
  final String formId;
  final String formTitle;

  const FormResponseHub({super.key, required this.formId, required this.formTitle});

  @override
  ConsumerState<FormResponseHub> createState() => _FormResponseHubState();
}

class _FormResponseHubState extends ConsumerState<FormResponseHub> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final String _searchQuery = ""; // Changed to final since it is currently fixed empty string state

  late DateTimeRange _selectedRange;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));

    _selectedRange = DateTimeRange(
      start: DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day),
      end: DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day).add(const Duration(days: 6)),
    );

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.formTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Column(
            children: [
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: "Form Response Attendance"),
                  Tab(text: "Detailed Form Responses"),
                ],
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          FormAttendanceTab(
            formId: widget.formId,
            formTitle: widget.formTitle,
            searchQuery: _searchQuery,
            range: _selectedRange,
            onRangeChanged: (newRange) {
              setState(() {
                _selectedRange = newRange;
              });
            },
          ),
          const Center(child: Text("Detailed Form Responses Content View Here")),
        ],
      ),
    );
  }
}
