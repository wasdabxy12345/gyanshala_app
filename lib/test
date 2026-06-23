import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:intl/intl.dart';

class SignupRequestsScreen extends ConsumerStatefulWidget {
  const SignupRequestsScreen({super.key});
  @override
  ConsumerState<SignupRequestsScreen> createState() =>
      _SignupRequestsScreenState();
}

class _SignupRequestsScreenState extends ConsumerState<SignupRequestsScreen> {
  bool _isLoading = false;
  final _searchController = TextEditingController();
  int _sortColumnIndex = 7;
  bool _isAscending = false;

  // Filter Sets
  Set<String>? _selectedNameFilters;
  Set<String>? _selectedPhoneFilters;
  Set<String>? _selectedRoleFilters;
  Set<String>? _selectedClusterFilters;
  Set<String>? _selectedVillageFilters;
  Set<String>? _selectedSchoolFilters;
  Set<String>? _selectedQualificationFilters;
  late DateTimeRange _selectedDateRange;
  Set<String>? _selectedTimeFilters;

  List<Map<String, dynamic>> _rawRequests = [];
  List<Map<String, dynamic>> _filteredRequests = [];

  @override
  void initState() {
    super.initState();
    final startOfWeek = DateTime.now().subtract(
      Duration(days: DateTime.now().weekday - 1),
    );
    _selectedDateRange = DateTimeRange(
      start: startOfWeek,
      end: startOfWeek.add(const Duration(days: 6)),
    );
  }

  /// Reusable confirmation dialog that asks for a mandatory reason
  Future<String?> _showActionReasonDialog({
    required String name,
    required String actionTitle,
    required String explanationText,
    Color confirmButtonColor = Colors.red,
  }) async {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('$actionTitle Account'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(explanationText),
              const SizedBox(height: 16),
              TextFormField(
                controller: reasonController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Reason for $actionTitle',
                  hintText: 'Provide context or justification...',
                  border: const OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a reason for this action';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, reasonController.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmButtonColor,
              foregroundColor: Colors.white,
            ),
            child: Text('Confirm $actionTitle'),
          ),
        ],
      ),
    );
  }

  /// Core database updater handling both Signup Requests and Profile Tables
  Future<void> _handleAction({
    required String id,
    required String currentStatus,
    required String targetStatus,
    required bool isProfileTable,
    String? reason,
  }) async {
    setState(() => _isLoading = true);
    final supabase = ref.read(supabaseClientProvider);
    final currentAdminId = supabase.auth.currentUser?.id;

    try {
      if (isProfileTable) {
        // Updates active, suspended, or removed users on the profiles table
        await supabase
            .from('profiles')
            .update({
              'account_status': targetStatus,
              'action_reason': reason,
              'actioned_by': currentAdminId,
              'actioned_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', id);
      } else {
        // Updates incoming signup applications
        await supabase
            .from('signup_requests')
            .update({
              'status': targetStatus,
              'action_reason': reason,
              'actioned_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', id);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully updated status to $targetStatus')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildTable({
    required String statusFilter,
    required bool isProfileTable,
  }) {
    final supabase = ref.watch(supabaseClientProvider);

    // Select correct target table and status key depending on context
    final table = isProfileTable ? 'profiles' : 'signup_requests';
    final statusColumn = isProfileTable ? 'account_status' : 'status';

    return Column(
      children: [
        _buildDateControls(),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: supabase
                .from(table)
                .stream(primaryKey: ['id'])
                .eq(statusColumn, statusFilter),
            builder: (context, snapshot) {
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());

              _rawRequests = List<Map<String, dynamic>>.from(snapshot.data!);
              final query = _searchController.text.toLowerCase().trim();

              _filteredRequests = _rawRequests.where((req) {
                final fullName =
                    "${req['first_name'] ?? ''} ${req['last_name'] ?? ''}";
                final dateField = isProfileTable
                    ? req['updated_at']
                    : req['created_at'];

                final signupTime = dateField != null
                    ? DateFormat(
                        'hh:mm a',
                      ).format(DateTime.parse(dateField).toLocal())
                    : '';

                if (_selectedNameFilters != null &&
                    !_selectedNameFilters!.contains(fullName))
                  return false;
                if (_selectedPhoneFilters != null &&
                    !_selectedPhoneFilters!.contains(req['phone']?.toString()))
                  return false;
                if (_selectedRoleFilters != null &&
                    !_selectedRoleFilters!.contains(req['role']))
                  return false;
                if (_selectedClusterFilters != null &&
                    !_selectedClusterFilters!.contains(req['cluster']))
                  return false;
                if (_selectedVillageFilters != null &&
                    !_selectedVillageFilters!.contains(req['village']))
                  return false;
                if (_selectedSchoolFilters != null &&
                    !_selectedSchoolFilters!.contains(req['school']))
                  return false;
                if (_selectedQualificationFilters != null &&
                    !_selectedQualificationFilters!.contains(
                      req['qualification'],
                    ))
                  return false;

                final targetDate = dateField != null
                    ? DateTime.parse(dateField).toLocal()
                    : null;
                if (targetDate != null) {
                  if (targetDate.isBefore(_selectedDateRange.start) ||
                      targetDate.isAfter(_selectedDateRange.end)) {
                    return false;
                  }
                }
                if (_selectedTimeFilters != null &&
                    !_selectedTimeFilters!.contains(signupTime))
                  return false;

                return query.isEmpty ||
                    fullName.toLowerCase().contains(query) ||
                    (req['phone']?.toString().toLowerCase().contains(query) ??
                        false) ||
                    (req['qualification']?.toString().toLowerCase().contains(
                          query,
                        ) ??
                        false);
              }).toList();

              _applySorting();
              final defaultStart = DateTime.now().subtract(
                Duration(days: DateTime.now().weekday - 1),
              );
              final defaultEnd = defaultStart.add(const Duration(days: 6));

              return Column(
                children: [
                  Expanded(
                    child: _filteredRequests.isEmpty
                        ? const Center(
                            child: Text("No records match your filters"),
                          )
                        : SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Table(
                                defaultColumnWidth:
                                    const IntrinsicColumnWidth(),
                                border: TableBorder(
                                  verticalInside: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                  horizontalInside: BorderSide(
                                    color: Colors.grey.shade300,
                                    width: 1.0,
                                  ),
                                  bottom: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                  left: BorderSide(color: Colors.grey.shade300),
                                  right: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                children: [
                                  TableRow(
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                    ),
                                    children: [
                                      _SortableHeader(
                                        label: "Full Name",
                                        onSort: () => _onSort(0),
                                        onFilter: () =>
                                            _showFilterMenu(0, "Name"),
                                        isSorted: _sortColumnIndex == 0,
                                        isAscending: _isAscending,
                                        hasFilter: _selectedNameFilters != null,
                                      ),
                                      _SortableHeader(
                                        label: "Phone",
                                        onSort: () => _onSort(1),
                                        onFilter: () =>
                                            _showFilterMenu(1, "Phone"),
                                        isSorted: _sortColumnIndex == 1,
                                        isAscending: _isAscending,
                                        hasFilter:
                                            _selectedPhoneFilters != null,
                                      ),
                                      _SortableHeader(
                                        label: "Role",
                                        onSort: () => _onSort(2),
                                        onFilter: () =>
                                            _showFilterMenu(2, "Role"),
                                        isSorted: _sortColumnIndex == 2,
                                        isAscending: _isAscending,
                                        hasFilter: _selectedRoleFilters != null,
                                      ),
                                      _SortableHeader(
                                        label: "Cluster",
                                        onSort: () => _onSort(3),
                                        onFilter: () =>
                                            _showFilterMenu(3, "Cluster"),
                                        isSorted: _sortColumnIndex == 3,
                                        isAscending: _isAscending,
                                        hasFilter:
                                            _selectedClusterFilters != null,
                                      ),
                                      _SortableHeader(
                                        label: "Village",
                                        onSort: () => _onSort(4),
                                        onFilter: () =>
                                            _showFilterMenu(4, "Village"),
                                        isSorted: _sortColumnIndex == 4,
                                        isAscending: _isAscending,
                                        hasFilter:
                                            _selectedVillageFilters != null,
                                      ),
                                      _SortableHeader(
                                        label: "School",
                                        onSort: () => _onSort(5),
                                        onFilter: () =>
                                            _showFilterMenu(5, "School"),
                                        isSorted: _sortColumnIndex == 5,
                                        isAscending: _isAscending,
                                        hasFilter:
                                            _selectedSchoolFilters != null,
                                      ),
                                      _SortableHeader(
                                        label: "Qualification",
                                        onSort: () => _onSort(6),
                                        onFilter: () =>
                                            _showFilterMenu(6, "Qualification"),
                                        isSorted: _sortColumnIndex == 6,
                                        isAscending: _isAscending,
                                        hasFilter:
                                            _selectedQualificationFilters !=
                                            null,
                                      ),
                                      _SortableHeader(
                                        label: "Date",
                                        onSort: () => _onSort(7),
                                        onFilter: () => _pickStartDate(),
                                        isSorted: _sortColumnIndex == 7,
                                        isAscending: _isAscending,
                                        hasFilter:
                                            _selectedDateRange.start !=
                                                defaultStart ||
                                            _selectedDateRange.end !=
                                                defaultEnd,
                                      ),
                                      _SortableHeader(
                                        label: "Time",
                                        onSort: () => _onSort(8),
                                        onFilter: () =>
                                            _showFilterMenu(8, "Time"),
                                        isSorted: _sortColumnIndex == 8,
                                        isAscending: _isAscending,
                                        hasFilter: _selectedTimeFilters != null,
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: Text(
                                          "Actions",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  ..._filteredRequests.map((req) {
                                    final String currentName =
                                        "${req['first_name'] ?? ''} ${req['last_name'] ?? ''}";
                                    final dateField = isProfileTable
                                        ? req['updated_at']
                                        : req['created_at'];
                                    final parsedDate = DateTime.parse(
                                      dateField,
                                    ).toLocal();

                                    return TableRow(
                                      children: [
                                        _DataCell(
                                          text: currentName,
                                          isBold: true,
                                        ),
                                        _DataCell(
                                          text: req['phone']?.toString() ?? "-",
                                        ),
                                        _DataCell(
                                          text: req['role']?.toString() ?? "-",
                                        ),
                                        _DataCell(
                                          text:
                                              req['cluster']?.toString() ?? "-",
                                        ),
                                        _DataCell(
                                          text:
                                              req['village']?.toString() ?? "-",
                                        ),
                                        _DataCell(
                                          text:
                                              req['school']?.toString() ?? "-",
                                        ),
                                        _DataCell(
                                          text:
                                              req['qualification']
                                                  ?.toString() ??
                                              "-",
                                        ),
                                        _DataCell(
                                          text: DateFormat(
                                            'dd MMM yyyy',
                                          ).format(parsedDate),
                                        ),
                                        _DataCell(
                                          text: DateFormat(
                                            'hh:mm a',
                                          ).format(parsedDate),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          child: _buildActionButtons(
                                            statusFilter,
                                            req,
                                            currentName,
                                          ),
                                        ),
                                      ],
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Contextual action button rendering engine
  Widget _buildActionButtons(
    String statusFilter,
    Map<String, dynamic> req,
    String currentName,
  ) {
    if (statusFilter == 'pending') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 32,
            width: 75,
            child: ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () => _handleAction(
                      id: req['id'],
                      currentStatus: 'pending',
                      targetStatus: 'approved',
                      isProfileTable: false,
                    ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
              child: const Text(
                "Approve",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 32,
            width: 75,
            child: ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () async {
                      final reason = await _showActionReasonDialog(
                        name: currentName,
                        actionTitle: 'Reject',
                        explanationText:
                            'Are you sure you want to reject the signup request for $currentName?',
                      );
                      if (reason != null) {
                        _handleAction(
                          id: req['id'],
                          currentStatus: 'pending',
                          targetStatus: 'removed',
                          isProfileTable: false,
                          reason: reason,
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
              child: const Text(
                "Reject",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      );
    } else if (statusFilter == 'active') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 32,
            width: 80,
            child: ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () async {
                      final reason = await _showActionReasonDialog(
                        name: currentName,
                        actionTitle: 'Suspend',
                        explanationText:
                            'Provide a reason to temporarily suspend $currentName account access.',
                        confirmButtonColor: Colors.orange,
                      );
                      if (reason != null) {
                        _handleAction(
                          id: req['id'],
                          currentStatus: 'active',
                          targetStatus: 'suspended',
                          isProfileTable: true,
                          reason: reason,
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
              child: const Text(
                "Suspend",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 32,
            width: 75,
            child: ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () async {
                      final reason = await _showActionReasonDialog(
                        name: currentName,
                        actionTitle: 'Remove',
                        explanationText:
                            'Are you completely sure you want to permanently remove $currentName?',
                      );
                      if (reason != null) {
                        _handleAction(
                          id: req['id'],
                          currentStatus: 'active',
                          targetStatus: 'removed',
                          isProfileTable: true,
                          reason: reason,
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
              child: const Text(
                "Remove",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      );
    } else {
      // 'suspended' configuration layout
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 32,
            width: 90,
            child: ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () async {
                      final reason = await _showActionReasonDialog(
                        name: currentName,
                        actionTitle: 'Unsuspend',
                        explanationText:
                            'Provide a validation reason to reinstate $currentName to active status.',
                        confirmButtonColor: Colors.blue,
                      );
                      if (reason != null) {
                        _handleAction(
                          id: req['id'],
                          currentStatus: 'suspended',
                          targetStatus: 'active',
                          isProfileTable: true,
                          reason: reason,
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
              child: const Text(
                "Unsuspend",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 32,
            width: 75,
            child: ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () async {
                      final reason = await _showActionReasonDialog(
                        name: currentName,
                        actionTitle: 'Remove',
                        explanationText:
                            'Permanently remove $currentName? This action is irreversible.',
                      );
                      if (reason != null) {
                        _handleAction(
                          id: req['id'],
                          currentStatus: 'suspended',
                          targetStatus: 'removed',
                          isProfileTable: true,
                          reason: reason,
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
              child: const Text(
                "Remove",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Signup Request Management"),
          bottom: const TabBar(
            tabs: [
              Tab(text: "Pending Requests"),
              Tab(text: "Active Profiles"),
              Tab(text: "Suspended Profiles"),
            ],
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildTable(statusFilter: 'pending', isProfileTable: false),
            _buildTable(statusFilter: 'active', isProfileTable: true),
            _buildTable(statusFilter: 'suspended', isProfileTable: true),
          ],
        ),
      ),
    );
  }

  // Stub methods to keep code compiling cleanly
  Widget _buildDateControls() => const SizedBox.shrink();
  void _applySorting() {}
  void _onSort(int index) {}
  void _showFilterMenu(int index, String name) {}
  void _pickStartDate() {}
}
