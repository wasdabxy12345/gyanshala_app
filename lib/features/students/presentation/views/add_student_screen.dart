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

  String? _selectedClusterId;
  String? _selectedVillageId;
  String? _selectedSchoolId;

  List<Map<String, dynamic>> _clusters = [];
  List<Map<String, dynamic>> _villages = [];
  List<Map<String, dynamic>> _schools = [];

  bool _isLoadingLocations = false;

  @override
  void initState() {
    super.initState();
    _loadClusters();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  Future<void> _loadClusters() async {
    setState(() => _isLoadingLocations = true);
    try {
      final clusters = await ref.read(studentProvider.notifier).getClusters();
      setState(() {
        _clusters = clusters;
      });
    } catch (e) {
      _showErrorSnackBar('Failed to load clusters: ${e.toString()}');
    } finally {
      setState(() => _isLoadingLocations = false);
    }
  }

  Future<void> _onClusterChanged(String? clusterId) async {
    setState(() {
      _selectedClusterId = clusterId;
      _selectedVillageId = null;
      _selectedSchoolId = null;
      _villages = [];
      _schools = [];
      _isLoadingLocations = true;
    });

    if (clusterId != null) {
      try {
        final villages = await ref.read(studentProvider.notifier).getVillages(clusterId);
        setState(() {
          _villages = villages;
        });
      } catch (e) {
        _showErrorSnackBar('Failed to load villages: ${e.toString()}');
      }
    }
    setState(() => _isLoadingLocations = false);
  }

  Future<void> _onVillageChanged(String? villageId) async {
    setState(() {
      _selectedVillageId = villageId;
      _selectedSchoolId = null;
      _schools = [];
      _isLoadingLocations = true;
    });

    if (villageId != null) {
      try {
        final schools = await ref.read(studentProvider.notifier).getSchools(villageId);
        setState(() {
          _schools = schools;
        });
      } catch (e) {
        _showErrorSnackBar('Failed to load schools: ${e.toString()}');
      }
    }
    setState(() => _isLoadingLocations = false);
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
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
              if (_isLoadingLocations) const Padding(padding: EdgeInsets.only(bottom: 16.0), child: LinearProgressIndicator()),
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
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedClusterId,
                items: _clusters.map((c) => DropdownMenuItem<String>(value: c['id'].toString(), child: Text(c['name']))).toList(),
                onChanged: _onClusterChanged,
                decoration: const InputDecoration(labelText: 'Cluster', border: OutlineInputBorder()),
                validator: (val) => val == null ? 'Select a cluster' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedVillageId,
                items: _villages.map((v) => DropdownMenuItem<String>(value: v['id'].toString(), child: Text(v['name']))).toList(),
                onChanged: _onVillageChanged,
                decoration: const InputDecoration(labelText: 'Village', border: OutlineInputBorder()),
                validator: (val) => val == null ? 'Select a village' : null,
                disabledHint: const Text('Select a cluster first'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedSchoolId,
                items: _schools.map((s) => DropdownMenuItem<String>(value: s['id'].toString(), child: Text(s['name']))).toList(),
                onChanged: (val) => setState(() => _selectedSchoolId = val),
                decoration: const InputDecoration(labelText: 'School', border: OutlineInputBorder()),
                validator: (val) => val == null ? 'Select a school' : null,
                disabledHint: const Text('Select a village first'),
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

    try {
      final success = await ref
          .read(studentProvider.notifier)
          .registerStudent(
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            studentId: _idController.text.trim(),
            gender: _selectedGender,
            grade: _selectedGrade,
            schoolId: _selectedSchoolId!,
          );

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Student Registered Successfully!')));
        Navigator.pop(context, true);
      } else {
        _showErrorSnackBar('Registration failed. Check Debug Console for exact system exception.');
      }
    } catch (e) {
      _showErrorSnackBar('Error: ${e.toString()}');
    }
  }

  Future<void> _handleExcelImport() async {
    try {
      await ref.read(studentProvider.notifier).importStudentsFromExcel();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import successful!')));
    } catch (e) {
      _showErrorSnackBar('Error Debug: ${e.toString()}');
      String msg = e.toString();

      if (msg.contains("CONFLICT:")) {
        final conflictString = msg.substring(msg.indexOf("CONFLICT:") + 9);
        final parts = conflictString.split("|");
        if (parts.length < 3) return;

        try {
          jsonDecode(parts.sublist(2).join("|"));
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => ConflictWorkspaceDialog(conflictRawString: msg),
          );
        } catch (_) {
          _showErrorSnackBar('Conflict found, but data is malformed.');
        }
      } else {
        _showErrorSnackBar('Excel Import Failed: $msg');
      }
    }
  }
}
