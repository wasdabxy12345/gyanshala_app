import 'dart:convert';

import 'package:flutter/material.dart';

class ConflictWorkspaceDialog extends StatefulWidget {
  final String conflictRawString;
  const ConflictWorkspaceDialog({super.key, required this.conflictRawString});
  @override
  State<ConflictWorkspaceDialog> createState() => _ConflictWorkspaceDialogState();
}

class _ConflictWorkspaceDialogState extends State<ConflictWorkspaceDialog> {
  late List<Map<String, dynamic>> activeConflicts;
  late List<Map<String, dynamic>> filteredConflicts;
  final searchController = TextEditingController();
  String? sortField;
  bool sortAscending = true;
  final Set<String> selectedRowIds = {};
  final Set<int> selectedIndexes = {};
  final Map<String, Set<String>> activeFilters = {};
  final Map<String, Set<String>> columnValues = {};
  int? lowestSelectedIndex;
  int? highestSelectedIndex;
  Map<String, Map<String, bool>> fieldSelections = {};
  final fields = const ['student_id_custom', 'first_name', 'last_name', 'gender', 'grade', 'school', 'village', 'cluster'];
  @override
  void initState() {
    super.initState();
    final parts = widget.conflictRawString.split("|");
    final List<dynamic> rawData = jsonDecode(parts.sublist(2).join("|"));
    activeConflicts = List<Map<String, dynamic>>.from(rawData);
    filteredConflicts = List.from(activeConflicts);
    for (final f in fields) {
      columnValues[f] = activeConflicts.map((e) => e['current'][f]?.toString() ?? '').where((v) => v.isNotEmpty).toSet();
    }
  }

  void applyFilters() {
    final q = searchController.text.toLowerCase().trim();

    setState(() {
      filteredConflicts = activeConflicts.where((item) {
        final current = item['current'];
        final matchesSearch = fields.any((field) {
          final value = current[field]?.toString().toLowerCase() ?? '';
          return value.contains(q);
        });

        if (!matchesSearch) return false;
        for (final entry in activeFilters.entries) {
          final field = entry.key;
          final allowedValues = entry.value;

          final value = current[field]?.toString() ?? '';
          if (allowedValues.isNotEmpty && !allowedValues.contains(value)) {
            return false;
          }
        }

        return true;
      }).toList();
    });
  }

  void applySort(String field) {
    setState(() {
      if (sortField == field) {
        sortAscending = !sortAscending;
      } else {
        sortField = field;
        sortAscending = true;
      }
      filteredConflicts.sort((a, b) {
        final aVal = a['current'][field]?.toString().toLowerCase() ?? '';
        final bVal = b['current'][field]?.toString().toLowerCase() ?? '';
        final cmp = aVal.compareTo(bVal);
        return sortAscending ? cmp : -cmp;
      });
    });
  }

  void clearSelection() {
    setState(() {
      selectedRowIds.clear();
      selectedIndexes.clear();
      lowestSelectedIndex = null;
      highestSelectedIndex = null;
    });
  }

  void _openFilterMenu(String field) {
    final values = columnValues[field]!.toList()..sort();

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final tempSelected = activeFilters[field] ?? <String>{};

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Column(
              children: [
                ListTile(
                  title: Text("Filter: ${field.toUpperCase()}"),
                  trailing: TextButton(
                    onPressed: () {
                      setState(() {
                        activeFilters.remove(field);
                        applyFilters();
                      });
                      Navigator.pop(ctx);
                    },
                    child: const Text("Clear"),
                  ),
                ),

                const Divider(),

                Expanded(
                  child: ListView.builder(
                    itemCount: values.length,
                    itemBuilder: (context, i) {
                      final v = values[i];

                      return CheckboxListTile(
                        title: Text(v.isEmpty ? "(empty)" : v),
                        value: tempSelected.contains(v),
                        onChanged: (val) {
                          setModalState(() {
                            if (val == true) {
                              tempSelected.add(v);
                            } else {
                              tempSelected.remove(v);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),

                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      activeFilters[field] = tempSelected;
                      applyFilters();
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text("Apply Filter"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.all(10),
      title: const Text("Conflict Workspace"),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.95,
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            _buildActionBar(),
            _buildSearchBar(),
            const SizedBox(height: 8),
            Expanded(child: _buildTable()),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        ElevatedButton(
          onPressed: activeConflicts.isEmpty ? null : () => Navigator.pop(context),
          child: const Text("Finalize Import"),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: searchController,
      onChanged: (_) => applyFilters(),
      decoration: InputDecoration(
        hintText: "Search conflicts...",
        prefixIcon: const Icon(Icons.search),
        suffixIcon: searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  searchController.clear();
                  setState(() {
                    filteredConflicts = List.from(activeConflicts);
                  });
                },
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        isDense: true,
      ),
    );
  }

  Widget _buildTable() {
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 20,
          dataRowMaxHeight: 85,
          columns: fields.map(_buildColumn).toList(),
          rows: filteredConflicts.map(_buildRow).toList(),
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Text("${selectedRowIds.length} Selected", style: const TextStyle(fontWeight: FontWeight.bold)),

        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text("KEEP CURRENT"),
                onPressed: selectedRowIds.isEmpty
                    ? null
                    : () {
                        setState(() {
                          for (final item in activeConflicts) {
                            final id = item['current']['student_id_custom'].toString();

                            if (selectedRowIds.contains(id)) {
                              fieldSelections[id] ??= {};
                              for (final f in fields) {
                                fieldSelections[id]![f] = false;
                              }
                            }
                          }

                          activeConflicts.removeWhere(
                            (item) => selectedRowIds.contains(item['current']['student_id_custom'].toString()),
                          );

                          filteredConflicts = List.from(activeConflicts);
                          clearSelection();
                        });
                      },
              ),
            ),

            const SizedBox(width: 8),

            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text("OVERWRITE"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: selectedRowIds.isEmpty
                    ? null
                    : () {
                        setState(() {
                          for (final item in activeConflicts) {
                            final id = item['current']['student_id_custom'].toString();

                            if (selectedRowIds.contains(id)) {
                              fieldSelections[id] ??= {};
                              for (final f in fields) {
                                fieldSelections[id]![f] = true;
                              }
                            }
                          }

                          activeConflicts.removeWhere(
                            (item) => selectedRowIds.contains(item['current']['student_id_custom'].toString()),
                          );

                          filteredConflicts = List.from(activeConflicts);
                          clearSelection();
                        });
                      },
              ),
            ),
          ],
        ),

        TextButton.icon(
          icon: const Icon(Icons.select_all, size: 18),
          label: const Text("Select Interval"),
          onPressed: (lowestSelectedIndex == null || highestSelectedIndex == null)
              ? null
              : () {
                  setState(() {
                    for (int i = lowestSelectedIndex!; i <= highestSelectedIndex!; i++) {
                      final row = activeConflicts[i];
                      final id = row['current']['student_id_custom'].toString();
                      selectedRowIds.add(id);
                      selectedIndexes.add(i);
                    }
                  });
                },
        ),
      ],
    );
  }

  DataColumn _buildColumn(String f) {
    final isActive = sortField == f;
    return DataColumn(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => applySort(f),
            child: Text(f.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => applySort(f),
            child: Icon(
              isActive ? (sortAscending ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more,
              size: 14,
              color: isActive ? Colors.blue : Colors.grey,
            ),
          ),
          const SizedBox(width: 4),

          // filter icon
          GestureDetector(onTap: () => _openFilterMenu(f), child: const Icon(Icons.filter_alt, size: 14)),
        ],
      ),
    );
  }

  DataRow _buildRow(Map<String, dynamic> item) {
    final id = item['current']['student_id_custom'].toString();
    return DataRow(
      selected: selectedRowIds.contains(id),
      onSelectChanged: (val) {
        setState(() {
          final index = filteredConflicts.indexOf(item);
          if (val == true) {
            selectedRowIds.add(id);
            selectedIndexes.add(index);
          } else {
            selectedRowIds.remove(id);
            selectedIndexes.remove(index);
          }
          if (selectedIndexes.isEmpty) {
            lowestSelectedIndex = null;
            highestSelectedIndex = null;
          } else {
            lowestSelectedIndex = selectedIndexes.reduce((a, b) => a < b ? a : b);
            highestSelectedIndex = selectedIndexes.reduce((a, b) => a > b ? a : b);
          }
        });
      },
      cells: fields.map((f) {
        final curVal = item['current'][f].toString();
        final incVal = item['incoming'][f].toString();
        if (curVal == incVal) return DataCell(Text(curVal));
        fieldSelections[id] ??= {};
        final useExcel = fieldSelections[id]![f] ?? true;
        return DataCell(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(curVal),
              const Divider(height: 4),
              Text(incVal, style: TextStyle(color: useExcel ? Colors.red : Colors.grey)),
            ],
          ),
        );
      }).toList(),
    );
  }
}
