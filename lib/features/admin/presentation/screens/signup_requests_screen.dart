import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';

class SignupRequestsScreen extends ConsumerStatefulWidget {
  const SignupRequestsScreen({super.key});

  @override
  ConsumerState<SignupRequestsScreen> createState() =>
      _SignupRequestsScreenState();
}

class _SignupRequestsScreenState extends ConsumerState<SignupRequestsScreen> {
  bool _isLoading = false;
  String _searchQuery = "";

  // Filter States
  final Set<String> selectedRoles = {};
  final Set<String> selectedVillages = {};
  final Set<String> selectedClusters = {};
  final Set<String> selectedSchools = {};

  bool _matchesSearch(Map<String, dynamic> req) {
    if (_searchQuery.isEmpty) return true;
    final query = _searchQuery.toLowerCase();
    final fullName = "${req['first_name']} ${req['last_name']}".toLowerCase();
    final phone = req['phone']?.toString().toLowerCase() ?? "";

    return fullName.contains(query) || phone.contains(query);
  }

  bool _matchesFilters(Map<String, dynamic> req) {
    if (selectedRoles.isNotEmpty && !selectedRoles.contains(req['role']))
      return false;
    if (selectedVillages.isNotEmpty &&
        !selectedVillages.contains(req['village']))
      return false;
    if (selectedClusters.isNotEmpty &&
        !selectedClusters.contains(req['cluster']))
      return false;
    if (selectedSchools.isNotEmpty && !selectedSchools.contains(req['school']))
      return false;
    return true;
  }

  Future<void> _updateStatus(String id, String name, String status) async {
    setState(() => _isLoading = true);
    try {
      final supabase = ref.read(supabaseClientProvider);
      await supabase
          .from('signup_requests')
          .update({'status': status})
          .eq('id', id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('User $name marked as $status')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("User Management"),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(
              110,
            ), // Space for Tabs + Search
            child: Column(
              children: [
                // 1. Search Bar
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: "Search by name or phone...",
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
                // 2. Tabs
                const TabBar(
                  tabs: [
                    Tab(text: "Pending"),
                    Tab(text: "Approved"),
                    Tab(text: "Rejected"),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _buildRequestList('pending'),
            _buildRequestList('approved'),
            _buildRequestList('rejected'),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestList(String statusFilter) {
    final supabase = ref.watch(supabaseClientProvider);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: supabase
          .from('signup_requests')
          .stream(primaryKey: ['id'])
          .eq('status', statusFilter),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());

        final allData = snapshot.data!;

        // Apply Search and Filter
        final filteredData = allData
            .where((req) => _matchesSearch(req) && _matchesFilters(req))
            .toList();

        // Extract unique values for filter buttons
        final roles =
            allData
                .map((e) => e['role']?.toString())
                .whereType<String>()
                .toSet()
                .toList()
              ..sort();
        final villages =
            allData
                .map((e) => e['village']?.toString())
                .whereType<String>()
                .toSet()
                .toList()
              ..sort();
        final clusters =
            allData
                .map((e) => e['cluster']?.toString())
                .whereType<String>()
                .toSet()
                .toList()
              ..sort();
        final schools =
            allData
                .map((e) => e['school']?.toString())
                .whereType<String>()
                .toSet()
                .toList()
              ..sort();

        return Column(
          children: [
            // 3. Horizontal Filter Bar
            _buildFilterBar(roles, villages, clusters, schools),

            Expanded(
              child: filteredData.isEmpty
                  ? const Center(
                      child: Text("No users found matching filters."),
                    )
                  : ListView.builder(
                      itemCount: filteredData.length,
                      padding: const EdgeInsets.all(8),
                      itemBuilder: (context, index) {
                        final req = filteredData[index];
                        return _buildUserCard(req, statusFilter);
                      },
                    ),
            ),
          ],
        );
      },
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
            TextButton(
              onPressed: () => setState(() {
                selectedRoles.clear();
                selectedVillages.clear();
                selectedClusters.clear();
                selectedSchools.clear();
              }),
              child: const Text("Clear"),
            ),
        ],
      ),
    );
  }

  Widget _filterChip(String title, List<String> options, Set<String> selected) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: OutlinedButton(
        onPressed: () => _showMultiSelectDialog(title, options, selected),
        style: OutlinedButton.styleFrom(
          backgroundColor: selected.isNotEmpty ? Colors.indigo.shade50 : null,
          visualDensity: VisualDensity.compact,
        ),
        child: Text(
          selected.isEmpty ? "$title: All" : "$title: ${selected.length}",
        ),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> req, String statusFilter) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: statusFilter == 'rejected'
              ? Colors.red.shade100
              : Colors.indigo.shade100,
          child: Text(req['first_name']?[0].toUpperCase() ?? '?'),
        ),
        title: Text("${req['first_name']} ${req['last_name']}"),
        subtitle: Text("Role: ${req['role']}"),
        children: [
          _bulletProofRow(Icons.phone, "Phone", req['phone']),
          _bulletProofRow(Icons.location_on, "Village", req['village']),
          _bulletProofRow(Icons.hub, "Cluster", req['cluster']),
          _bulletProofRow(Icons.school, "School", req['school']),
          _bulletProofRow(Icons.history_edu, "Qual.", req['qualification']),
          const SizedBox(height: 10),
          if (statusFilter == 'pending')
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading
                          ? null
                          : () => _updateStatus(
                              req['id'],
                              req['first_name'],
                              'rejected',
                            ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                      child: const Text("Reject"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : () => _updateStatus(
                              req['id'],
                              req['first_name'],
                              'approved',
                            ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text("Approve"),
                    ),
                  ),
                ],
              ),
            ),
          if (statusFilter != 'pending')
            TextButton(
              onPressed: () =>
                  _updateStatus(req['id'], req['first_name'], 'pending'),
              child: const Text("Reset to Pending"),
            ),
        ],
      ),
    );
  }

  Widget _bulletProofRow(IconData icon, String label, dynamic value) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(icon, size: 20, color: Colors.indigo),
      title: Text("$label: ${value?.toString() ?? 'N/A'}"),
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
        title: Text("Select $title"),
        content: SizedBox(
          width: double.maxFinite,
          child: StatefulBuilder(
            builder: (context, setLocalState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // --- Select All / Clear All Bar ---
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton.icon(
                        onPressed: () =>
                            setLocalState(() => temp.addAll(options)),
                        icon: const Icon(Icons.select_all, size: 18),
                        label: const Text("Select All"),
                      ),
                      TextButton.icon(
                        onPressed: () => setLocalState(() => temp.clear()),
                        icon: const Icon(Icons.clear_all, size: 18),
                        label: const Text("Clear All"),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                // --- Scrollable List ---
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: options
                        .map(
                          (opt) => CheckboxListTile(
                            title: Text(opt),
                            value: temp.contains(opt),
                            onChanged: (val) => setLocalState(() {
                              if (val == true) {
                                temp.add(opt);
                              } else {
                                temp.remove(opt);
                              }
                            }),
                          ),
                        )
                        .toList(),
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
              setState(() {
                selected.clear();
                selected.addAll(temp);
              });
              Navigator.pop(ctx);
            },
            child: const Text("Apply"),
          ),
        ],
      ),
    );
  }
}
