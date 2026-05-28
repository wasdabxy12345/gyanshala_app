import 'dart:convert';

import 'form_question_model.dart'; // Make sure to import your question model file

class DynamicForm {
  final String id;
  final String title;
  final List<FormQuestion> questions;

  DynamicForm({required this.id, required this.title, required this.questions});

  /// Factory constructor to create a DynamicForm from a Supabase row map.
  factory DynamicForm.fromMap(Map<String, dynamic> map) {
    // 1. Safeguard extraction of the questions list from JSONB payload
    final rawQuestions = map['questions'];
    List<FormQuestion> parsedQuestions = [];

    if (rawQuestions != null) {
      // Supabase might return the JSONB column as a pre-parsed List or a JSON String depending on the client setup
      final List<dynamic> jsonList = rawQuestions is String ? jsonDecode(rawQuestions) : rawQuestions as List<dynamic>;

      parsedQuestions = jsonList.map((q) => FormQuestion.fromJson(q as Map<String, dynamic>)).toList();
    }

    return DynamicForm(id: map['id'] as String, title: map['title'] as String, questions: parsedQuestions);
  }

  /// Converts a DynamicForm instance into a Map format suitable for Supabase insertion (Admin app).
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'questions': questions.map((q) => q.toJson()).toList(),
      // 'id' is omitted here assuming Supabase generates UUID automatically via gen_random_uuid()
    };
  }
}
