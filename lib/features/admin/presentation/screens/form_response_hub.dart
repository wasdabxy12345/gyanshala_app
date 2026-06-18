import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:gyanshala_app/features/admin/presentation/tabs/detailed_form_responses_tab.dart';
import 'package:gyanshala_app/features/admin/presentation/tabs/form_attendance_tab.dart';

class FormResponseHub extends ConsumerStatefulWidget {
  final String formId;
  final String formTitle;

  const FormResponseHub({super.key, required this.formId, required this.formTitle});

  @override
  ConsumerState<FormResponseHub> createState() => _FormResponseHubState();
}

class _FormResponseHubState extends ConsumerState<FormResponseHub> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final String _searchQuery = "";
  bool _isExporting = false;
  final _formAttendanceKey = GlobalKey<FormAttendanceTabState>();
  final _detailResponsesKey = GlobalKey<DetailedFormResponsesTabState>();
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

  Future<void> _triggerExport() async {
    if (_isExporting) return;

    setState(() => _isExporting = true);

    try {
      if (_tabController.index == 0) {
        await _formAttendanceKey.currentState?.exportExcel();
      } else if (_tabController.index == 1) {
        await _detailResponsesKey.currentState?.exportExcel();
      }
    } catch (e) {
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  void _triggerRefresh() {
    if (_isExporting) return;
    if (_tabController.index == 0) {
      _formAttendanceKey.currentState?.refresh();
    } else {
      _detailResponsesKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.formTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: CircleAvatar(
              foregroundColor: Colors.white,
              backgroundColor: _isExporting ? Colors.grey[400] : AppTheme.primaryBlue,
              child: _isExporting
                  ? const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                  : IconButton(tooltip: "Export Excel", icon: const Icon(Icons.download), onPressed: _triggerExport),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh), tooltip: "Refresh", onPressed: _isExporting ? null : _triggerRefresh),
          const SizedBox(width: 8),
        ],
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
              const Padding(padding: EdgeInsets.all(3)),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          FormAttendanceTab(
            key: _formAttendanceKey,
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
          DetailedFormResponsesTab(key: _detailResponsesKey, formId: widget.formId, formTitle: widget.formTitle),
        ],
      ),
    );
  }
}
