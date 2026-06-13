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
  List<Map<String, dynamic>> _rows = [];
  bool _isLoading = true;

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
        _rows = List<Map<String, dynamic>>.from(responsesData);
        _isLoading = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error fetching table schema: $e"), backgroundColor: Colors.red));
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_rows.isEmpty) {
      return const Center(child: Text("No submissions found"));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: _buildTable()),
          ),
        ),
      ],
    );
  }

  Widget _buildTable() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: Colors.grey.shade300, width: 0.5),
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFFE6F7FF)),
            children: [
              _buildHeaderCell("Employee Name"),
              _buildHeaderCell("Submission Date"),
              _buildHeaderCell("GPS Location"),
              ..._columns.map((q) => _buildHeaderCell(q['question'] ?? '')),
            ],
          ),
          ..._rows.map((row) {
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

  Widget _buildHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 13, top: 13, bottom: 13, right: 13),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black),
      ),
    );
  }

  Widget _buildDataCell(String text, {bool isBold = false, Color? textColor}) {
    return Padding(
      padding: const EdgeInsets.only(left: 13, top: 13, bottom: 13, right: 13),
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
      for (final row in _rows) {
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
        final bytes = excel.encode();
        debugPrint("Excel bytes length: ${bytes?.length}");
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Excel exported successfully")));
        }
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Export failed: $e"), backgroundColor: Colors.red));
    }
  }
}
