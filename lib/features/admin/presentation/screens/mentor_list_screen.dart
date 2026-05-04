import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/models/user_role.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';

class MentorListScreen extends ConsumerStatefulWidget {
  const MentorListScreen({super.key});

  @override
  ConsumerState<MentorListScreen> createState() => _MentorListScreenState();
}

class _MentorListScreenState extends ConsumerState<MentorListScreen> {
  String _searchQuery = "";

  final Set<String> selectedRoles = {};
  final Set<String> selectedVillages = {};
  final Set<String> selectedClusters = {};
  final Set<String> selectedSchools = {};

  bool _matchesSearch(Map<String, dynamic> mentor) {
    if (_searchQuery.isEmpty) return true;
    final query = _searchQuery.toLowerCase();
    final fullName = "${mentor['first_name']} ${mentor['last_name']}"
        .toLowerCase();
    final roleLabel = UserRole.fromString(mentor['role']).label.toLowerCase();

    return fullName.contains(query) ||
        mentor['phone'].toString().contains(query) ||
        roleLabel.contains(query);
  }

  bool _matchesFilters(Map<String, dynamic> mentor) {
    if (selectedRoles.isNotEmpty && !selectedRoles.contains(mentor['role']))
      return false;
    if (selectedVillages.isNotEmpty &&
        !selectedVillages.contains(mentor['village']))
      return false;
    if (selectedClusters.isNotEmpty &&
        !selectedClusters.contains(mentor['cluster']))
      return false;
    if (selectedSchools.isNotEmpty &&
        !selectedSchools.contains(mentor['school']))
      return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final supabase = ref.watch(supabaseClientProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Mentors Directory"),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: "Search mentors...",
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                fillColor: Colors.white,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: supabase.from('profiles').stream(primaryKey: ['id']).inFilter(
          'role',
          ['mentor', 'seniorMentor'],
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          final allMentors = snapshot.data!;
          final filteredMentors = allMentors
              .where((m) => _matchesSearch(m) && _matchesFilters(m))
              .toList();

          final roles =
              allMentors
                  .map((e) => e['role']?.toString())
                  .whereType<String>()
                  .toSet()
                  .toList()
                ..sort();
          final villages =
              allMentors
                  .map((e) => e['village']?.toString())
                  .whereType<String>()
                  .toSet()
                  .toList()
                ..sort();
          final clusters =
              allMentors
                  .map((e) => e['cluster']?.toString())
                  .whereType<String>()
                  .toSet()
                  .toList()
                ..sort();
          final schools =
              allMentors
                  .map((e) => e['school']?.toString())
                  .whereType<String>()
                  .toSet()
                  .toList()
                ..sort();

          return Column(
            children: [
              _buildFilterBar(roles, villages, clusters, schools),
              Expanded(
                child: filteredMentors.isEmpty
                    ? const Center(child: Text("No mentors found."))
                    : ListView.builder(
                        itemCount: filteredMentors.length,
                        padding: const EdgeInsets.all(8),
                        itemBuilder: (context, index) {
                          final mentor = filteredMentors[index];
                          return _buildMentorCard(mentor);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterBar(
    List<String> roles,
    List<String> villages,
    List<String> clusters,
    List<String> schools,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          _filterChip("Role", roles, selectedRoles),
          _filterChip("Village", villages, selectedVillages),
          _filterChip("Cluster", clusters, selectedClusters),
          _filterChip("School", schools, selectedSchools),
          if (selectedRoles.isNotEmpty ||
              selectedVillages.isNotEmpty ||
              selectedClusters.isNotEmpty ||
              selectedSchools.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.red),
              onPressed: () => setState(() {
                selectedRoles.clear();
                selectedVillages.clear();
                selectedClusters.clear();
                selectedSchools.clear();
              }),
            ),
        ],
      ),
    );
  }

  Widget _filterChip(String title, List<String> options, Set<String> selected) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(selected.isEmpty ? title : "$title (${selected.length})"),
        selected: selected.isNotEmpty,
        onSelected: (_) => _showMultiSelectDialog(title, options, selected),
      ),
    );
  }

  Widget _buildMentorCard(Map<String, dynamic> mentor) {
    final roleEnum = UserRole.fromString(mentor['role']);
    final isSenior = roleEnum == UserRole.seniorMentor;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: isSenior
              ? Colors.amber.shade100
              : Colors.indigo.shade100,
          child: Icon(
            isSenior ? Icons.stars : Icons.person,
            color: isSenior ? Colors.amber.shade900 : Colors.indigo,
          ),
        ),
        title: Text("${mentor['first_name']} ${mentor['last_name']}"),
        subtitle: Text(roleEnum.label.toUpperCase()),
        children: [],
      ),
    );
  }

  Future<void> _showMultiSelectDialog(
    String title,
    List<String> options,
    Set<String> selected,
  ) async {
    final temp = Set<String>.from(selected);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Filter by $title"),
        content: SizedBox(
          width: double.maxFinite,
          child: StatefulBuilder(
            builder: (context, setLocalState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () =>
                          setLocalState(() => temp.addAll(options)),
                      child: const Text("Select All"),
                    ),
                    TextButton(
                      onPressed: () => setLocalState(() => temp.clear()),
                      child: const Text("Clear All"),
                    ),
                  ],
                ),
                const Divider(),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: options.map((opt) {
                      String displayLabel = opt;
                      if (title == "Role") {
                        displayLabel = UserRole.fromString(opt).label;
                      }

                      return CheckboxListTile(
                        title: Text(displayLabel),
                        value: temp.contains(opt),
                        onChanged: (val) => setLocalState(
                          () => val == true ? temp.add(opt) : temp.remove(opt),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              setState(
                () => selected
                  ..clear()
                  ..addAll(temp),
              );
              Navigator.pop(ctx);
            },
            child: const Text("Apply"),
          ),
        ],
      ),
    );
  }
}
