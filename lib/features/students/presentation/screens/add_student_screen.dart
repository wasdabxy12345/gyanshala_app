import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controller/student_controller.dart';

class AddStudentScreen extends ConsumerStatefulWidget {
  const AddStudentScreen({super.key});

  @override
  ConsumerState<AddStudentScreen> createState() => _AddStudentScreenState();
}

class _AddStudentScreenState extends ConsumerState<AddStudentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _idController = TextEditingController();

  // These variables still hold the "current" selection
  String _selectedGender = 'Male';
  int _selectedGrade = 1;

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(studentProvider);

    return Scaffold(
      appBar: AppBar(title: const Text("Register Student")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Full Name",
                  border: OutlineInputBorder(),
                ),
                validator: (val) => val!.isEmpty ? "Enter full name" : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _idController,
                decoration: const InputDecoration(
                  labelText: "Student ID",
                  border: OutlineInputBorder(),
                ),
                validator: (val) => val!.isEmpty ? "Enter student ID" : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedGender,
                items: ['Male', 'Female', 'Other']
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (val) => setState(() => _selectedGender = val!),
                decoration: const InputDecoration(
                  labelText: "Gender",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _selectedGrade,
                items: List.generate(10, (index) => index + 1)
                    .map(
                      (g) =>
                          DropdownMenuItem(value: g, child: Text("Grade $g")),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _selectedGrade = val!),
                decoration: const InputDecoration(
                  labelText: "Grade",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _submitForm,
                  child: isLoading
                      ? const CircularProgressIndicator()
                      : const Text("Save Student"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submitForm() async {
    if (_formKey.currentState!.validate()) {
      final success = await ref
          .read(studentProvider.notifier)
          .registerStudent(
            name: _nameController.text,
            studentId: _idController.text,
            gender: _selectedGender,
            grade: _selectedGrade,
            village:
                "Auto-Village", // You can later pull this from the Mentor's Profile
            cluster: "Auto-Cluster",
            school: "Auto-School",
          );

      if (success && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Student Registered!")));
        Navigator.pop(context);
      }
    }
  }
}
