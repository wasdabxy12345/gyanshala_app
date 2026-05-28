class FormResponse {
  final String? id; // Nullable because Supabase generates this on insertion
  final String formId;
  final String userId; // Strictly required based on your database constraint
  final Map<String, dynamic> answers; // Stores { "question_id": "user_answer" }
  final double? latitude;
  final double? longitude;
  final DateTime? submittedAt; // Managed automatically by Supabase, but good to track locally

  FormResponse({
    this.id,
    required this.formId,
    required this.userId,
    required this.answers,
    this.latitude,
    this.longitude,
    this.submittedAt,
  });
  factory FormResponse.fromMap(Map<String, dynamic> map) {
    double? lat;
    double? lng;
    final geoPoint = map['gps_location'];

    if (geoPoint is Map) {
      lat = double.tryParse(geoPoint['lat']?.toString() ?? '');
      lng = double.tryParse(geoPoint['lng']?.toString() ?? '');
    } else if (geoPoint is String) {
      final match = RegExp(r'POINT\(([-+]?\d*\.?\d+)\s+([-+]?\d*\.?\d+)\)').firstMatch(geoPoint);
      if (match != null && match.groupCount == 2) {
        lng = double.tryParse(match.group(1) ?? '');
        lat = double.tryParse(match.group(2) ?? '');
      }
    }

    return FormResponse(
      id: map['id'] as String?,
      formId: map['form_id'] as String,
      userId: map['user_id'] as String,
      answers: Map<String, dynamic>.from(map['answers'] as Map),
      latitude: lat,
      longitude: lng,
      submittedAt: map['submitted_at'] != null ? DateTime.parse(map['submitted_at'] as String) : null,
    );
  }

  /// Converts the form responses into a payload map specifically designed for Supabase ingestion
  Map<String, dynamic> toMap() {
    return {
      'form_id': formId,
      'user_id': userId,
      'answers': answers,
      // Formatting to standard PostGIS Point string syntax: 'POINT(longitude latitude)'
      // Note: PostGIS geometry positions items as Longitude first, then Latitude!
      if (latitude != null && longitude != null) 'gps_location': 'POINT($longitude $latitude)',
    };
  }
}
