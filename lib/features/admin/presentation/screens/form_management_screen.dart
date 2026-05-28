import 'package:flutter/material.dart';
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error syncing forms collection: $e"), backgroundColor: Colors.red));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _createNewForm() {
    final titleController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          "Create New Form Document",
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00AFEF)),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00AFEF)),
            onPressed: () async {
              final text = titleController.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(context);
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
                  ).then((_) => _fetchFormsFromSupabase());
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Failed to instantiate form database entry: $e"), backgroundColor: Colors.red),
                  );
                }
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
        backgroundColor: const Color(0xFF00AFEF),
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchFormsFromSupabase)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00AFEF)))
          : _formsList.isEmpty
          ? const Center(
              child: Text("No evaluation forms found. Create one to begin.", style: TextStyle(color: Colors.grey)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _formsList.length,
              itemBuilder: (context, index) {
                final form = _formsList[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.assignment_turned_in, color: Color(0xFF00AFEF)),
                    title: Text(form['title'] ?? 'Missing Title Reference', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("UUID: ${form['id']}", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FormBuilderCanvas(
                            formId: form['id'].toString(),
                            formTitle: form['title'] ?? 'Evaluation Framework',
                          ),
                        ),
                      ).then((_) => _fetchFormsFromSupabase());
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNewForm,
        backgroundColor: const Color(0xFF00AFEF),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Create Form", style: TextStyle(color: Colors.white)),
      ),
    );
  }
}
