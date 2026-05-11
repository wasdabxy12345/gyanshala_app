import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/features/mentors/presentation/tabs/mentor_list_tab.dart';
import 'package:gyanshala_app/features/mentors/presentation/views/mentor_attendance_records_view.dart';

class MentorHubPage extends ConsumerStatefulWidget {
  const MentorHubPage({super.key});

  @override
  ConsumerState<MentorHubPage> createState() => _MentorHubPageState();
}

class _MentorHubPageState extends ConsumerState<MentorHubPage> {
  String _searchQuery = "";

  DateTimeRange _selectedRange = DateTimeRange(start: DateTime.now().subtract(const Duration(days: 7)), end: DateTime.now());

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Mentors"),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(110),
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.history), text: "Past Records"),
                    Tab(icon: Icon(Icons.people_outline), text: "Mentor List"),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: "Search mentors...",
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            MentorAttendanceRecordsView(
              range: _selectedRange,
              searchQuery: _searchQuery,
              onRangeChanged: (r) => setState(() => _selectedRange = r),
            ),
            MentorListTab(searchQuery: _searchQuery),
          ],
        ),
      ),
    );
  }
}
