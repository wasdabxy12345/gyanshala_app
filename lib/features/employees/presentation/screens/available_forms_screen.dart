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
      appBar: AppBar(title: const Text("Forms")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue))
          : _availableForms.isEmpty
          ? const Center(
              child: Text("No forms found", style: TextStyle(color: Colors.grey)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _availableForms.length,
              itemBuilder: (context, index) {
                final form = _availableForms[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 13),
                  elevation: 1,
                  child: ListTile(
                    title: Text(
                      form['title'] ?? '[no title]',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.primaryBlue),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              FormFillerScreen(formId: form['id'].toString(), formTitle: form['title'] ?? '[no title]'),
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
