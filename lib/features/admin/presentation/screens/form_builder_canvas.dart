import 'dart:io';
import 'dart:isolate';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gyanshala_app/core/utils/excel_parser/excel_parser.dart'
    if (dart.library.js_interop) 'package:gyanshala_app/core/utils/excel_parser/excel_web_parser.dart'
    if (dart.library.io) 'package:gyanshala_app/core/utils/excel_parser/excel_mobile_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FormBuilderCanvas extends StatefulWidget {
  final String? formId;
  final String formTitle;

  const FormBuilderCanvas({super.key, this.formId, required this.formTitle});

  @override
  State<FormBuilderCanvas> createState() => _FormBuilderCanvasState();
}

class _FormBuilderCanvasState extends State<FormBuilderCanvas> {
  late TextEditingController _titleController;
  List<Map<String, dynamic>> _currentQuestions = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.formTitle);
    if (widget.formId != null) {
      _loadExistingFormQuestions();
    }
  }

  Future<void> _loadExistingFormQuestions() async {
    final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    final currentFormId = widget.formId;

    if (currentFormId == null || currentFormId.isEmpty || !uuidRegex.hasMatch(currentFormId)) {
      debugPrint("Skipping database fetch: formId is missing or invalid.");
      return;
    }

    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final data = await supabase
          .from('form_questions')
          .select('*')
          .eq('form_id', currentFormId)
          .order('sort_order', ascending: true);

      setState(() {
        _currentQuestions = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error loading form structure: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveFormStructureToSupabase() async {
    if (widget.formId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Cannot save: Form definition ID is missing."), backgroundColor: Colors.amber));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final List<Map<String, dynamic>> rowsToUpsert = [];

      for (int i = 0; i < _currentQuestions.length; i++) {
        final q = _currentQuestions[i];
        rowsToUpsert.add({
          if (q['id'] != null && !q['id'].toString().startsWith('new_')) 'id': q['id'],
          'form_id': widget.formId,
          'section': q['section'] ?? 'General',
          'question': q['question'],
          'required': q['required'] ?? false,
          'sort_order': i,
          'field_config': q['field_config'],
        });
      }

      await supabase.from('form_questions').upsert(rowsToUpsert, onConflict: 'id');

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Form setup changes saved successfully!"), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to save changes: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<String>> _pickOptionsFromExcel() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return [];
      final platformFile = result.files.single;
      List<int> bytes;
      if (platformFile.bytes != null) {
        bytes = platformFile.bytes!;
      } else if (platformFile.path != null) {
        bytes = File(platformFile.path!).readAsBytesSync();
      } else {
        return [];
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xff00afef)))),
      );

      await Future.delayed(const Duration(milliseconds: 100));

      List<String> parsedOptions = [];

      if (kIsWeb) {
        parsedOptions = await ExcelWebParser.parseFirstColumnFast(bytes);
      } else {
        parsedOptions = await Isolate.run(() {
          final excel = Excel.decodeBytes(bytes);
          List<String> options = [];
          for (var table in excel.tables.keys) {
            var sheet = excel.tables[table];
            if (sheet == null || sheet.rows.isEmpty) continue;
            for (var row in sheet.rows) {
              if (row.isNotEmpty && row[0] != null) {
                final cellValue = row[0]!.value;
                if (cellValue != null) {
                  final val = cellValue.toString().trim();
                  if (val.isNotEmpty && val != "null") {
                    options.add(val);
                  }
                }
              }
            }
            break;
          }
          return options;
        });
      }

      if (mounted) Navigator.pop(context);

      if (parsedOptions.isNotEmpty) {
        final rawHeaderValue = parsedOptions.first;
        if (mounted) {
          final skipFirstRow = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text("Header Detection"),
              content: Text("The first filled cell found is:\n\"$rawHeaderValue\"\n\nSkip this row?"),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Keep")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff00afef)),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text("Skip", style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );

          if (skipFirstRow ?? false) {
            parsedOptions.removeAt(0);
          }
        }
      }

      return parsedOptions;
    } catch (e) {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst || route is! PopupRoute);
      }
      debugPrint("Error reading spreadsheet matrix: $e");
      return [];
    }
  }

  Future<List<String>> _fetchAllTablePreviewData({required String tableName, String? roleFilter}) async {
    try {
      final supabase = Supabase.instance.client;
      if (tableName == 'clusters') {
        final res = await supabase.from('clusters').select('name').order('name');
        return res.map((row) => row['name'] as String).toList();
      }
      if (tableName == 'profiles') {
        var query = supabase.from('profiles').select('first_name, last_name');
        if (roleFilter != null && roleFilter != 'all') {
          query = query.eq('role', roleFilter as Object);
        }
        final res = await query;
        return res.map((row) => "${row['first_name'] ?? ''} ${row['last_name'] ?? ''}".trim()).toList();
      }
      if (tableName == 'villages') {
        final res = await supabase.from('villages').select('name').order('name');
        return res.map((row) => row['name'] as String).toList();
      }
      if (tableName == 'schools') {
        final res = await supabase.from('schools').select('name').order('name');
        return res.map((row) => row['name'] as String).toList();
      }
      return [];
    } catch (e) {
      return ['Error fetching table data: $e'];
    }
  }

  void _showCreateQuestionDialog(String type) {
    final questionController = TextEditingController();
    final sectionController = TextEditingController(text: 'General');
    bool isRequired = false;

    String sourceOptionType = 'static';
    final List<TextEditingController> staticOptionControllers = [TextEditingController()];

    String selectedTable = 'clusters';
    String selectedRoleFilter = 'all';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(
                "Configure New ${type == 'checkbox_search' ? 'Check box' : type} Field",
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xff00afef)),
              ),
              // Crucial fix: Directs the built-in action layout to align horizontally to the right
              actionsAlignment: MainAxisAlignment.end,
              content: SizedBox(
                width: 640,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 500),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Row 1: Question + Section + Mandatory Checkbox
                      Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: TextField(
                              controller: questionController,
                              decoration: const InputDecoration(labelText: 'Question Text *', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: sectionController,
                              decoration: const InputDecoration(labelText: 'Section / Group', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 140,
                            child: CheckboxListTile(
                              title: const Text("Mandatory", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                              contentPadding: EdgeInsets.zero,
                              value: isRequired,
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: (val) => setModalState(() => isRequired = val ?? false),
                            ),
                          ),
                        ],
                      ),

                      if (type == 'radio' || type == 'checkbox_search') ...[
                        const Divider(height: 24),

                        // Row 2: Radio Selectors + Far Right Re-import Button
                        Row(
                          children: [
                            Radio<String>(
                              value: 'static',
                              groupValue: sourceOptionType,
                              onChanged: (val) {
                                if (val != null) setModalState(() => sourceOptionType = val);
                              },
                            ),
                            const Text("Manual"),
                            const SizedBox(width: 8),
                            Radio<String>(
                              value: 'database',
                              groupValue: sourceOptionType,
                              onChanged: (val) {
                                if (val != null) setModalState(() => sourceOptionType = val);
                              },
                            ),
                            const Text("Database"),
                            const SizedBox(width: 8),
                            Radio<String>(
                              value: 'excel',
                              groupValue: sourceOptionType,
                              onChanged: (val) async {
                                if (val != null) {
                                  setModalState(() => sourceOptionType = val);
                                  final imported = await _pickOptionsFromExcel();
                                  if (imported.isNotEmpty) {
                                    setModalState(() {
                                      staticOptionControllers.clear();
                                      for (var opt in imported) {
                                        staticOptionControllers.add(TextEditingController(text: opt));
                                      }
                                    });
                                  }
                                }
                              },
                            ),
                            const Text("Excel"),

                            const Spacer(),

                            if (sourceOptionType == 'excel')
                              SizedBox(
                                height: 36,
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                                  icon: const Icon(Icons.refresh, size: 16, color: Colors.green),
                                  label: const Text(
                                    "Re-import Excel",
                                    style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
                                  ),
                                  onPressed: () async {
                                    final imported = await _pickOptionsFromExcel();
                                    if (imported.isNotEmpty) {
                                      setModalState(() {
                                        staticOptionControllers.clear();
                                        for (var opt in imported) {
                                          staticOptionControllers.add(TextEditingController(text: opt));
                                        }
                                      });
                                    }
                                  },
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Options Display List (Manual Input / Excel Data Grid View)
                        if (sourceOptionType == 'static' || sourceOptionType == 'excel') ...[
                          Expanded(
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: staticOptionControllers.length,
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0, right: 8.0),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: staticOptionControllers[index],
                                          decoration: InputDecoration(
                                            labelText: 'Option ${index + 1}',
                                            border: const OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle, color: Colors.red),
                                        onPressed: () {
                                          if (staticOptionControllers.length > 1) {
                                            setModalState(() => staticOptionControllers.removeAt(index));
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text("Add Option Line"),
                            onPressed: () => setModalState(() => staticOptionControllers.add(TextEditingController())),
                          ),
                        ],

                        // Database Option Block
                        if (sourceOptionType == 'database') ...[
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: selectedTable,
                            decoration: const InputDecoration(labelText: 'Target Lookup Table', border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(value: 'clusters', child: Text("Clusters (name)")),
                              DropdownMenuItem(value: 'villages', child: Text("Villages (name)")),
                              DropdownMenuItem(value: 'schools', child: Text("Schools (name)")),
                              DropdownMenuItem(value: 'profiles', child: Text("Profiles (first_name + last_name)")),
                            ],
                            onChanged: (val) => setModalState(() {
                              selectedTable = val!;
                              if (selectedTable != 'profiles') selectedRoleFilter = 'all';
                            }),
                          ),
                          if (selectedTable == 'profiles') ...[
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: selectedRoleFilter,
                              decoration: const InputDecoration(
                                labelText: 'Filter Access Scope By Role',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'all', child: Text("All Profiles")),
                                DropdownMenuItem(value: 'shikshaMitra', child: Text("Only Shiksha Mitras")),
                                DropdownMenuItem(value: 'seniorMentor', child: Text("Only Senior Mentors")),
                                DropdownMenuItem(value: 'admin', child: Text("Only Administrators")),
                              ],
                              onChanged: (val) => setModalState(() => selectedRoleFilter = val!),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Expanded(
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xff00afef).withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xff00afef).withValues(alpha: 0.2)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: const [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Icon(Icons.storage, size: 16, color: Color(0xff00afef)),
                                            SizedBox(width: 6),
                                            Text(
                                              "Live Table Entire Dataset",
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xff00afef),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.unfold_more, size: 16, color: Color(0xff00afef)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: FutureBuilder<List<String>>(
                                      future: _fetchAllTablePreviewData(tableName: selectedTable, roleFilter: selectedRoleFilter),
                                      builder: (context, snapshot) {
                                        if (snapshot.connectionState == ConnectionState.waiting) {
                                          return const Center(
                                            child: SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xff00afef)),
                                            ),
                                          );
                                        }
                                        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                                          return const Text(
                                            "No matching records found in this table configuration.",
                                            style: TextStyle(fontSize: 12, color: Colors.grey),
                                          );
                                        }
                                        return SingleChildScrollView(
                                          physics: const BouncingScrollPhysics(),
                                          child: SizedBox(
                                            width: double.infinity,
                                            child: Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: snapshot.data!
                                                  .map(
                                                    (entry) => Chip(
                                                      label: Text(
                                                        entry,
                                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                                                      ),
                                                      backgroundColor: Colors.white,
                                                      elevation: 0,
                                                      side: const BorderSide(color: Color(0xff00afef)),
                                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                    ),
                                                  )
                                                  .toList(),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              // Safely isolated inside the native actions container to ensure single line rendering without layout errors
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff00afef)),
                  onPressed: () {
                    if (questionController.text.trim().isEmpty) return;
                    _commitQuestionToCanvas(
                      type: type,
                      labelText: questionController.text.trim(),
                      section: sectionController.text.trim(),
                      required: isRequired,
                      sourceType: sourceOptionType,
                      staticControllers: staticOptionControllers,
                      tableName: selectedTable,
                      roleFilter: selectedRoleFilter,
                    );
                    Navigator.pop(context);
                  },
                  child: const Text("Add Field", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _commitQuestionToCanvas({
    required String type,
    required String labelText,
    required String section,
    required bool required,
    required String sourceType,
    required List<TextEditingController> staticControllers,
    required String tableName,
    required String roleFilter,
  }) {
    final Map<String, dynamic> configBlock = {'type': type};

    if (type == 'radio' || type == 'checkbox_search') {
      if (sourceType == 'static' || sourceType == 'excel') {
        final options = staticControllers.map((c) => c.text.trim()).where((text) => text.isNotEmpty).toList();
        configBlock['options'] = options.isNotEmpty ? options : ['Default Option'];
        configBlock['source_meta'] = sourceType;
      } else {
        final Map<String, dynamic> datasourcePayload = {'table': tableName, 'value_column': 'id'};
        switch (tableName) {
          case 'clusters':
            datasourcePayload['label_column'] = 'name';
            break;
          case 'villages':
            datasourcePayload['label_column'] = 'name';
            datasourcePayload['relational_parent_key'] = 'cluster_id';
            break;
          case 'schools':
            datasourcePayload['label_column'] = 'name';
            datasourcePayload['relational_parent_key'] = 'village_id';
            break;
          case 'profiles':
            datasourcePayload['label_column'] = 'composite_name';
            if (roleFilter != 'all') {
              datasourcePayload['filter_column'] = 'role';
              datasourcePayload['filter_value'] = roleFilter;
            }
            break;
        }
        configBlock['datasource'] = datasourcePayload;
      }
    }

    setState(() {
      _currentQuestions.add({
        'id': 'new_${DateTime.now().millisecondsSinceEpoch}',
        'question': labelText,
        'section': section.isEmpty ? 'General' : section,
        'required': required,
        'field_config': configBlock,
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titleController.text, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xff00afef),
        leading: const BackButton(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.save, size: 28, color: Colors.white),
            onPressed: _isLoading ? null : _saveFormStructureToSupabase,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xff00afef)))
          : Column(
              children: [
                Expanded(
                  child: _currentQuestions.isEmpty
                      ? const Center(
                          child: Text("No Fields Added Yet. Click below to add inputs.", style: TextStyle(color: Colors.grey)),
                        )
                      : ReorderableListView.builder(
                          itemCount: _currentQuestions.length,
                          onReorder: (oldIndex, newIndex) {
                            setState(() {
                              if (newIndex > oldIndex) newIndex -= 1;
                              final item = _currentQuestions.removeAt(oldIndex);
                              _currentQuestions.insert(newIndex, item);
                            });
                          },
                          itemBuilder: (context, idx) {
                            final q = _currentQuestions[idx];
                            return Card(
                              key: ValueKey(q['id'] ?? 'index_$idx'),
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              child: ListTile(
                                leading: const Icon(Icons.drag_indicator, color: Colors.grey),
                                title: Text(q['question'] ?? ''),
                                subtitle: Text(
                                  "Section: ${q['section']} | Type: ${q['field_config']['type'] == 'checkbox_search' ? 'Check box' : q['field_config']['type']}",
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  onPressed: () => setState(() => _currentQuestions.removeAt(idx)),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                _buildToolboxTray(),
              ],
            ),
    );
  }

  Widget _buildToolboxTray() {
    return Container(
      color: Colors.grey[200],
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(child: _toolButton("Text", Icons.text_fields, () => _showCreateQuestionDialog('text'))),
            Expanded(child: _toolButton("Radio", Icons.radio_button_checked, () => _showCreateQuestionDialog('radio'))),
            Expanded(
              child: _toolButton("Check box", Icons.check_box_outlined, () => _showCreateQuestionDialog('checkbox_search')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolButton(String label, IconData icon, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black87),
        onPressed: onPressed,
        icon: Icon(icon, size: 16, color: const Color(0xff00afef)),
        label: Text(label, style: const TextStyle(fontSize: 11)),
      ),
    );
  }
}
