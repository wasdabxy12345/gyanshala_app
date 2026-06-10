import 'package:flutter/material.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'form_filler_screen.dart';

class AvailableFormsScreen extends StatefulWidget {
  const AvailableFormsScreen({super.key});

  @override
  State<AvailableFormsScreen> createState() => _AvailableFormsScreenState();
}

class _AvailableFormsScreenState extends State<AvailableFormsScreen> {
  List<Map<String, dynamic>> _availableForms = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchForms();
  }

  Future<void> _fetchForms() async {
    try {
      final supabase = Supabase.instance.client;
      final data = await supabase.from('forms').select('id, title').order('title');

      setState(() {
        _availableForms = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error fetching assignments: $e"), backgroundColor: Colors.red));
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Assigned Evaluations")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue))
          : _availableForms.isEmpty
          ? const Center(
              child: Text("No evaluation templates assigned yet.", style: TextStyle(color: Colors.grey)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _availableForms.length,
              itemBuilder: (context, index) {
                final form = _availableForms[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0x1A9C27B0),
                      child: Icon(Icons.assignment, color: Colors.purple),
                    ),
                    title: Text(form['title'] ?? 'Evaluation Blueprint', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text("Tap to open and fill responses"),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              FormFillerScreen(formId: form['id'].toString(), formTitle: form['title'] ?? 'Evaluation Framework'),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
