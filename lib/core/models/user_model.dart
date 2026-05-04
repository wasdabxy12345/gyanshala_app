class UserModel {
  final String id;
  final String phone;
  final String? firstName;
  final String? lastName;
  final String role; // String from DB
  final String? qualification;
  final String? cluster;
  final String? village;
  final String? school;

  UserModel({
    required this.id,
    required this.phone,
    this.firstName,
    this.lastName,
    required this.role,
    this.qualification,
    this.village,
    this.cluster,
    this.school,
  });

  // Factory to create a UserModel from Supabase Map
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      phone: json['phone'] as String,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      role: json['role'] as String? ?? 'mentor',
      qualification: json['qualification'] as String?,
      village: json['village'] as String?,
      cluster: json['cluster'] as String?,
      school: json['school'] as String?,
    );
  }
}
