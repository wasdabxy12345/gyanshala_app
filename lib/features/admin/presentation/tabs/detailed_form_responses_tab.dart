import 'dart:io';
import 'dart:ui';

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
  DateTime? _fromDate;
  DateTime? _toDate;
  int _sortColumnIndex = 1;
  bool _isAscending = false;

  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  final Map<int, Set<String>> _selectedColumnFilters = {};

  Future<void> refresh() => _fetchTableData();
  Future<void> exportExcel() => _exportExcel();

  @override
  void initState() {
    super.initState();
    _fetchTableData();
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  String formatISTDateTime(String utcTimestamp) {
    final utcTime = DateTime.parse(utcTimestamp);
    final localTime = utcTime.toLocal();
    return DateFormat('dd MMM yyyy, hh:mm a').format(localTime);
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
        if (_fromDate != null || _toDate != null) {
          final submittedAt = DateTime.parse(row['submitted_at']);

          if (_fromDate != null) {
            final from = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);

            if (submittedAt.isBefore(from)) {
              return false;
            }
          }

          if (_toDate != null) {
            final to = DateTime(_toDate!.year, _toDate!.month, _toDate!.day, 23, 59, 59);

            if (submittedAt.isAfter(to)) {
              return false;
            }
          }
        }
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
      return formatISTDateTime(row['submitted_at'].toString());
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_horizontalController.hasClients) {
        debugPrint('Horizontal extent: ${_horizontalController.position.maxScrollExtent}');
      }
    });

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_rawRows.isEmpty) {
      return const Center(child: Text("No submissions found"));
    }

    final bool hasActiveFilters = _selectedColumnFilters.isNotEmpty;

    final List<String> headerTitles = [
      "Employee Name",
      "Submission Date",
      "GPS Location",
      ..._columns.map((q) => (q['question'] ?? '').toString()),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasActiveFilters)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13.0, vertical: 3.0),
            child: Row(
              children: [
                Text(
                  'Showing ${_filteredRows.length} of ${_rawRows.length} responses',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _clearAllFilters,
                  icon: const Icon(Icons.filter_alt_off, size: 13),
                  label: const Text('Clear Active Filters'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
          ),
        Expanded(
          child: _filteredRows.isEmpty
              ? const Center(child: Text("Nothing found matching applied filters"))
              : ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad}),
                  child: ScrollbarTheme(
                    data: ScrollbarThemeData(
                      thumbVisibility: WidgetStateProperty.all(true),
                      trackVisibility: WidgetStateProperty.all(true),
                      thickness: WidgetStateProperty.all(13),
                      thumbColor: WidgetStateProperty.all(Colors.grey.shade600),
                    ),
                    child: Scrollbar(
                      controller: _verticalController,
                      thumbVisibility: true,
                      trackVisibility: true,
                      scrollbarOrientation: ScrollbarOrientation.right,
                      notificationPredicate: (notification) {
                        return notification.metrics.axis == Axis.vertical;
                      },
                      child: Scrollbar(
                        controller: _horizontalController,
                        thumbVisibility: true,
                        trackVisibility: true,
                        scrollbarOrientation: ScrollbarOrientation.bottom,
                        notificationPredicate: (notification) {
                          return notification.metrics.axis == Axis.horizontal;
                        },
                        child: SingleChildScrollView(
                          controller: _verticalController,
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            controller: _horizontalController,
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width),
                              child: _buildTable(headerTitles),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildTable(List<String> headerTitles) {
    return Container(
      padding: const EdgeInsets.all(13),
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: Colors.grey.shade300, width: 0.5),
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFFE6F7FF)),
            children: List.generate(headerTitles.length, (index) {
              return _buildSortableHeaderCell(headerTitles[index], index);
            }),
          ),
          ..._filteredRows.map((row) {
            final profile = row['profiles'] as Map<String, dynamic>?;
            final employeeName = profile != null
                ? "${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}".trim()
                : "User (${row['user_id'].toString().substring(0, 6)})";

            final formattedDate = formatISTDateTime(row['submitted_at'].toString());

            final dynamic lat = row['latitude'];
            final dynamic lon = row['longitude'];

            final Map<String, dynamic> answersPayload = row['responses'] as Map<String, dynamic>? ?? {};

            return TableRow(
              children: [
                _buildDataCell(employeeName, isBold: true),
                _buildDataCell(formattedDate, textColor: Colors.grey.shade700),
                _buildDataCell(
                  lat != null && lon != null
                      ? "${(lat as num).toStringAsFixed(5)}, ${(lon as num).toStringAsFixed(5)}"
                      : "No GPS Data",
                  textColor: lat != null ? Colors.black : Colors.grey,
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
    final bool hasFilter =
        _selectedColumnFilters[columnIndex] != null || (columnIndex == 1 && (_fromDate != null || _toDate != null));

    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
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
                      child: Tooltip(
                        message: text,
                        child: Text(
                          text,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
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
            onTap: () {
              if (columnIndex == 1) {
                _showDateFilterDialog();
              } else {
                _showFilterMenu(columnIndex, text);
              }
            },
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
      padding: const EdgeInsets.all(13),
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

  Future<void> _exportExcel() async {
    try {
      final excel = Excel.createExcel();
      final Sheet sheet = excel['Sheet1'];
      final headers = ['Employee Name', 'Submission Date', 'GPS Location', ..._columns.map((q) => q['question'].toString())];

      sheet.appendRow(headers.map((e) => TextCellValue(e)).toList());

      for (final row in _filteredRows) {
        final profile = row['profiles'] as Map<String, dynamic>?;

        final employeeName = profile != null
            ? "${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}".trim()
            : "User (${row['user_id'].toString().substring(0, 6)})";

        final submittedAt = formatISTDateTime(row['submitted_at'].toString());

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

  Future<void> _showDateFilterDialog() async {
    DateTime? tempFrom = _fromDate;
    DateTime? tempTo = _toDate;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Filter Submission Date'),
              content: SizedBox(
                width: 350,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: Text(tempFrom == null ? 'Start Date' : DateFormat('dd MMM yyyy').format(tempFrom!)),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                          initialDate: tempFrom ?? DateTime.now(),
                        );

                        if (picked != null) {
                          setDialogState(() {
                            tempFrom = picked;
                          });
                        }
                      },
                    ),
                    ListTile(
                      title: Text(tempTo == null ? 'End Date' : DateFormat('dd MMM yyyy').format(tempTo!)),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                          initialDate: tempTo ?? DateTime.now(),
                        );

                        if (picked != null) {
                          setDialogState(() {
                            tempTo = picked;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _fromDate = null;
                      _toDate = null;
                      _applyAllFilters();
                    });

                    Navigator.pop(context);
                  },
                  child: const Text('Clear'),
                ),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _fromDate = tempFrom;
                      _toDate = tempTo;
                      _applyAllFilters();
                    });

                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
