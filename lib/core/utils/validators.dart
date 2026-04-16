class Validators {
  static bool isValidEmail(String email) {
    return email.contains('@') && email.contains('.');
  }

  static bool isValidPhone(String phone) {
    final digitsOnly = phone.replaceAll(RegExp(r'\D'), '');
    return digitsOnly.length >= 10;
  }

  static bool isEmailOrPhone(String value) {
    final trimmed = value.trim();
    return isValidEmail(trimmed) || isValidPhone(trimmed);
  }
}
