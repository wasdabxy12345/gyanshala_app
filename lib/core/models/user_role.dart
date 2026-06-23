enum UserRole {
  shikshaMitra38,
  shikshaMitra910,
  mentorBV8, // 💡 Completely renamed internally to avoid future confusion
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
        return 'Mentor (BV-8)'; // 💡 Clean, cohesive internal and external naming
      case UserRole.admin:
        return 'Admin';
    }
  }
}
