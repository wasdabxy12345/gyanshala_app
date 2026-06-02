import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'form_filler_screen.dart'; // Import the FormFillerScreen built previously

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
      // Fetch available valuation definitions
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
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        title: const Text("Assigned Evaluations"),
        backgroundColor: const Color(0xff00afef),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xff00afef)))
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
                      // Route explicitly to your user-facing filler canvas
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
