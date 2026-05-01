import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/features/students/controller/student_controller.dart';

class StudentListTab extends ConsumerStatefulWidget {
  final String searchQuery;
  const StudentListTab({super.key, required this.searchQuery});

  @override
  ConsumerState<StudentListTab> createState() => _StudentListTabState();
}

class _StudentListTabState extends ConsumerState<StudentListTab> {
  String? selectedGender;
  int? selectedGrade;
  String? selectedSchool;
  String? selectedVillage;
  String? selectedCluster;
  bool _showFilters = false;

  bool _matchesSearch(Map<String, dynamic> student, String query) {
    if (query.isEmpty) return true;
    final lowerQuery = query.toLowerCase();

    return (student['student_id_custom']?.toString().toLowerCase().contains(
              lowerQuery,
            ) ??
            false) ||
        (student['full_name']?.toString().toLowerCase().contains(lowerQuery) ??
            false) ||
        (student['gender']?.toString().toLowerCase().contains(lowerQuery) ??
            false) ||
        (student['grade']?.toString().toLowerCase().contains(lowerQuery) ??
            false) ||
        (student['school_name']?.toString().toLowerCase().contains(
              lowerQuery,
            ) ??
            false) ||
        (student['village_name']?.toString().toLowerCase().contains(
              lowerQuery,
            ) ??
            false) ||
        (student['cluster_name']?.toString().toLowerCase().contains(
              lowerQuery,
            ) ??
            false);
  }

  bool _matchesFilters(Map<String, dynamic> student) {
    if (selectedGender != null &&
        student['gender']?.toString() != selectedGender)
      return false;
    if (selectedGrade != null && student['grade'] != selectedGrade)
      return false;
    if (selectedSchool != null &&
        student['school_name']?.toString() != selectedSchool)
      return false;
    if (selectedVillage != null &&
        student['village_name']?.toString() != selectedVillage)
      return false;
    if (selectedCluster != null &&
        student['cluster_name']?.toString() != selectedCluster)
      return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: ref.read(studentProvider.notifier).getMyStudents(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          final allStudents = snapshot.data!;

          final filteredStudents = allStudents
              .where(
                (s) =>
                    _matchesSearch(s, widget.searchQuery) && _matchesFilters(s),
              )
              .toList();

          // Get unique filter values
          final genders =
              allStudents
                  .map((s) => s['gender']?.toString())
                  .whereType<String>()
                  .toSet()
                  .toList()
                ..sort();

          final grades =
              allStudents
                  .map((s) => s['grade'] as int?)
                  .whereType<int>()
                  .toSet()
                  .toList()
                ..sort();

          final schools =
              allStudents
                  .map((s) => s['school_name']?.toString())
                  .whereType<String>()
                  .toSet()
                  .toList()
                ..sort();

          final villages =
              allStudents
                  .map((s) => s['village_name']?.toString())
                  .whereType<String>()
                  .toSet()
                  .toList()
                ..sort();

          final clusters =
              allStudents
                  .map((s) => s['cluster_name']?.toString())
                  .whereType<String>()
                  .toSet()
                  .toList()
                ..sort();

          return Column(
            children: [
              if (_showFilters)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        DropdownButton<String>(
                          hint: const Text('Gender'),
                          value: selectedGender,
                          items: genders
                              .map(
                                (g) =>
                                    DropdownMenuItem(value: g, child: Text(g)),
                              )
                              .toList(),
                          onChanged: (val) =>
                              setState(() => selectedGender = val),
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<int>(
                          hint: const Text('Grade'),
                          value: selectedGrade,
                          items: grades
                              .map(
                                (g) => DropdownMenuItem(
                                  value: g,
                                  child: Text('Grade $g'),
                                ),
                              )
                              .toList(),
                          onChanged: (val) =>
                              setState(() => selectedGrade = val),
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                          hint: const Text('School'),
                          value: selectedSchool,
                          items: schools
                              .map(
                                (s) =>
                                    DropdownMenuItem(value: s, child: Text(s)),
                              )
                              .toList(),
                          onChanged: (val) =>
                              setState(() => selectedSchool = val),
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                          hint: const Text('Village'),
                          value: selectedVillage,
                          items: villages
                              .map(
                                (v) =>
                                    DropdownMenuItem(value: v, child: Text(v)),
                              )
                              .toList(),
                          onChanged: (val) =>
                              setState(() => selectedVillage = val),
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                          hint: const Text('Cluster'),
                          value: selectedCluster,
                          items: clusters
                              .map(
                                (c) =>
                                    DropdownMenuItem(value: c, child: Text(c)),
                              )
                              .toList(),
                          onChanged: (val) =>
                              setState(() => selectedCluster = val),
                        ),
                        const SizedBox(width: 12),
                        if (selectedGender != null ||
                            selectedGrade != null ||
                            selectedSchool != null ||
                            selectedVillage != null ||
                            selectedCluster != null)
                          SizedBox(
                            width: 120,
                            child: ElevatedButton(
                              onPressed: () => setState(() {
                                selectedGender = null;
                                selectedGrade = null;
                                selectedSchool = null;
                                selectedVillage = null;
                                selectedCluster = null;
                              }),
                              child: const Text('Clear Filters'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: filteredStudents.isEmpty
                    ? const Center(child: Text('No students found'))
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Student ID')),
                              DataColumn(label: Text('Name')),
                              DataColumn(label: Text('Gender')),
                              DataColumn(label: Text('Grade')),
                              DataColumn(label: Text('School')),
                              DataColumn(label: Text('Village')),
                              DataColumn(label: Text('Cluster')),
                            ],
                            rows: filteredStudents.map((s) {
                              return DataRow(
                                cells: [
                                  DataCell(
                                    Text(
                                      s['student_id_custom']?.toString() ?? '-',
                                    ),
                                  ),
                                  DataCell(
                                    Text(s['full_name']?.toString() ?? '-'),
                                  ),
                                  DataCell(
                                    Text(s['gender']?.toString() ?? '-'),
                                  ),
                                  DataCell(Text(s['grade']?.toString() ?? '-')),
                                  DataCell(
                                    Text(s['school_name']?.toString() ?? '-'),
                                  ),
                                  DataCell(
                                    Text(s['village_name']?.toString() ?? '-'),
                                  ),
                                  DataCell(
                                    Text(s['cluster_name']?.toString() ?? '-'),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'filter',
            onPressed: () => setState(() => _showFilters = !_showFilters),
            mini: true,
            child: const Icon(Icons.filter_list),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'add',
            onPressed: () {
              // Add your Navigation to AddStudentScreen here
            },
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
