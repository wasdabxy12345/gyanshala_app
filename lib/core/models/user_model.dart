enum UserRole {
  mentor,
  seniorMentor,
  admin;

  static UserRole fromString(String? value) {
    // This ensures that even if Supabase returns 'Mentor',
    // it matches our enum 'mentor'
    return UserRole.values.firstWhere(
      (role) => role.name.toLowerCase() == value?.toLowerCase(),
      orElse: () => UserRole.mentor,
    );
  }
}

extension UserRoleLabel on UserRole {
  String get label {
    switch (this) {
      case UserRole.mentor:
        return 'Mentor';
      case UserRole.seniorMentor:
        return 'Senior Mentor';
      case UserRole.admin:
        return 'Admin';
    }
  }
}
