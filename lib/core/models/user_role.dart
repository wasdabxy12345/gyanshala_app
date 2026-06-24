enum UserRole {
  shikshaMitra38,
  shikshaMitra910,
  mentorBV8,
  admin;

  static UserRole fromString(String? value) {
    return UserRole.values.firstWhere(
      (role) => role.name.toLowerCase() == value?.toLowerCase(),
      orElse: () => UserRole.shikshaMitra38,
    );
  }
}

extension UserRoleLabel on UserRole {
  String get label {
    switch (this) {
      case UserRole.shikshaMitra38:
        return 'Shiksha Mitra (3-8)';
      case UserRole.shikshaMitra910:
        return 'Shiksha Mitra (9-10)';
      case UserRole.mentorBV8:
        return 'Mentor (BV-8)';
      case UserRole.admin:
        return 'Admin';
    }
  }
}
