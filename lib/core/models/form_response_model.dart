class FormResponse {
  final String? id;
  final String formId;
  final String userId;
  final Map<String, dynamic> answers;
  final double? latitude;
  final double? longitude;
  final DateTime? submittedAt;

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
  Map<String, dynamic> toMap() {
    return {
      'form_id': formId,
      'user_id': userId,
      'answers': answers,
      if (latitude != null && longitude != null) 'gps_location': 'POINT($longitude $latitude)',
    };
  }
}
