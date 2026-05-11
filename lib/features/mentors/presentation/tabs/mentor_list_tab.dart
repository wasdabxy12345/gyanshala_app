import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/models/user_role.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';

class MentorListTab extends ConsumerStatefulWidget {
  final String searchQuery;
  const MentorListTab({super.key, required this.searchQuery});

  @override
  ConsumerState<MentorListTab> createState() => _MentorListTabState();
}

class _MentorListTabState extends ConsumerState<MentorListTab> {
  final Set<String> _selectedMentorIds = {};
  final Set<String> selectedRoles = {};
  final Set<String> selectedClusters = {};
  final Set<String> selectedVillages = {};
  final Set<String> selectedSchools = {};

  bool _matchesSearch(Map<String, dynamic> mentor, String query) {
    if (query.isEmpty) return true;
    final lowerQuery = query.toLowerCase();

    final firstName = mentor['first_name']?.toString().toLowerCase() ?? '';
    final lastName = mentor['last_name']?.toString().toLowerCase() ?? '';
    final fullName = "$firstName $lastName";

    return fullName.contains(lowerQuery) ||
        (mentor['phone']?.toString().toLowerCase().contains(lowerQuery) ?? false) ||
        (mentor['role']?.toString().toLowerCase().contains(lowerQuery) ?? false) ||
        (mentor['cluster']?.toString().toLowerCase().contains(lowerQuery) ?? false) ||
        (mentor['village']?.toString().toLowerCase().contains(lowerQuery) ?? false) ||
        (mentor['school']?.toString().toLowerCase().contains(lowerQuery) ?? false);
  }

  bool _matchesFilters(Map<String, dynamic> mentor) {
    if (selectedRoles.isNotEmpty && !selectedRoles.contains(mentor['role']?.toString())) return false;
    if (selectedClusters.isNotEmpty && !selectedClusters.contains(mentor['cluster']?.toString())) return false;
    if (selectedVillages.isNotEmpty && !selectedVillages.contains(mentor['village']?.toString())) return false;
    if (selectedSchools.isNotEmpty && !selectedSchools.contains(mentor['school']?.toString())) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final supabase = ref.watch(supabaseClientProvider);

    return Scaffold(
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: supabase.from('profiles').stream(primaryKey: ['id']).inFilter('role', ['mentor', 'seniorMentor']),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final allMentors = snapshot.data!;
          final filteredMentors = allMentors.where((m) => _matchesSearch(m, widget.searchQuery) && _matchesFilters(m)).toList();

          final roles = allMentors.map((m) => m['role']?.toString()).whereType<String>().toSet().toList()..sort();
          final clusters = allMentors.map((m) => m['cluster']?.toString()).whereType<String>().toSet().toList()..sort();
          final villages = allMentors.map((m) => m['village']?.toString()).whereType<String>().toSet().toList()..sort();
          final schools = allMentors.map((m) => m['school']?.toString()).whereType<String>().toSet().toList()..sort();

          return Column(
            children: [
              if (filteredMentors.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      Text(
                        '${_selectedMentorIds.length} Selected',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() {
                          if (_selectedMentorIds.length == filteredMentors.length) {
                            _selectedMentorIds.clear();
                          } else {
                            _selectedMentorIds.addAll(filteredMentors.map((m) => m['id'].toString()));
                          }
                        }),
                        child: Text(_selectedMentorIds.length == filteredMentors.length ? 'Deselect All' : 'Select All'),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          final currentFilteredIds = filteredMentors.map((m) => m['id'].toString()).toSet();
                          final newSelection = currentFilteredIds.difference(_selectedMentorIds);
                          _selectedMentorIds.clear();
                          _selectedMentorIds.addAll(newSelection);
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
                child: filteredMentors.isEmpty
                    ? const Center(child: Text('No mentors found'))
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            onSelectAll: (isSelectedAll) {
                              setState(() {
                                if (isSelectedAll == true) {
                                  _selectedMentorIds.addAll(filteredMentors.map((m) => m['id'].toString()));
                                } else {
                                  _selectedMentorIds.clear();
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
                            rows: filteredMentors.map((m) {
                              final mentorId = m['id'].toString();
                              return DataRow(
                                selected: _selectedMentorIds.contains(mentorId),
                                onSelectChanged: (isSelected) {
                                  setState(() {
                                    if (isSelected == true) {
                                      _selectedMentorIds.add(mentorId);
                                    } else {
                                      _selectedMentorIds.remove(mentorId);
                                    }
                                  });
                                },
                                cells: [
                                  DataCell(Text(m['first_name'] ?? '-')),
                                  DataCell(Text(m['last_name'] ?? '-')),
                                  DataCell(Text(m['phone'] ?? '-')),
                                  DataCell(Text(UserRole.fromString(m['role']).label)),
                                  DataCell(Text(m['cluster'] ?? '-')),
                                  DataCell(Text(m['village'] ?? '-')),
                                  DataCell(Text(m['school'] ?? '-')),
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
