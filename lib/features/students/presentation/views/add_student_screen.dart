import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/features/students/controller/student_controller.dart';
import 'package:gyanshala_app/features/students/presentation/widgets/conflict_workspace_dialog.dart';

class AddStudentScreen extends ConsumerStatefulWidget {
  const AddStudentScreen({super.key});

  @override
  ConsumerState<AddStudentScreen> createState() => _AddStudentScreenState();
}

class _AddStudentScreenState extends ConsumerState<AddStudentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _idController = TextEditingController();

  String _selectedGender = 'Male';
  int _selectedGrade = 1;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(studentProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Register Student')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstNameController,
                      decoration: const InputDecoration(labelText: 'First Name', border: OutlineInputBorder()),
                      validator: (val) => val == null || val.isEmpty ? 'Enter first name' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _lastNameController,
                      decoration: const InputDecoration(labelText: 'Last Name', border: OutlineInputBorder()),
                      validator: (val) => val == null || val.isEmpty ? 'Enter last name' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _idController,
                decoration: const InputDecoration(labelText: 'Student ID', border: OutlineInputBorder()),
                validator: (val) => val == null || val.isEmpty ? 'Enter student ID' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedGender,
                items: ['Male', 'Female', 'Other'].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                onChanged: (val) => setState(() => _selectedGender = val!),
                decoration: const InputDecoration(labelText: 'Gender', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _selectedGrade,
                items: [
                  const DropdownMenuItem(value: 0, child: Text('Balvatika (BV)')),
                  ...List.generate(10, (index) => index + 1).map((g) => DropdownMenuItem(value: g, child: Text('$g'))),
                ],
                onChanged: (val) => setState(() => _selectedGrade = val!),
                decoration: const InputDecoration(labelText: 'Grade', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.center,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _submitForm,
                  child: isLoading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save Student'),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        label: const Text("Import Excel"),
        icon: const Icon(Icons.upload_file),
        onPressed: isLoading ? null : _handleExcelImport,
      ),
    );
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    final success = await ref
        .read(studentProvider.notifier)
        .registerStudent(
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          studentId: _idController.text.trim(),
          gender: _selectedGender,
          grade: _selectedGrade,
        );
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Student Registered!')));
      Navigator.pop(context, true);
    }
  }

  Future<void> _handleExcelImport() async {
    try {
      await ref.read(studentProvider.notifier).importStudentsFromExcel();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import successful!')));
    } catch (e) {
      String msg = e.toString();
      if (msg.contains("CONFLICT:")) {
        final conflictString = msg.substring(msg.indexOf("CONFLICT:") + 9);

        final parts = conflictString.split("|");
        if (parts.length < 3) return;

        jsonDecode(parts.sublist(2).join("|"));

        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => ConflictWorkspaceDialog(conflictRawString: msg),
        );
      }
    }
  }
}
