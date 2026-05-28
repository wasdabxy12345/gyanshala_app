import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';

import '../models/dynamic_form_model.dart';
import '../models/form_question_model.dart';
import '../models/form_response_model.dart';

// =========================================================================
// ADDED THIS CLASS: This acts as the bridge so your screen can trigger submit
// =========================================================================
class DynamicFormController {
  Future<void> Function()? _submitCallback;

  void submit() {
    _submitCallback?.call();
  }
}

class DynamicFormRenderer extends StatefulWidget {
  final DynamicForm form;
  final String userId;
  // ADDED PARAMETER: Exposing the controller to the screen
  final DynamicFormController? controller;
  final Future<Map<String, String>> Function(DataSourceRule) onFetchDynamicOptions;
  final Future<Map<String, double>?> Function() onGetGPSLocation;
  final Function(FormResponse) onSubmit;

  const DynamicFormRenderer({
    super.key,
    required this.form,
    required this.userId,
    this.controller, // Added parameter
    required this.onFetchDynamicOptions,
    required this.onGetGPSLocation,
    required this.onSubmit,
  });

  @override
  State<DynamicFormRenderer> createState() => _DynamicFormRendererState();
}

class _DynamicFormRendererState extends State<DynamicFormRenderer> {
  final _formKey = GlobalKey<FormState>();

  // Tracks user answers: { "q1": "Yes", "q2": "Tesla", "q3": ["Autopilot", "Electric"] }
  final Map<String, dynamic> _userAnswers = {};

  // Cache for dynamic database options to prevent endless reloading loops
  final Map<String, Map<String, String>> _dynamicOptionsCache = {};

  // =========================================================================
  // ADDED INITSTATE: Binds the incoming controller to the local submit method
  // =========================================================================
  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      widget.controller!._submitCallback = submitCurrentForm;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView.builder(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        itemCount: widget.form.questions.length,
        itemBuilder: (context, index) {
          final question = widget.form.questions[index];

          // Conditional Rule Assessment
          if (!_isConditionMet(question.conditional)) {
            // If condition fails, remove any previous answer so hidden child questions clear out
            _userAnswers.remove(question.id);
            return const SizedBox.shrink();
          }

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(question.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildQuestionInput(question),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Evaluates whether a question should be visible
  bool _isConditionMet(ConditionalRule? rule) {
    if (rule == null) return true;
    final parentAnswer = _userAnswers[rule.dependsOn];

    if (parentAnswer is List) {
      return parentAnswer.contains(rule.equals);
    }
    return parentAnswer?.toString() == rule.equals;
  }

  /// Decides which field widget type to render
  Widget _buildQuestionInput(FormQuestion question) {
    switch (question.type) {
      case 'text':
        return TextFormField(
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Type your answer here...'),
          validator: (value) => value == null || value.isEmpty ? 'This field is required' : null,
          onChanged: (value) {
            setState(() {
              _userAnswers[question.id] = value;
            });
          },
        );

      case 'radio':
        return _buildRadioGroup(question);

      case 'checkbox_search':
        return _buildCheckboxSearch(question);

      default:
        return const Text('Unsupported field type');
    }
  }

  /// Builds Radio Button lists wrapped inside modern RadioGroup parents
  Widget _buildRadioGroup(FormQuestion question) {
    if (question.options != null) {
      return RadioGroup<String>(
        groupValue: _userAnswers[question.id]?.toString(),
        onChanged: (val) {
          setState(() {
            _userAnswers[question.id] = val;
          });
        },
        child: Column(
          children: question.options!.map((option) {
            return RadioListTile<String>(title: Text(option), value: option);
          }).toList(),
        ),
      );
    }

    if (question.datasource != null) {
      return _buildDynamicLoader(
        rule: question.datasource!,
        builder: (options) {
          return RadioGroup<String>(
            groupValue: _userAnswers[question.id]?.toString(),
            onChanged: (val) {
              setState(() {
                _userAnswers[question.id] = val;
              });
            },
            child: Column(
              children: options.entries.map((entry) {
                return RadioListTile<String>(
                  title: Text(entry.value), // Display label
                  value: entry.key, // Underlying system key
                );
              }).toList(),
            ),
          );
        },
      );
    }
    return const Text('No options defined');
  }

  /// Builds a Searchable Multiselect Checkbox matching version 6 properties
  Widget _buildCheckboxSearch(FormQuestion question) {
    if (question.options != null) {
      final List<String> currentSelections = List<String>.from(_userAnswers[question.id] ?? []);
      return DropdownSearch<String>.multiSelection(
        items: (filter, infiniteScrollProps) => question.options!,
        selectedItems: currentSelections,
        popupProps: const MultiSelectionPopupProps.menu(
          showSearchBox: true,
          searchFieldProps: TextFieldProps(decoration: InputDecoration(hintText: 'Search options...')),
        ),
        onSelected: (List<String> selected) {
          setState(() {
            _userAnswers[question.id] = selected;
          });
        },
      );
    }

    if (question.datasource != null) {
      return _buildDynamicLoader(
        rule: question.datasource!,
        builder: (options) {
          final List<String> currentKeysSelected = List<String>.from(_userAnswers[question.id] ?? []);

          return DropdownSearch<String>.multiSelection(
            items: (filter, infiniteScrollProps) => options.keys.toList(),
            selectedItems: currentKeysSelected,
            itemAsString: (key) => options[key] ?? '',
            popupProps: const MultiSelectionPopupProps.menu(
              showSearchBox: true,
              searchFieldProps: TextFieldProps(decoration: InputDecoration(hintText: 'Search database records...')),
            ),
            onSelected: (List<String> selectedKeys) {
              setState(() {
                _userAnswers[question.id] = selectedKeys;
              });
            },
          );
        },
      );
    }
    return const Text('No data source configuration set');
  }

  /// FutureBuilder helper to fetch external Supabase reference items cleanly
  Widget _buildDynamicLoader({required DataSourceRule rule, required Widget Function(Map<String, String>) builder}) {
    final cacheKey = '${rule.table}_${rule.valueColumn}_${rule.labelColumn}';
    if (_dynamicOptionsCache.containsKey(cacheKey)) {
      return builder(_dynamicOptionsCache[cacheKey]!);
    }

    return FutureBuilder<Map<String, String>>(
      future: widget.onFetchDynamicOptions(rule),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(padding: EdgeInsets.all(8.0), child: LinearProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Text('Failed to populate dropdown options from database.');
        }

        _dynamicOptionsCache[cacheKey] = snapshot.data!;
        return builder(snapshot.data!);
      },
    );
  }

  /// Call this method from an external button widget via a GlobalKey/callback layer
  Future<void> submitCurrentForm() async {
    if (!_formKey.currentState!.validate()) return;

    // Trigger automated GPS fetch
    final gpsData = await widget.onGetGPSLocation();

    final finalResponse = FormResponse(
      formId: widget.form.id,
      userId: widget.userId,
      answers: _userAnswers,
      latitude: gpsData?['latitude'],
      longitude: gpsData?['longitude'],
    );

    widget.onSubmit(finalResponse);
  }
}
