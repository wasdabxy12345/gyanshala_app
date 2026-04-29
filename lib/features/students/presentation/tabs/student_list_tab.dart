import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/features/students/controller/student_controller.dart';
import 'package:gyanshala_app/features/students/presentation/views/add_student_screen.dart';

class StudentListTab extends ConsumerStatefulWidget {
  final String searchQuery;
  const StudentListTab({super.key, required this.searchQuery});

  @override
  ConsumerState<StudentListTab> createState() => _StudentListTabState();
}

class _StudentListTabState extends ConsumerState<StudentListTab> {
  final Set<String> selectedGenders = {};
  final Set<int> selectedGrades = {};
  final Set<String> selectedSchools = {};
  final Set<String> selectedVillages = {};
  final Set<String> selectedClusters = {};

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
    if (selectedGenders.isNotEmpty &&
        !selectedGenders.contains(student['gender']?.toString()))
      return false;
    if (selectedGrades.isNotEmpty && !selectedGrades.contains(student['grade']))
      return false;
    if (selectedSchools.isNotEmpty &&
        !selectedSchools.contains(student['school_name']?.toString()))
      return false;
    if (selectedVillages.isNotEmpty &&
        !selectedVillages.contains(student['village_name']?.toString()))
      return false;
    if (selectedClusters.isNotEmpty &&
        !selectedClusters.contains(student['cluster_name']?.toString()))
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
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => _showMultiSelectDialog<String>(
                          context: context,
                          title: 'Gender',
                          options: genders,
                          selected: selectedGenders,
                        ),
                        child: Text(
                          selectedGenders.isEmpty
                              ? 'Gender: All'
                              : 'Gender: ${selectedGenders.length} selected',
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () => _showMultiSelectDialog<int>(
                          context: context,
                          title: 'Grade',
                          options: grades,
                          selected: selectedGrades,
                          labelBuilder: (g) => 'Grade $g',
                        ),
                        child: Text(
                          selectedGrades.isEmpty
                              ? 'Grade: All'
                              : 'Grade: ${selectedGrades.length} selected',
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () => _showMultiSelectDialog<String>(
                          context: context,
                          title: 'School',
                          options: schools,
                          selected: selectedSchools,
                        ),
                        child: Text(
                          selectedSchools.isEmpty
                              ? 'School: All'
                              : 'School: ${selectedSchools.length} selected',
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () => _showMultiSelectDialog<String>(
                          context: context,
                          title: 'Village',
                          options: villages,
                          selected: selectedVillages,
                        ),
                        child: Text(
                          selectedVillages.isEmpty
                              ? 'Village: All'
                              : 'Village: ${selectedVillages.length} selected',
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () => _showMultiSelectDialog<String>(
                          context: context,
                          title: 'Cluster',
                          options: clusters,
                          selected: selectedClusters,
                        ),
                        child: Text(
                          selectedClusters.isEmpty
                              ? 'Cluster: All'
                              : 'Cluster: ${selectedClusters.length} selected',
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (selectedGenders.isNotEmpty ||
                          selectedGrades.isNotEmpty ||
                          selectedSchools.isNotEmpty ||
                          selectedVillages.isNotEmpty ||
                          selectedClusters.isNotEmpty)
                        SizedBox(
                          width: 120,
                          child: ElevatedButton(
                            onPressed: () => setState(() {
                              selectedGenders.clear();
                              selectedGrades.clear();
                              selectedSchools.clear();
                              selectedVillages.clear();
                              selectedClusters.clear();
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
      floatingActionButton: FloatingActionButton(
        heroTag: 'add',
        onPressed: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AddStudentScreen()));
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showMultiSelectDialog<T>({
    required BuildContext context,
    required String title,
    required List<T> options,
    required Set<T> selected,
    String Function(T value)? labelBuilder,
  }) async {
    final temp = Set<T>.from(selected);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Select $title'),
          content: StatefulBuilder(
            builder: (context, setLocalState) {
              return SizedBox(
                width: 320,
                child: ListView(
                  shrinkWrap: true,
                  children: options.map((option) {
                    final isChecked = temp.contains(option);
                    final label =
                        labelBuilder?.call(option) ?? option.toString();
                    return CheckboxListTile(
                      value: isChecked,
                      title: Text(label),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (checked) {
                        setLocalState(() {
                          if (checked == true) {
                            temp.add(option);
                          } else {
                            temp.remove(option);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => selected.clear());
                Navigator.of(dialogContext).pop();
              },
              child: const Text('All'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  selected
                    ..clear()
                    ..addAll(temp);
                });
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
  }
}
