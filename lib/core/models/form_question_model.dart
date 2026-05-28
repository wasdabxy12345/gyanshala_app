class FormQuestion {
  final String id;
  final String type;
  final String label;
  final List<String>? options;
  final DataSourceRule? datasource;
  final ConditionalRule? conditional;

  FormQuestion({required this.id, required this.type, required this.label, this.options, this.datasource, this.conditional});

  factory FormQuestion.fromJson(Map<String, dynamic> json) {
    return FormQuestion(
      id: json['id'] as String,
      type: json['type'] as String,
      label: json['label'] as String,
      options: json['options'] != null ? List<String>.from(json['options'] as List) : null,
      datasource: json['datasource'] != null ? DataSourceRule.fromJson(json['datasource'] as Map<String, dynamic>) : null,
      conditional: json['conditional'] != null ? ConditionalRule.fromJson(json['conditional'] as Map<String, dynamic>) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'label': label,
      if (options != null) 'options': options,
      if (datasource != null) 'datasource': datasource!.toJson(),
      if (conditional != null) 'conditional': conditional!.toJson(),
    };
  }
}

class DataSourceRule {
  final String table;
  final String valueColumn;
  final String labelColumn;

  DataSourceRule({required this.table, required this.valueColumn, required this.labelColumn});

  factory DataSourceRule.fromJson(Map<String, dynamic> json) {
    return DataSourceRule(
      table: json['table'] as String,
      valueColumn: json['value_column'] as String,
      labelColumn: json['label_column'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'table': table, 'value_column': valueColumn, 'label_column': labelColumn};
  }
}

class ConditionalRule {
  final String dependsOn;
  final String equals;

  ConditionalRule({required this.dependsOn, required this.equals});

  factory ConditionalRule.fromJson(Map<String, dynamic> json) {
    return ConditionalRule(dependsOn: json['depends_on'] as String, equals: json['equals'].toString());
  }

  Map<String, dynamic> toJson() {
    return {'depends_on': dependsOn, 'equals': equals};
  }
}
