import 'dart:convert';

import 'form_question_model.dart';

class DynamicForm {
  final String id;
  final String title;
  final List<FormQuestion> questions;

  DynamicForm({required this.id, required this.title, required this.questions});
  factory DynamicForm.fromMap(Map<String, dynamic> map) {
    final rawQuestions = map['questions'];
    List<FormQuestion> parsedQuestions = [];

    if (rawQuestions != null) {
      final List<dynamic> jsonList = rawQuestions is String ? jsonDecode(rawQuestions) : rawQuestions as List<dynamic>;

      parsedQuestions = jsonList.map((q) => FormQuestion.fromJson(q as Map<String, dynamic>)).toList();
    }

    return DynamicForm(id: map['id'] as String, title: map['title'] as String, questions: parsedQuestions);
  }
  Map<String, dynamic> toMap() {
    return {'title': title, 'questions': questions.map((q) => q.toJson()).toList()};
  }
}
