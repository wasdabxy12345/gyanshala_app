import 'package:flutter/material.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:gyanshala_app/features/admin/presentation/screens/form_responses_viewer_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'form_builder_canvas.dart';

class FormManagementScreen extends StatefulWidget {
  const FormManagementScreen({super.key});

  @override
  State<FormManagementScreen> createState() => _FormManagementScreenState();
}

class _FormManagementScreenState extends State<FormManagementScreen> {
  List<Map<String, dynamic>> _formsList = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchFormsFromSupabase();
  }

  Future<void> _fetchFormsFromSupabase() async {
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final data = await supabase.from('forms').select('id, title').order('title');
      setState(() {
        _formsList = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error syncing forms collection: $e"), backgroundColor: Colors.red));
      }
    } finally {
      // FIXED: Corrected from 'final' to 'finally'
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteFormDocument(String formId, String formTitle) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final bool confirmDelete =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
                SizedBox(width: 8),
                Text("Delete Form Blueprint?", style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              "Are you sure you want to delete \"$formTitle\"?\n\nThis operation will permanently purge all related canvas questions and matching user submission entries.",
              style: const TextStyle(height: 1.4),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Cancel")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text("Permanently Delete", style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmDelete) return;

    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('forms').delete().eq('id', formId);

      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text("\"$formTitle\" successfully removed from database."), backgroundColor: Colors.green),
      );

      await _fetchFormsFromSupabase();
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text("Failed to destroy form entity row: $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _createNewForm() {
    final titleController = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          "Create New Form Document",
          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
        ),
        content: TextField(
          controller: titleController,
          decoration: const InputDecoration(
            labelText: "Form Evaluation Title *",
            hintText: "e.g., Student Quality Assessment 2026",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
            onPressed: () async {
              final text = titleController.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(dialogContext);

              setState(() => _isLoading = true);
              try {
                final supabase = Supabase.instance.client;
                final newFormRow = await supabase.from('forms').insert({'title': text}).select('id, title').single();

                await _fetchFormsFromSupabase();

                if (mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          FormBuilderCanvas(formId: newFormRow['id'].toString(), formTitle: newFormRow['title']),
                    ),
                  ).then((_) {
                    if (mounted) _fetchFormsFromSupabase();
                  });
                }
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text("Failed to instantiate form database entry: $e"), backgroundColor: Colors.red),
                );
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            child: const Text("Create Document", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Form Management Layout"),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchFormsFromSupabase)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue))
          : _formsList.isEmpty
          ? const Center(
              child: Text("No evaluation forms found. Create one to begin.", style: TextStyle(color: Colors.grey)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _formsList.length,
              itemBuilder: (context, index) {
                final form = _formsList[index];
                final String currentFormId = form['id'].toString();
                final String currentFormTitle = form['title'] ?? 'Evaluation Framework';

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: ListTile(
                      leading: const Icon(Icons.assignment_turned_in, color: AppTheme.primaryBlue, size: 28),
                      title: Text(currentFormTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.grey, size: 22),
                            tooltip: "Edit Form Template",
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => FormBuilderCanvas(formId: currentFormId, formTitle: currentFormTitle),
                                ),
                              ).then((_) => _fetchFormsFromSupabase());
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent, size: 22),
                            tooltip: "Remove Form Blueprint",
                            onPressed: () => _deleteFormDocument(currentFormId, currentFormTitle),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, color: Colors.grey),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => FormResponsesOverviewScreen(formId: currentFormId, formTitle: currentFormTitle),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNewForm,
        backgroundColor: AppTheme.primaryBlue,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Create Form", style: TextStyle(color: Colors.white)),
      ),
    );
  }
}
