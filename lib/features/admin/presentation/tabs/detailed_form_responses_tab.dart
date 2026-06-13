import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_html/html.dart' as html;

class DetailedFormResponsesTab extends StatefulWidget {
  final String formId;
  final String formTitle;

  const DetailedFormResponsesTab({super.key, required this.formId, required this.formTitle});

  @override
  State<DetailedFormResponsesTab> createState() => DetailedFormResponsesTabState();
}

class DetailedFormResponsesTabState extends State<DetailedFormResponsesTab> {
  List<Map<String, dynamic>> _columns = [];
  List<Map<String, dynamic>> _rawRows = [];
  List<Map<String, dynamic>> _filteredRows = [];
  bool _isLoading = true;
  int _sortColumnIndex = 1;
  bool _isAscending = false;
  final Map<int, Set<String>> _selectedColumnFilters = {};

  Future<void> refresh() => _fetchTableData();
  Future<void> exportExcel() => _exportToExcel();

  @override
  void initState() {
    super.initState();
    _fetchTableData();
  }

  Future<void> _fetchTableData() async {
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final questionsData = await supabase
          .from('form_questions')
          .select('id, question')
          .eq('form_id', widget.formId)
          .order('sort_order', ascending: true);

      final responsesData = await supabase
          .from('form_responses')
          .select('id, submitted_at, responses, user_id, latitude, longitude, profiles(first_name, last_name)')
          .eq('form_id', widget.formId)
          .order('submitted_at', ascending: false);

      setState(() {
        _columns = List<Map<String, dynamic>>.from(questionsData);
        _rawRows = List<Map<String, dynamic>>.from(responsesData);
        _selectedColumnFilters.clear();
        _applyAllFilters();
        _isLoading = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error fetching table schema: $e"), backgroundColor: Colors.red));
      setState(() => _isLoading = false);
    }
  }

  void _onSort(int columnIndex) {
    setState(() {
      if (_sortColumnIndex == columnIndex) {
        _isAscending = !_isAscending;
      } else {
        _sortColumnIndex = columnIndex;
        _isAscending = true;
      }
      _applySorting();
    });
  }

  void _applySorting() {
    _filteredRows.sort((a, b) {
      String valA = _getCellValueString(a, _sortColumnIndex);
      String valB = _getCellValueString(b, _sortColumnIndex);
      if (_sortColumnIndex == 1) {
        final dateA = DateTime.tryParse(a['submitted_at']?.toString() ?? '') ?? DateTime(0);
        final dateB = DateTime.tryParse(b['submitted_at']?.toString() ?? '') ?? DateTime(0);
        return _isAscending ? dateA.compareTo(dateB) : dateB.compareTo(dateA);
      }

      int compare = valA.toLowerCase().compareTo(valB.toLowerCase());
      return _isAscending ? compare : -compare;
    });
  }

  void _applyAllFilters() {
    setState(() {
      _filteredRows = _rawRows.where((row) {
        for (int i = 0; i < (_columns.length + 3); i++) {
          if (_selectedColumnFilters[i] != null) {
            final value = _getCellValueString(row, i);
            if (!_selectedColumnFilters[i]!.contains(value)) {
              return false;
            }
          }
        }
        return true;
      }).toList();
      _applySorting();
    });
  }

  String _getCellValueString(Map<String, dynamic> row, int index) {
    if (index == 0) {
      final profile = row['profiles'] as Map<String, dynamic>?;
      return profile != null
          ? "${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}".trim()
          : "User (${row['user_id'].toString().substring(0, 6)})";
    }
    if (index == 1) {
      final DateTime parsedTime = DateTime.parse(row['submitted_at']);
      return DateFormat('dd MMM yyyy, hh:mm a').format(parsedTime);
    }
    if (index == 2) {
      final dynamic lat = row['latitude'];
      final dynamic lon = row['longitude'];
      return lat != null && lon != null
          ? "${(lat as num).toStringAsFixed(5)}, ${(lon as num).toStringAsFixed(5)}"
          : "No GPS Data";
    }
    final questionIdx = index - 3;
    if (questionIdx >= 0 && questionIdx < _columns.length) {
      final String questionId = _columns[questionIdx]['id'].toString();
      final Map<String, dynamic> answersPayload = row['responses'] as Map<String, dynamic>? ?? {};
      final dynamic rawAnswer = answersPayload[questionId];

      if (rawAnswer == null || (rawAnswer is List && rawAnswer.isEmpty)) {
        return "-";
      }
      if (rawAnswer is List) {
        return rawAnswer.join(', ');
      }
      return rawAnswer.toString();
    }
    return "";
  }

  List<String> _getUniqueValuesForColumn(int columnIndex) {
    final Set<String> values = {};
    for (final row in _rawRows) {
      values.add(_getCellValueString(row, columnIndex));
    }
    return values.toList()..sort();
  }

  Future<void> _showFilterMenu(int columnIndex, String label) async {
    final allValues = _getUniqueValuesForColumn(columnIndex);
    Set<String> currentSelection = _selectedColumnFilters[columnIndex] != null
        ? Set.from(_selectedColumnFilters[columnIndex]!)
        : Set.from(allValues);

    final dialogSearchController = TextEditingController();
    List<String> filteredValues = List.from(allValues);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text("Filter by $label"),
          content: SizedBox(
            width: 320,
            height: 333,
            child: Column(
              children: [
                TextField(
                  controller: dialogSearchController,
                  decoration: const InputDecoration(hintText: "Search values...", prefixIcon: Icon(Icons.search)),
                  onChanged: (value) {
                    setStateDialog(() {
                      filteredValues = allValues.where((e) => e.toLowerCase().contains(value.toLowerCase())).toList();
                    });
                  },
                ),
                const SizedBox(height: 13),
                CheckboxListTile(
                  dense: true,
                  value: currentSelection.length == allValues.length,
                  title: const Text("Select All"),
                  onChanged: (checked) {
                    setStateDialog(() {
                      currentSelection = checked == true ? Set.from(allValues) : {};
                    });
                  },
                ),
                const Divider(),
                Expanded(
                  child: ListView(
                    children: filteredValues.map((value) {
                      return CheckboxListTile(
                        dense: true,
                        value: currentSelection.contains(value),
                        title: Text(value),
                        onChanged: (checked) {
                          setStateDialog(() {
                            checked == true ? currentSelection.add(value) : currentSelection.remove(value);
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  final isAllSelected = currentSelection.length == allValues.length;
                  if (isAllSelected) {
                    _selectedColumnFilters.remove(columnIndex);
                  } else {
                    _selectedColumnFilters[columnIndex] = Set.from(currentSelection);
                  }
                  _applyAllFilters();
                });
                Navigator.pop(ctx);
              },
              child: const Text("Apply"),
            ),
          ],
        ),
      ),
    );
  }

  void _clearAllFilters() {
    setState(() {
      _selectedColumnFilters.clear();
      _applyAllFilters();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_rawRows.isEmpty) {
      return const Center(child: Text("No submissions found"));
    }

    final bool hasActiveFilters = _selectedColumnFilters.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasActiveFilters)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 3.0),
            child: Row(
              children: [
                Text(
                  'Showing ${_filteredRows.length} of ${_rawRows.length} responses',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _clearAllFilters,
                  icon: const Icon(Icons.filter_alt_off, size: 16),
                  label: const Text('Clear Active Filters'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
          ),
        Expanded(
          child: _filteredRows.isEmpty
              ? const Center(child: Text("No responses match the active filters."))
              : SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: _buildTable()),
                ),
        ),
      ],
    );
  }

  Widget _buildTable() {
    return Container(
      padding: const EdgeInsets.all(13),
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: Colors.grey.shade300, width: 0.5),
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFFE6F7FF)),
            children: [
              _buildSortableHeaderCell("Employee Name", 0),
              _buildSortableHeaderCell("Submission Date", 1),
              _buildSortableHeaderCell("GPS Location", 2),
              ..._columns.asMap().entries.map((entry) {
                final int dynamicIdx = entry.key + 3;
                final String title = entry.value['question'] ?? '';
                return _buildSortableHeaderCell(title, dynamicIdx);
              }),
            ],
          ),
          ..._filteredRows.map((row) {
            final profile = row['profiles'] as Map<String, dynamic>?;
            final employeeName = profile != null
                ? "${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}".trim()
                : "User (${row['user_id'].toString().substring(0, 6)})";

            final DateTime parsedTime = DateTime.parse(row['submitted_at']);
            final formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(parsedTime);

            final dynamic lat = row['latitude'];
            final dynamic lon = row['longitude'];

            final Map<String, dynamic> answersPayload = row['responses'] as Map<String, dynamic>? ?? {};

            return TableRow(
              children: [
                _buildDataCell(employeeName, isBold: true),
                _buildDataCell(formattedDate, textColor: Colors.grey.shade700),
                _buildDataCell(
                  lat != null && lon != null
                      ? "${(lat as num).toStringAsFixed(5)},\n${(lon as num).toStringAsFixed(5)}"
                      : "No GPS Data",
                  textColor: lat != null ? Colors.black87 : Colors.grey,
                ),
                ..._columns.map((q) {
                  final String questionId = q['id'].toString();
                  final dynamic rawAnswer = answersPayload[questionId];

                  if (rawAnswer == null || (rawAnswer is List && rawAnswer.isEmpty)) {
                    return _buildDataCell("-", textColor: Colors.grey);
                  }

                  if (rawAnswer is List) {
                    final String stackedString = rawAnswer.map((item) => "• ${item.toString()}").join("\n");
                    return _buildDataCell(stackedString);
                  }

                  return _buildDataCell(rawAnswer.toString());
                }),
              ],
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildSortableHeaderCell(String text, int columnIndex) {
    final bool isSorted = _sortColumnIndex == columnIndex;
    final bool hasFilter = _selectedColumnFilters[columnIndex] != null;

    return Container(
      constraints: const BoxConstraints(minWidth: 130, maxWidth: 500),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: InkWell(
              onTap: () => _onSort(columnIndex),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 3.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        text,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      isSorted ? (_isAscending ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more,
                      size: 13,
                      color: isSorted ? Colors.blue : Colors.grey.shade600,
                    ),
                  ],
                ),
              ),
            ),
          ),
          InkWell(
            onTap: () => _showFilterMenu(columnIndex, text),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: hasFilter ? Colors.blue.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Icon(Icons.filter_alt, size: 15, color: hasFilter ? Colors.blue : Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataCell(String text, {bool isBold = false, Color? textColor}) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.3,
          fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
          color: textColor ?? Colors.black,
        ),
      ),
    );
  }

  Future<void> _exportToExcel() async {
    try {
      final excel = Excel.createExcel();
      final Sheet sheet = excel['Responses'];
      final headers = ['Employee Name', 'Submission Date', 'GPS Location', ..._columns.map((q) => q['question'].toString())];

      sheet.appendRow(headers.map((e) => TextCellValue(e)).toList());

      for (final row in _filteredRows) {
        final profile = row['profiles'] as Map<String, dynamic>?;

        final employeeName = profile != null
            ? "${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}".trim()
            : "User (${row['user_id'].toString().substring(0, 6)})";

        final submittedAt = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(row['submitted_at']));

        final lat = row['latitude'];
        final lon = row['longitude'];

        final gps = lat != null && lon != null
            ? "${(lat as num).toStringAsFixed(5)}, ${(lon as num).toStringAsFixed(5)}"
            : "No GPS Data";

        final answers = _columns.map((q) {
          final questionId = q['id'].toString();
          final rawAnswer = (row['responses'] as Map<String, dynamic>? ?? {})[questionId];

          if (rawAnswer == null) return '';

          if (rawAnswer is List) {
            return rawAnswer.join(', ');
          }

          return rawAnswer.toString();
        }).toList();

        sheet.appendRow([
          TextCellValue(employeeName),
          TextCellValue(submittedAt),
          TextCellValue(gps),
          ...answers.map((e) => TextCellValue(e)),
        ]);
      }
      final bytes = excel.encode();
      if (bytes == null) {
        throw Exception('Failed to generate excel file');
      }
      final fileName = "${widget.formTitle} [${DateTime.now()}].xlsx";
      if (kIsWeb) {
        debugPrint("Excel bytes length: ${bytes.length}");
        final blob = html.Blob([bytes], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement()
          ..href = url
          ..download = fileName
          ..style.display = 'none';

        html.document.body?.children.add(anchor);
        anchor.click();
        anchor.remove();
        html.Url.revokeObjectUrl(url);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Excel download started")));
        }
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(bytes);
        await OpenFilex.open(file.path);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Excel exported successfully")));
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Export failed: $e"), backgroundColor: Colors.red));
    }
  }
}
