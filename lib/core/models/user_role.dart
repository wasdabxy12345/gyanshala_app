enum UserRole {
  shikshaMitra,
  seniorMentor,
  admin;

  static UserRole fromString(String? value) {
    return UserRole.values.firstWhere(
      (role) => role.name.toLowerCase() == value?.toLowerCase(),
      orElse: () => UserRole.shikshaMitra,
    );
  }
}

extension UserRoleLabel on UserRole {
  String get label {
    switch (this) {
      case UserRole.shikshaMitra:
        return 'Shiksha Mitra';
      case UserRole.seniorMentor:
        return 'Senior Mentor';
      case UserRole.admin:
        return 'Admin';
    }
  }
}
