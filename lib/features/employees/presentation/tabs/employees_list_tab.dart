import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/models/user_role.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';

class EmployeeListTab extends ConsumerStatefulWidget {
  final String searchQuery;
  const EmployeeListTab({super.key, required this.searchQuery});

  @override
  ConsumerState<EmployeeListTab> createState() => _EmployeeListTabState();
}

class _EmployeeListTabState extends ConsumerState<EmployeeListTab> {
  final Set<String> _selectedEmployeeIds = {};
  final Set<String> selectedRoles = {};
  final Set<String> selectedClusters = {};
  final Set<String> selectedVillages = {};
  final Set<String> selectedSchools = {};

  bool _matchesSearch(Map<String, dynamic> shikshaMitra, String query) {
    if (query.isEmpty) return true;
    final lowerQuery = query.toLowerCase();

    final firstName = shikshaMitra['first_name']?.toString().toLowerCase() ?? '';
    final lastName = shikshaMitra['last_name']?.toString().toLowerCase() ?? '';
    final fullName = "$firstName $lastName";

    return fullName.contains(lowerQuery) ||
        (shikshaMitra['phone']?.toString().toLowerCase().contains(lowerQuery) ?? false) ||
        (shikshaMitra['role']?.toString().toLowerCase().contains(lowerQuery) ?? false) ||
        (shikshaMitra['cluster']?.toString().toLowerCase().contains(lowerQuery) ?? false) ||
        (shikshaMitra['village']?.toString().toLowerCase().contains(lowerQuery) ?? false) ||
        (shikshaMitra['school']?.toString().toLowerCase().contains(lowerQuery) ?? false);
  }

  bool _matchesFilters(Map<String, dynamic> shikshaMitra) {
    if (selectedRoles.isNotEmpty && !selectedRoles.contains(shikshaMitra['role']?.toString())) return false;
    if (selectedClusters.isNotEmpty && !selectedClusters.contains(shikshaMitra['cluster']?.toString())) return false;
    if (selectedVillages.isNotEmpty && !selectedVillages.contains(shikshaMitra['village']?.toString())) return false;
    if (selectedSchools.isNotEmpty && !selectedSchools.contains(shikshaMitra['school']?.toString())) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final supabase = ref.watch(supabaseClientProvider);

    return Scaffold(
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: supabase.from('profiles').stream(primaryKey: ['id']).inFilter('role', ['shikshaMitra', 'seniorMentor']),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final allEmployees = snapshot.data!;
          final filteredEmployees = allEmployees
              .where((m) => _matchesSearch(m, widget.searchQuery) && _matchesFilters(m))
              .toList();

          final roles = allEmployees.map((m) => m['role']?.toString()).whereType<String>().toSet().toList()..sort();
          final clusters = allEmployees.map((m) => m['cluster']?.toString()).whereType<String>().toSet().toList()..sort();
          final villages = allEmployees.map((m) => m['village']?.toString()).whereType<String>().toSet().toList()..sort();
          final schools = allEmployees.map((m) => m['school']?.toString()).whereType<String>().toSet().toList()..sort();

          return Column(
            children: [
              if (filteredEmployees.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      Text(
                        '${_selectedEmployeeIds.length} Selected',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() {
                          if (_selectedEmployeeIds.length == filteredEmployees.length) {
                            _selectedEmployeeIds.clear();
                          } else {
                            _selectedEmployeeIds.addAll(filteredEmployees.map((m) => m['id'].toString()));
                          }
                        }),
                        child: Text(_selectedEmployeeIds.length == filteredEmployees.length ? 'Deselect All' : 'Select All'),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          final currentFilteredIds = filteredEmployees.map((m) => m['id'].toString()).toSet();
                          final newSelection = currentFilteredIds.difference(_selectedEmployeeIds);
                          _selectedEmployeeIds.clear();
                          _selectedEmployeeIds.addAll(newSelection);
                        }),
                        child: const Text('Invert Selection'),
                      ),
                    ],
                  ),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      _filterButton('Role', roles, selectedRoles),
                      const SizedBox(width: 8),
                      _filterButton('Cluster', clusters, selectedClusters),
                      const SizedBox(width: 8),
                      _filterButton('Village', villages, selectedVillages),
                      const SizedBox(width: 8),
                      _filterButton('School', schools, selectedSchools),
                      if ([selectedRoles, selectedClusters, selectedVillages, selectedSchools].any((s) => s.isNotEmpty))
                        TextButton(
                          onPressed: () => setState(() {
                            selectedRoles.clear();
                            selectedClusters.clear();
                            selectedVillages.clear();
                            selectedSchools.clear();
                          }),
                          child: const Text('Clear'),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: filteredEmployees.isEmpty
                    ? const Center(child: Text('No employees found'))
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            onSelectAll: (isSelectedAll) {
                              setState(() {
                                if (isSelectedAll == true) {
                                  _selectedEmployeeIds.addAll(filteredEmployees.map((m) => m['id'].toString()));
                                } else {
                                  _selectedEmployeeIds.clear();
                                }
                              });
                            },
                            columns: const [
                              DataColumn(label: Text('First Name')),
                              DataColumn(label: Text('Last Name')),
                              DataColumn(label: Text('Phone')),
                              DataColumn(label: Text('Role')),
                              DataColumn(label: Text('Cluster')),
                              DataColumn(label: Text('Village')),
                              DataColumn(label: Text('School')),
                            ],
                            rows: filteredEmployees.map((e) {
                              final employeeId = e['id'].toString();
                              return DataRow(
                                selected: _selectedEmployeeIds.contains(employeeId),
                                onSelectChanged: (isSelected) {
                                  setState(() {
                                    if (isSelected == true) {
                                      _selectedEmployeeIds.add(employeeId);
                                    } else {
                                      _selectedEmployeeIds.remove(employeeId);
                                    }
                                  });
                                },
                                cells: [
                                  DataCell(Text(e['first_name'] ?? '-')),
                                  DataCell(Text(e['last_name'] ?? '-')),
                                  DataCell(Text(e['phone'] ?? '-')),
                                  DataCell(Text(UserRole.fromString(e['role']).label)),
                                  DataCell(Text(e['cluster'] ?? '-')),
                                  DataCell(Text(e['village'] ?? '-')),
                                  DataCell(Text(e['school'] ?? '-')),
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
    );
  }

  Widget _filterButton<T>(String title, List<T> options, Set<T> selected, {String Function(T)? labelBuilder}) {
    return OutlinedButton(
      onPressed: () => _showMultiSelectDialog<T>(
        context: context,
        title: title,
        options: options,
        selected: selected,
        labelBuilder: labelBuilder,
      ),
      child: Text(selected.isEmpty ? title : '$title (${selected.length})'),
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
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Select $title'),
        content: StatefulBuilder(
          builder: (context, setLocalState) => SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: options.map((option) {
                return CheckboxListTile(
                  title: Text(labelBuilder?.call(option) ?? option.toString()),
                  value: temp.contains(option),
                  onChanged: (val) => setLocalState(() => val == true ? temp.add(option) : temp.remove(option)),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                selected.clear();
                selected.addAll(temp);
              });
              Navigator.pop(ctx);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}
