import 'package:gyanshala_app/core/models/form_question_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FormRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Resolves database reference rules dynamically based on configuration models
  Future<Map<String, String>> fetchDynamicOptions(DataSourceRule rule) async {
    try {
      // Executes queries dynamically: e.g., supabase.from('schools').select('id, school_name')
      final List<dynamic> response = await _supabase.from(rule.table).select('${rule.valueColumn}, ${rule.labelColumn}');

      // Transform rows into a lookup map: { "id_123": "Primary School Alpha" }
      final Map<String, String> optionsMap = {};
      for (var row in response) {
        final key = row[rule.valueColumn]?.toString() ?? '';
        final value = row[rule.labelColumn]?.toString() ?? '';
        if (key.isNotEmpty) {
          optionsMap[key] = value;
        }
      }
      return optionsMap;
    } catch (e) {
      // Fallback matrix configuration in case network drops out
      return {};
    }
  }

  /// Sends structural answer logs downstream
  Future<void> submitFormResponse(Map<String, dynamic> answers, String formId, String userId) async {
    await _supabase.from('form_submissions').insert({
      'form_id': formId,
      'user_id': userId,
      'responses': answers,
      'submitted_at': DateTime.now().toIso8601String(),
    });
  }
}
