import 'package:gyanshala_app/core/models/form_question_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FormRepository {
  final SupabaseClient _supabase = Supabase.instance.client;
  Future<Map<String, String>> fetchDynamicOptions(DataSourceRule rule) async {
    try {
      final List<dynamic> response = await _supabase.from(rule.table).select('${rule.valueColumn}, ${rule.labelColumn}');
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
      return {};
    }
  }

  Future<void> submitFormResponse(Map<String, dynamic> answers, String formId, String userId) async {
    await _supabase.from('form_submissions').insert({
      'form_id': formId,
      'user_id': userId,
      'responses': answers,
      'submitted_at': DateTime.now().toIso8601String(),
    });
  }
}
