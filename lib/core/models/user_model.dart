enum UserRole {
  mentor,
  seniorMentor,
  admin,
}

extension UserRoleLabel on UserRole {
  String? get label {
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