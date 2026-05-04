enum UserRole {
  mentor,
  seniorMentor,
  admin;

  static UserRole fromString(String? value) {
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
        return 'mentor';
      case UserRole.seniorMentor:
        return 'seniorMentor';
      case UserRole.admin:
        return 'admin';
    }
  }
}
