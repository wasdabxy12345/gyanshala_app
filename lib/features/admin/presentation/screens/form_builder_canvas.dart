import 'dart:io';
import 'dart:isolate';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
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

  List<String> _deletedQuestionIds = <String>[];
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
        _deletedQuestionIds = <String>[];
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

      if (_deletedQuestionIds.isNotEmpty) {
        await supabase.from('form_questions').delete().inFilter('id', _deletedQuestionIds);
      }

      final List<Map<String, dynamic>> newRowsToInsert = [];
      final List<Map<String, dynamic>> existingRowsToUpsert = [];
      final Map<String, String> tempToRealIdMap = {};

      for (int i = 0; i < _currentQuestions.length; i++) {
        final q = _currentQuestions[i];
        final String currentId = q['id'].toString();

        final Map<String, dynamic> rowData = {
          'form_id': widget.formId,
          'section': q['section'] ?? 'General',
          'question': q['question'] ?? '',
          'required': q['required'] ?? false,
          'sort_order': i,
          'field_config': Map<String, dynamic>.from(q['field_config'] ?? {}),
        };

        if (currentId.startsWith('new_')) {
          newRowsToInsert.add({'temp_canvas_id': currentId, ...rowData});
        } else {
          rowData['id'] = q['id'];
          existingRowsToUpsert.add(rowData);
          tempToRealIdMap[currentId] = currentId;
        }
      }

      if (newRowsToInsert.isNotEmpty) {
        final pureInserts = newRowsToInsert.map((r) {
          final clone = Map<String, dynamic>.from(r);
          clone.remove('temp_canvas_id');
          return clone;
        }).toList();

        final rawResponse = await supabase.from('form_questions').insert(pureInserts).select('id, question, sort_order');

        final List<Map<String, dynamic>> insertedRecords = List<Map<String, dynamic>>.from(rawResponse);

        for (final Map<String, dynamic> record in insertedRecords) {
          final String dbQuestion = (record['question'] ?? '').toString();
          final String dbSortOrder = (record['sort_order'] ?? '').toString();

          int matchingInputIndex = -1;
          for (int k = 0; k < newRowsToInsert.length; k++) {
            final String canvasQuestion = (newRowsToInsert[k]['question'] ?? '').toString();
            final String canvasSortOrder = (newRowsToInsert[k]['sort_order'] ?? '').toString();

            if (canvasQuestion == dbQuestion && canvasSortOrder == dbSortOrder) {
              matchingInputIndex = k;
              break;
            }
          }

          if (matchingInputIndex != -1) {
            final String tempId = (newRowsToInsert[matchingInputIndex]['temp_canvas_id'] ?? '').toString();
            final String realId = (record['id'] ?? '').toString();
            if (tempId.isNotEmpty && realId.isNotEmpty) {
              tempToRealIdMap[tempId] = realId;
            }
          }
        }
      }

      final rawFormQuestions = await supabase.from('form_questions').select('*').eq('form_id', widget.formId!);

      final List<Map<String, dynamic>> completeFormQuestions = List<Map<String, dynamic>>.from(rawFormQuestions);
      final List<Map<String, dynamic>> finalRemappedRows = [];

      for (var question in completeFormQuestions) {
        final config = Map<String, dynamic>.from(question['field_config'] ?? {});
        final skipLogic = config['skip_logic'] != null ? Map<String, dynamic>.from(config['skip_logic']) : null;

        if (skipLogic != null && skipLogic['enabled'] == true) {
          final currentDepId = skipLogic['dependent_question_id']?.toString();

          if (currentDepId != null && tempToRealIdMap.containsKey(currentDepId)) {
            skipLogic['dependent_question_id'] = tempToRealIdMap[currentDepId];
            config['skip_logic'] = skipLogic;

            finalRemappedRows.add({
              'id': question['id'],
              'form_id': question['form_id'],
              'section': question['section'],
              'question': question['question'],
              'required': question['required'],
              'sort_order': question['sort_order'],
              'field_config': config,
            });
          }
        }
      }

      if (finalRemappedRows.isNotEmpty) {
        await supabase.from('form_questions').upsert(finalRemappedRows, onConflict: 'id');
      }
      if (existingRowsToUpsert.isNotEmpty) {
        await supabase.from('form_questions').upsert(existingRowsToUpsert, onConflict: 'id');
      }

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
        parsedOptions = await ExcelParser.parseFirstColumnFast(bytes);
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

  void _showConfigureQuestionDialog({required String type, Map<String, dynamic>? existingQuestion, int? editIndex}) {
    final isEditing = existingQuestion != null && editIndex != null;

    final questionController = TextEditingController(text: isEditing ? existingQuestion['question'] : '');
    final sectionController = TextEditingController(text: isEditing ? existingQuestion['section'] : 'General');
    bool isRequired = isEditing ? (existingQuestion['required'] ?? false) : false;
    final config = isEditing ? Map<String, dynamic>.from(existingQuestion['field_config'] ?? {}) : {};

    String sourceOptionType = config['source_meta']?.toString() ?? 'static';
    if (config['datasource'] != null) {
      sourceOptionType = 'database';
    }

    // MODIFIED: Read the allow_other option flag from existing configuration
    bool allowOtherOption = config['allow_other'] ?? false;

    final List<TextEditingController> staticOptionControllers = [];
    if (isEditing && (sourceOptionType == 'static' || sourceOptionType == 'excel')) {
      final existingOptions = List<dynamic>.from(config['options'] ?? []);
      for (var opt in existingOptions) {
        staticOptionControllers.add(TextEditingController(text: opt.toString()));
      }
    }
    if (staticOptionControllers.isEmpty) {
      staticOptionControllers.add(TextEditingController());
    }

    String selectedTable = config['datasource']?['table']?.toString() ?? 'clusters';
    final skipBlock = config['skip_logic'] != null ? Map<String, dynamic>.from(config['skip_logic']) : null;
    bool enableSkipLogic = skipBlock != null ? (skipBlock['enabled'] ?? false) : false;
    String? selectedDependentQuestionId = skipBlock?['dependent_question_id']?.toString();
    String skipOperator = skipBlock?['operator']?.toString() ?? 'equals';
    final skipValueController = TextEditingController(text: skipBlock?['value']?.toString() ?? '');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtratedPriorQuestions = _currentQuestions.where((q) {
              if (!isEditing) return true;
              final currentIdx = _currentQuestions.indexOf(q);
              return currentIdx < editIndex;
            }).toList();

            Future<void> handleSmartSpreadsheetPaste(int index) async {
              final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
              if (data == null || data.text == null || data.text!.isEmpty) return;

              final String pasteRaw = data.text!;

              if (pasteRaw.contains('\n')) {
                final List<String> parsedLines = pasteRaw
                    .split(RegExp(r'\r?\n'))
                    .map((line) => line.trim())
                    .where((line) => line.isNotEmpty)
                    .toList();

                if (parsedLines.length > 1) {
                  setModalState(() {
                    staticOptionControllers[index].text = parsedLines.first;
                    for (int i = 1; i < parsedLines.length; i++) {
                      staticOptionControllers.insert(index + i, TextEditingController(text: parsedLines[i]));
                    }
                  });
                  return;
                }
              }
              staticOptionControllers[index].text = pasteRaw;
            }

            return AlertDialog(
              title: Text(
                isEditing
                    ? "Modify ${type} Question Parameters"
                    : "Configure New ${type == 'checkbox_search' ? 'Check box' : type} Field",
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xff00afef)),
              ),
              actionsAlignment: MainAxisAlignment.end,
              content: SizedBox(
                width: 680,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                            width: 130,
                            child: CheckboxListTile(
                              title: const Text("Required", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
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
                        const Text("Option Data Mapping Strategy", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<String>(
                            segments: const <ButtonSegment<String>>[
                              ButtonSegment<String>(
                                value: 'static',
                                label: Text('Manual'),
                                icon: Icon(Icons.edit_note, size: 16),
                              ),
                              ButtonSegment<String>(
                                value: 'database',
                                label: Text('Database'),
                                icon: Icon(Icons.storage, size: 16),
                              ),
                              ButtonSegment<String>(
                                value: 'excel',
                                label: Text('Excel'),
                                icon: Icon(Icons.table_chart, size: 16),
                              ),
                            ],
                            selected: <String>{sourceOptionType},
                            onSelectionChanged: (Set<String> newSelection) async {
                              final val = newSelection.first;
                              setModalState(() => sourceOptionType = val);
                              if (val == 'excel') {
                                final imported = await _pickOptionsFromExcel();
                                if (imported.isNotEmpty) {
                                  setModalState(() {
                                    staticOptionControllers.clear();
                                    for (final opt in imported) {
                                      staticOptionControllers.add(TextEditingController(text: opt));
                                    }
                                  });
                                }
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (sourceOptionType == 'static' || sourceOptionType == 'excel') ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6.0),
                            child: Text(
                              "💡 Tip: You can copy cells directly from Excel and hit Ctrl+V / Cmd+V into any option row below to paste them into individual options.",
                              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey.shade700),
                            ),
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: staticOptionControllers.length,
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6.0),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: SizedBox(
                                          height: 40,
                                          child: CallbackShortcuts(
                                            bindings: <ShortcutActivator, VoidCallback>{
                                              const SingleActivator(LogicalKeyboardKey.keyV, control: true): () =>
                                                  handleSmartSpreadsheetPaste(index),
                                              const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () =>
                                                  handleSmartSpreadsheetPaste(index),
                                            },
                                            child: TextField(
                                              controller: staticOptionControllers[index],
                                              decoration: InputDecoration(
                                                labelText: 'Option ${index + 1}',
                                                border: const OutlineInputBorder(),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle, color: Colors.red, size: 22),
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton.icon(
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text("Add Option Line"),
                                onPressed: () => setModalState(() => staticOptionControllers.add(TextEditingController())),
                              ),
                              // ADDED: Toggle Switch to support dynamic write-in textbox answers
                              Flexible(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      "Include 'Other' input field",
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                    ),
                                    const SizedBox(width: 4),
                                    Switch(
                                      value: allowOtherOption,
                                      activeThumbColor: const Color(0xff00afef),
                                      onChanged: (value) => setModalState(() => allowOtherOption = value),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (sourceOptionType == 'database') ...[
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: selectedTable,
                            decoration: const InputDecoration(
                              labelText: 'Target Lookup Table',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'clusters', child: Text("Clusters (name)")),
                              DropdownMenuItem(value: 'villages', child: Text("Villages (name)")),
                              DropdownMenuItem(value: 'schools', child: Text("Schools (name)")),
                              DropdownMenuItem(value: 'profiles', child: Text("Profiles (Name Structure)")),
                            ],
                            onChanged: (val) => setModalState(() {
                              if (val != null) selectedTable = val;
                            }),
                          ),
                        ],
                      ],
                      const Divider(height: 28),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.alt_route, color: Colors.blueGrey, size: 20),
                                const SizedBox(width: 8),
                                const Text(
                                  "Conditional Visibility (Skip Logic)",
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey),
                                ),
                                const Spacer(),
                                Switch(
                                  value: enableSkipLogic,
                                  onChanged: (val) => setModalState(() => enableSkipLogic = val),
                                  activeThumbColor: const Color(0xff00afef),
                                ),
                              ],
                            ),
                            if (enableSkipLogic) ...[
                              const SizedBox(height: 10),
                              const Text(
                                "Show this question only if...",
                                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.black54),
                              ),
                              const SizedBox(height: 8),
                              filtratedPriorQuestions.isEmpty
                                  ? const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 8.0),
                                      child: Text(
                                        "No prior questions available to depend on.",
                                        style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.w500),
                                      ),
                                    )
                                  : Column(
                                      children: [
                                        DropdownButtonFormField<String>(
                                          initialValue:
                                              filtratedPriorQuestions.any(
                                                (element) => element['id'].toString() == selectedDependentQuestionId,
                                              )
                                              ? selectedDependentQuestionId
                                              : null,
                                          decoration: const InputDecoration(
                                            labelText: 'Select Prior Question',
                                            border: OutlineInputBorder(),
                                            contentPadding: EdgeInsets.symmetric(horizontal: 10),
                                          ),
                                          items: filtratedPriorQuestions.map((q) {
                                            return DropdownMenuItem<String>(
                                              value: q['id'].toString(),
                                              child: Text(
                                                q['question'] ?? '',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 13),
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (val) => setModalState(() => selectedDependentQuestionId = val),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              flex: 3,
                                              child: DropdownButtonFormField<String>(
                                                initialValue: skipOperator,
                                                decoration: const InputDecoration(
                                                  labelText: 'Condition',
                                                  border: OutlineInputBorder(),
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 10),
                                                ),
                                                items: const [
                                                  DropdownMenuItem(value: 'equals', child: Text("Matches (=)")),
                                                  DropdownMenuItem(value: 'not_equals', child: Text("Does Not Match (≠)")),
                                                  DropdownMenuItem(value: 'filled', child: Text("Is Answered")),
                                                ],
                                                onChanged: (val) => setModalState(() => skipOperator = val ?? 'equals'),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (skipOperator != 'filled')
                                              Expanded(
                                                flex: 4,
                                                child: TextField(
                                                  controller: skipValueController,
                                                  decoration: const InputDecoration(
                                                    labelText: 'Value to match',
                                                    border: OutlineInputBorder(),
                                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
                      enableSkipLogic: enableSkipLogic,
                      dependentQuestionId: selectedDependentQuestionId,
                      skipOperator: skipOperator,
                      skipValue: skipValueController.text.trim(),
                      editIndex: editIndex,
                      existingId: isEditing ? existingQuestion['id']?.toString() : null,
                      allowOther: allowOtherOption, // PASSED DOWN
                    );
                    Navigator.pop(context);
                  },
                  child: Text(isEditing ? "Save Changes" : "Add Field", style: const TextStyle(color: Colors.white)),
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
    required bool enableSkipLogic,
    required String? dependentQuestionId,
    required String skipOperator,
    required String skipValue,
    int? editIndex,
    String? existingId,
    bool allowOther = false, // ADDED
  }) {
    final Map<String, dynamic> configBlock = {'type': type};

    if (type == 'radio' || type == 'checkbox_search') {
      configBlock['allow_other'] = allowOther; // PERSISTED INTO FIELD_CONFIG
      if (sourceType == 'static' || sourceType == 'excel') {
        final options = staticControllers.map((c) => c.text.trim()).where((text) => text.isNotEmpty).toList();
        configBlock['options'] = options.isNotEmpty ? options : ['Default Option'];
        configBlock['source_meta'] = sourceType;
      } else {
        final Map<String, dynamic> datasourcePayload = {'table': tableName, 'value_column': 'id'};
        datasourcePayload['label_column'] = 'name';
        configBlock['datasource'] = datasourcePayload;
      }
    }

    if (enableSkipLogic && dependentQuestionId != null) {
      configBlock['skip_logic'] = {
        'enabled': true,
        'dependent_question_id': dependentQuestionId,
        'operator': skipOperator,
        'value': skipOperator == 'filled' ? '' : skipValue,
      };
    } else {
      configBlock['skip_logic'] = {'enabled': false};
    }

    final Map<String, dynamic> targetQuestionRow = {
      'id': existingId ?? 'new_${DateTime.now().millisecondsSinceEpoch}',
      'question': labelText,
      'section': section.isEmpty ? 'General' : section,
      'required': required,
      'field_config': configBlock,
    };

    setState(() {
      if (editIndex != null) {
        _currentQuestions[editIndex] = targetQuestionRow;
      } else {
        _currentQuestions.add(targetQuestionRow);
      }
    });
  }

  void _removeQuestionFromCanvas(int elementIndex) {
    final targetQuestion = _currentQuestions[elementIndex];
    final String targetId = (targetQuestion['id'] ?? '').toString();

    setState(() {
      if (targetId.isNotEmpty && !targetId.startsWith('new_')) {
        _deletedQuestionIds.add(targetId);
      }
      _currentQuestions.removeAt(elementIndex);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titleController.text, style: const TextStyle(color: Colors.white)),
        backgroundColor: AppTheme.primaryBlue,
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
                            final hasSkip = q['field_config']?['skip_logic']?['enabled'] ?? false;
                            final isOtherEnabled = q['field_config']?['allow_other'] ?? false;
                            final String fieldType = q['field_config']?['type'] ?? 'text';

                            return Card(
                              key: ValueKey(q['id'] ?? 'index_$idx'),
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              child: ListTile(
                                leading: const Icon(Icons.drag_indicator, color: Colors.grey),
                                title: Text(q['question'] ?? ''),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Section: ${q['section']} | Type: $fieldType ${isOtherEnabled ? '(+ Write-in Other)' : ''}",
                                    ),
                                    if (hasSkip)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4.0),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.alt_route, size: 14, color: Colors.purple),
                                            const SizedBox(width: 4),
                                            Text(
                                              "Conditional Skip Enabled",
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.purple.shade700,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_note, color: Color(0xff00afef)),
                                      onPressed: () =>
                                          _showConfigureQuestionDialog(type: fieldType, existingQuestion: q, editIndex: idx),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                      onPressed: () => _removeQuestionFromCanvas(idx),
                                    ),
                                  ],
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
            Expanded(child: _toolButton("Text", Icons.text_fields, () => _showConfigureQuestionDialog(type: 'text'))),
            Expanded(child: _toolButton("Radio", Icons.radio_button_checked, () => _showConfigureQuestionDialog(type: 'radio'))),
            Expanded(
              child: _toolButton(
                "Check box",
                Icons.check_box_outlined,
                () => _showConfigureQuestionDialog(type: 'checkbox_search'),
              ),
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
