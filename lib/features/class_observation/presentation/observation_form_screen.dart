import 'package:flutter/material.dart';

import '../../../core/models/dynamic_form_model.dart';
import '../../../core/models/form_question_model.dart';
// Import your unified location service here
import '../../../core/services/location_service.dart';
import '../../../core/widgets/dynamic_form_renderer.dart';
import '../../../features/forms/data/form_repository.dart';

class ObservationFormScreen extends StatefulWidget {
  const ObservationFormScreen({super.key});

  @override
  State<ObservationFormScreen> createState() => _ObservationFormScreenState();
}

class _ObservationFormScreenState extends State<ObservationFormScreen> {
  final DynamicFormController _formController = DynamicFormController();
  final FormRepository _repository = FormRepository();
  late final DynamicForm _mockForm;

  @override
  void initState() {
    super.initState();
    // Setting up a dummy form layout to test with
    _mockForm = DynamicForm(
      id: 'observation_form_01',
      title: 'Classroom Observation',
      questions: [
        FormQuestion(
          id: 'q_teacher_status',
          type: 'radio',
          options: ['Present', 'Absent'],
          label: 'Is the assigned teacher present?',
        ),
        FormQuestion(id: 'q_notes', type: 'text', label: 'Observation Summary Notes'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_mockForm.title)),
      body: SingleChildScrollView(
        child: DynamicFormRenderer(
          controller: _formController,
          form: _mockForm,
          userId: '00000000-0000-0000-0000-000000000000',
          onFetchDynamicOptions: _repository.fetchDynamicOptions,

          // ====================================================
          // THIS IS EXACTLY WHERE THE GPS CODE GOES:
          // ====================================================
          onGetGPSLocation: () async {
            final position = await LocationService.getCurrentPosition();
            if (position == null) return null;
            return {'latitude': position.latitude, 'longitude': position.longitude};
          },

          // ====================================================
          onSubmit: (formResponse) async {
            try {
              await _repository.submitFormResponse(formResponse.answers, formResponse.formId, formResponse.userId);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Observation uploaded successfully!')));
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Submission failed: $e')));
              }
            }
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: () {
              _formController.submit();
            },
            child: const Text('Submit Records', style: TextStyle(fontSize: 16)),
          ),
        ),
      ),
    );
  }
}
