import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gyanshala_app/core/services/location_service.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FormFillerScreen extends StatefulWidget {
  final String formId;
  final String formTitle;

  const FormFillerScreen({super.key, required this.formId, required this.formTitle});

  @override
  State<FormFillerScreen> createState() => _FormFillerScreenState();
}

class _FormFillerScreenState extends State<FormFillerScreen> {
  final _rootFormKey = GlobalKey<FormState>();

  final List<Map<String, dynamic>> _questions = [];
  final Map<String, dynamic> _formAnswers = {};
  final Map<String, List<String>> _resolvedOptions = {};

  final PageController _pageController = PageController();
  int _currentPageIndex = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFormStructure();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadFormStructure() async {
    try {
      final supabase = Supabase.instance.client;
      final data = await supabase
          .from('form_questions')
          .select('*')
          .eq('form_id', widget.formId)
          .order('sort_order', ascending: true);

      final List<Map<String, dynamic>> fetchedQuestions = List<Map<String, dynamic>>.from(data);

      for (var question in fetchedQuestions) {
        final config = question['field_config'] as Map<String, dynamic>? ?? {};
        final qId = question['id'].toString();

        if (config['type'] == 'radio' || config['type'] == 'checkbox_search') {
          if (config.containsKey('options')) {
            _resolvedOptions[qId] = List<String>.from(config['options']);
          } else if (config.containsKey('datasource')) {
            _resolvedOptions[qId] = await _fetchDropdownLookup(config['datasource']);
          }
        }
      }

      setState(() {
        _questions.addAll(fetchedQuestions);
        _isLoading = false;
      });
    } catch (e) {
      _showSnackbar("Failed to construct layout: $e", Colors.red);
      setState(() => _isLoading = false);
    }
  }

  Future<List<String>> _fetchDropdownLookup(Map<String, dynamic> ds) async {
    try {
      final supabase = Supabase.instance.client;
      final String tableName = ds['table'];

      if (tableName == 'profiles') {
        var query = supabase.from('profiles').select('first_name, last_name');
        if (ds.containsKey('filter_column') && ds.containsKey('filter_value')) {
          query = query.eq(ds['filter_column'], ds['filter_value']);
        }
        final res = await query;
        return res.map((r) => "${r['first_name'] ?? ''} ${r['last_name'] ?? ''}".trim()).toList();
      } else {
        final String labelCol = ds['label_column'] ?? 'name';
        final res = await supabase.from(tableName).select(labelCol).order(labelCol);
        return res.map((r) => r[labelCol].toString()).toList();
      }
    } catch (e) {
      return ['Error fetching lookups'];
    }
  }

  bool _shouldShowQuestion(Map<String, dynamic> question) {
    final String currentSection = question['section'] ?? 'General';
    final firstQuestionOfSection = _questions.firstWhere((q) => (q['section'] ?? 'General') == currentSection, orElse: () => {});
    if (firstQuestionOfSection.isNotEmpty) {
      final firstConfig = firstQuestionOfSection['field_config'] as Map<String, dynamic>? ?? {};
      final sectionSkip = firstConfig['section_skip_logic'] as Map<String, dynamic>?;
      if (sectionSkip != null && sectionSkip['enabled'] == true) {
        final bool sectionIsVisible = _evaluateLogicCondition(
          dependentQuestionId: sectionSkip['dependent_question_id']?.toString(),
          operator: sectionSkip['operator'],
          targetValue: sectionSkip['value']?.toString(),
        );
        if (!sectionIsVisible) return false;
      }
    }
    final config = question['field_config'] as Map<String, dynamic>? ?? {};
    final skipLogic = config['skip_logic'] as Map<String, dynamic>?;
    if (skipLogic == null || skipLogic['enabled'] != true) {
      return true;
    }
    return _evaluateLogicCondition(
      dependentQuestionId: skipLogic['dependent_question_id']?.toString(),
      operator: skipLogic['operator'],
      targetValue: skipLogic['value']?.toString(),
    );
  }

  bool _evaluateLogicCondition({required String? dependentQuestionId, required dynamic operator, required String? targetValue}) {
    if (dependentQuestionId == null) return true;

    final targetLower = targetValue?.toLowerCase().trim() ?? '';
    final rawAnswer = _formAnswers[dependentQuestionId];
    final currentAnswerStr = rawAnswer?.toString().toLowerCase().trim() ?? '';

    switch (operator) {
      case 'filled':
        if (rawAnswer is List) return rawAnswer.isNotEmpty;
        return currentAnswerStr.isNotEmpty && currentAnswerStr != 'null';
      case 'not_equals':
        if (rawAnswer is List) return !rawAnswer.map((e) => e.toString().toLowerCase().trim()).contains(targetLower);
        return currentAnswerStr != targetLower;
      case 'equals':
      default:
        if (rawAnswer is List) return rawAnswer.map((e) => e.toString().toLowerCase().trim()).contains(targetLower);
        return currentAnswerStr == targetLower;
    }
  }

  void _handleNextStep() {
    if (_rootFormKey.currentState != null && _rootFormKey.currentState!.validate()) {
      _rootFormKey.currentState!.save();

      int nextIndex = _currentPageIndex + 1;
      final List<String> fieldsToClear = [];
      while (nextIndex < _questions.length && !_shouldShowQuestion(_questions[nextIndex])) {
        fieldsToClear.add(_questions[nextIndex]['id'].toString());
        nextIndex++;
      }

      if (nextIndex <= _questions.length) {
        setState(() {
          for (var skippedId in fieldsToClear) {
            _formAnswers.remove(skippedId);
            _formAnswers.remove("${skippedId}_other_text");
          }

          if (nextIndex < _questions.length) {
            _currentPageIndex = nextIndex;
            _pageController.animateToPage(nextIndex, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
          } else {
            _submitFormEntries();
          }
        });
      }
    }
  }

  void _handlePreviousStep() {
    _rootFormKey.currentState?.reset();

    int prevIndex = _currentPageIndex - 1;
    while (prevIndex >= 0 && !_shouldShowQuestion(_questions[prevIndex])) {
      prevIndex--;
    }

    if (prevIndex >= 0) {
      setState(() {
        _currentPageIndex = prevIndex;
        _pageController.animateToPage(prevIndex, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      });
    }
  }

  Future<void> _submitFormEntries() async {
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception("Authentication session expired.");
      LocationPermission checkPermission = await Geolocator.checkPermission();
      if (checkPermission == LocationPermission.denied) {
        checkPermission = await Geolocator.requestPermission();
      }
      if (checkPermission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _isLoading = false);
          _showLocationRequiredDialog(isPermanent: true);
        }
        return;
      }
      if (checkPermission == LocationPermission.denied) {
        if (mounted) {
          setState(() => _isLoading = false);
          _showLocationRequiredDialog(isPermanent: false);
        }
        return;
      }
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() => _isLoading = false);
          _showHardwareGpsRequiredDialog();
          _showSnackbar("Please turn on your phone's GPS/Location service switcher.", Colors.yellow);
        }
        return;
      }
      double? lat;
      double? lng;

      try {
        final position = await LocationService.getCurrentPosition();
        if (position != null) {
          lat = position.latitude;
          lng = position.longitude;
        }
      } catch (e) {
        debugPrint("GPS capture failed: $e");
      }
      if (lat == null || lng == null) {
        if (mounted) {
          setState(() => _isLoading = false);
          _showLocationRequiredDialog(isPermanent: false);
        }
        return;
      }

      await supabase.from('form_responses').insert({
        'form_id': widget.formId,
        'user_id': userId,
        'responses': _formAnswers,
        'latitude': lat,
        'longitude': lng,
      });

      _showSnackbar("Evaluation submitted successfully!", Colors.green);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showSnackbar("Submission failed: $e", Colors.red);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackbar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    bool isLastCalculatedPage = true;
    for (int i = _currentPageIndex + 1; i < _questions.length; i++) {
      if (_shouldShowQuestion(_questions[i])) {
        isLastCalculatedPage = false;
        break;
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.formTitle),
        bottom: _isLoading || _questions.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(6),
                child: LinearProgressIndicator(
                  value: _questions.isEmpty ? 0 : (_currentPageIndex + 1) / _questions.length,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue))
          : _questions.isEmpty
          ? const Center(child: Text("This form contains no questions."))
          : Form(
              key: _rootFormKey,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Section: ${_questions[_currentPageIndex]['section'] ?? 'General'}",
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                        ),
                        Text(
                          "Question ${_currentPageIndex + 1} of ${_questions.length}",
                          style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.primaryBlue),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: (idx) => setState(() => _currentPageIndex = idx),
                      itemCount: _questions.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: SingleChildScrollView(
                                key: ValueKey('scroll_${_questions[index]['id']}'),
                                child: _buildDynamicField(_questions[index]),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  _buildBottomNavigationBar(isLastCalculatedPage),
                ],
              ),
            ),
    );
  }

  Widget _buildBottomNavigationBar(bool isLastPage) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (_currentPageIndex > 0)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: OutlinedButton.icon(
                    onPressed: _handlePreviousStep,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text("Back"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      side: BorderSide(color: Colors.grey.shade400),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              )
            else
              const SizedBox.shrink(),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: _currentPageIndex > 0 ? 8.0 : 0.0),
                child: ElevatedButton.icon(
                  onPressed: _handleNextStep,
                  icon: Icon(isLastPage ? Icons.check_circle : Icons.arrow_forward, color: Colors.white),
                  label: Text(
                    isLastPage ? "Submit Data" : "Next",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isLastPage ? Colors.green : AppTheme.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicField(Map<String, dynamic> q) {
    final String qId = q['id'].toString();
    final String label = q['question'] ?? '';
    final bool isRequired = q['required'] ?? false;
    final config = q['field_config'] as Map<String, dynamic>? ?? {};
    final String type = config['type'] ?? 'text';
    final bool allowOther = config['allow_other'] ?? false;
    const String otherChoiceString = "Other (Please specify)";
    final fieldLabel = Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Wrap(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          if (isRequired) const Text(" *", style: TextStyle(color: Colors.red, fontSize: 18)),
        ],
      ),
    );
    switch (type) {
      case 'text':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          key: ValueKey('text_container_$qId'),
          children: [
            fieldLabel,
            TextFormField(
              key: ValueKey('text_field_$qId'),
              initialValue: _formAnswers[qId],
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: "Type your answer here...",
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFFFAFAFA),
              ),
              validator: (val) => isRequired && (val == null || val.trim().isEmpty) ? 'This field is required' : null,
              onSaved: (val) => _formAnswers[qId] = val?.trim(),
            ),
          ],
        );
      case 'radio':
        final rawOptions = _resolvedOptions[qId] ?? [];
        final List<String> options = List<String>.from(rawOptions);
        if (allowOther && !options.contains(otherChoiceString)) {
          options.add(otherChoiceString);
        }
        final String otherTextKey = "${qId}_other_text";
        return FormField<String>(
          key: ValueKey('radio_formfield_$qId'),
          initialValue: _formAnswers[qId],
          validator: (val) {
            if (isRequired && val == null) return 'Please select an option to proceed';
            if (val == otherChoiceString) {
              final textVal = _formAnswers[otherTextKey]?.toString().trim();
              if (textVal == null || textVal.isEmpty) return 'Please specify your other answer';
            }
            return null;
          },
          onSaved: (val) {
            if (val == otherChoiceString) {
              _formAnswers[qId] = _formAnswers[otherTextKey]?.toString().trim() ?? otherChoiceString;
            } else {
              _formAnswers[qId] = val;
            }
          },
          builder: (FormFieldState<String> state) {
            final isOtherSelected = state.value == otherChoiceString;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                fieldLabel,
                RadioGroup<String>(
                  groupValue: state.value,
                  onChanged: (String? val) {
                    state.didChange(val);
                    if (val == otherChoiceString) {
                      _formAnswers[qId] = _formAnswers[otherTextKey] ?? '';
                    } else {
                      _formAnswers[qId] = val;
                    }
                  },
                  child: Column(
                    children: options.map((opt) {
                      return Card(
                        key: ValueKey('radio_card_${qId}_$opt'),
                        color: state.value == opt ? AppTheme.lightBlue : Colors.white,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(color: state.value == opt ? AppTheme.primaryBlue : Colors.grey.shade300),
                        ),
                        child: RadioListTile<String>(
                          title: Text(opt, style: const TextStyle(fontWeight: FontWeight.w500)),
                          value: opt,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                if (isOtherSelected)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                    child: TextFormField(
                      key: ValueKey('radio_other_input_$qId'),
                      initialValue: _formAnswers[otherTextKey],
                      decoration: const InputDecoration(
                        labelText: "Please specify custom response *",
                        hintText: "Type details here...",
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      onChanged: (text) {
                        _formAnswers[otherTextKey] = text;
                      },
                    ),
                  ),
                if (state.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 4),
                    child: Text(state.errorText ?? '', style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ),
              ],
            );
          },
        );
      case 'checkbox_search':
        final rawOptions = _resolvedOptions[qId] ?? [];
        final List<String> options = List<String>.from(rawOptions);
        if (allowOther && !options.contains(otherChoiceString)) {
          options.add(otherChoiceString);
        }

        _formAnswers[qId] ??= <String>[];
        final String otherTextKey = "${qId}_other_text";

        return FormField<List<String>>(
          key: ValueKey('checkbox_formfield_$qId'),
          initialValue: List<String>.from(_formAnswers[qId]),
          validator: (val) {
            if (isRequired && (val == null || val.isEmpty)) return 'Please choose at least one';
            if (val != null && val.contains(otherChoiceString)) {
              final textVal = _formAnswers[otherTextKey]?.toString().trim();
              if (textVal == null || textVal.isEmpty) return 'Please specify your other choices';
            }
            return null;
          },
          onSaved: (val) {
            if (val != null) {
              final savedList = List<String>.from(val);
              if (savedList.contains(otherChoiceString)) {
                savedList.remove(otherChoiceString);
                final customWriteIn = _formAnswers[otherTextKey]?.toString().trim() ?? '';
                if (customWriteIn.isNotEmpty) savedList.add("Other: $customWriteIn");
              }
              _formAnswers[qId] = savedList;
            }
          },
          builder: (FormFieldState<List<String>> state) {
            final selectedItems = state.value ?? [];
            final isOtherSelected = selectedItems.contains(otherChoiceString);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                fieldLabel,
                const Text("Select all that apply:", style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 12),
                Column(
                  children: options.map((opt) {
                    final isChecked = selectedItems.contains(opt);
                    return Card(
                      key: ValueKey('checkbox_card_${qId}_$opt'),
                      color: isChecked ? const Color(0xFFE6F7FF) : Colors.white,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: isChecked ? AppTheme.primaryBlue : Colors.grey.shade300),
                      ),
                      child: CheckboxListTile(
                        title: Text(opt, style: const TextStyle(fontWeight: FontWeight.w500)),
                        value: isChecked,
                        controlAffinity: ListTileControlAffinity.trailing,
                        activeColor: AppTheme.primaryBlue,
                        onChanged: (bool? checked) {
                          final updatedList = List<String>.from(selectedItems);
                          if (checked == true) {
                            updatedList.add(opt);
                          } else {
                            updatedList.remove(opt);
                          }
                          state.didChange(updatedList);
                          _formAnswers[qId] = updatedList;
                        },
                      ),
                    );
                  }).toList(),
                ),
                if (isOtherSelected)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                    child: TextFormField(
                      key: ValueKey('checkbox_other_input_$qId'),
                      initialValue: _formAnswers[otherTextKey],
                      decoration: const InputDecoration(
                        labelText: "Please specify custom details *",
                        hintText: "Type details here...",
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      onChanged: (text) {
                        _formAnswers[otherTextKey] = text;
                      },
                    ),
                  ),
                if (state.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 4),
                    child: Text(state.errorText ?? '', style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ),
              ],
            );
          },
        );

      default:
        return const SizedBox.shrink();
    }
  }

  void _showLocationRequiredDialog({required bool isPermanent}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.location_off, color: Colors.red, size: 28),
            Spacer(),
            Text("Location Needed", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          isPermanent
              ? "You have permanently disabled location access for Gyanshala. Please open your device settings to re-enable it manually."
              : "Gyanshala needs location permission to verify school visits. Please allow access when the system popup appears.",
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          if (isPermanent)
            TextButton.icon(
              icon: const Icon(Icons.settings, size: 16),
              label: const Text("Open Settings"),
              onPressed: () async {
                await Geolocator.openAppSettings();
              },
            )
          else
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
              onPressed: () async {
                Navigator.pop(context);
                _submitFormEntries();
              },
              child: const Text("Grant Permission", style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
    );
  }

  void _showHardwareGpsRequiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.gps_off, color: Colors.yellow, size: 28),
            Spacer(),
            Text("GPS Switched Off", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text("Your phone's GPS is off. Please turn it on.", style: TextStyle(fontSize: 14, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.location_searching, size: 16, color: Colors.white),
            label: const Text("Turn On GPS", style: TextStyle(color: Colors.white)),
            onPressed: () async {
              Navigator.pop(context);
              await Geolocator.openLocationSettings();
            },
          ),
        ],
      ),
    );
  }
}
