abstract class AuthRepository {
  Future<void> login({
    required String identifier,
    required String password,
    required String role,
  });

  Future<void> signup({
    required String firstName,
    required String lastName,
    required String identifier,
    required String password,
    required String role,
    String? pushToken,
    required String qualification,
    required String village,
    required String cluster,
    required String school,
  });

  Future<void> sendOtp({
    required String identifier,
    bool requireApprovedSignup = false,
  });

  Future<void> verifyOtp({required String identifier, required String otp});

  Future<void> updatePassword({
    required String identifier,
    required String password,
  });

  Future<String> getSignupStatus(String identifier);

  Future<void> signOut();

  Future<void> updateProfile({
    required String firstName,
    required String lastName,
  });
}
