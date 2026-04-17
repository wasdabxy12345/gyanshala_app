import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/validators.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl._internal();

  static final AuthRepositoryImpl instance = AuthRepositoryImpl._internal();

  // Supabase Configuration check
  // static const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  // static const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  // ignore: unnecessary_null_comparison
  bool get _isSupabaseEnabled => Supabase.instance.client != null;

  GoTrueClient get _auth => Supabase.instance.client.auth;

  /// Throws an exception if Supabase is not configured
  void _ensureSupabase() {
    if (!_isSupabaseEnabled) {
      throw Exception(
        'Supabase is not configured. Please check your environment variables.',
      );
    }
  }

  @override
  Future<void> login({
    required String identifier,
    required String password,
    required String role,
  }) async {
    final phone = _normalizePhone(identifier);

    // Attempt standard login
    final response = await _auth.signInWithPassword(
      phone: phone,
      password: password,
    );

    // Check if they are approved via metadata
    final status = response.user?.userMetadata?['status'];

    if (status != 'approved') {
      // Sign them back out if not approved
      await _auth.signOut();
      throw Exception("Your account is still pending admin approval.");
    }
  }

  @override
  Future<void> signup({
    required String firstName,
    required String lastName,
    required String identifier,
    required String password,
    required String role,
    String? pushToken,
  }) async {
    final phone = _normalizePhone(identifier);

    // You only need THIS call now.
    // The database trigger we just wrote handles the 'signup_requests' table.
    await _auth.signUp(
      phone: phone,
      password: password,
      data: {
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
        'role': role,
        'status': 'pending',
        'push_token': pushToken, // This metadata is passed to the trigger
      },
    );

    debugPrint(
      '✓ Signup initiated. Database trigger is handling the request entry.',
    );
  }

  @override
  Future<void> sendOtp({
    required String identifier,
    bool requireApprovedSignup = true,
  }) async {
    _ensureSupabase();
    final phone = _normalizePhone(identifier);

    // 1. Check the approval status
    final status = await getSignupStatus(identifier);
    if (status != 'approved') {
      throw Exception('Your account is still $status. OTP cannot be sent.');
    }

    // 2. Trigger the OTP call ONCE
    await _auth.signInWithOtp(
      phone: phone,
      shouldCreateUser: false, // Account was created at signup
    );

    debugPrint('✓ Admin-approved OTP sent to: $phone');
  }

  @override
  Future<void> verifyOtp({
    required String identifier,
    required String otp,
  }) async {
    final phone = _normalizePhone(identifier);

    // This confirms the phone number in Supabase Auth
    await _auth.verifyOTP(type: OtpType.sms, phone: phone, token: otp.trim());

    debugPrint("✓ Phone verified and account fully activated.");
  }

  @override
  Future<void> updatePassword({
    required String identifier,
    required String password,
  }) async {
    _ensureSupabase();
    final phone = _normalizePhone(identifier);

    final requestRows = await _fetchSignupRequestsByPhone(
      phone,
      columns: 'phone,first_name,last_name,role',
    );

    final metadata = requestRows.isEmpty
        ? null
        : {
            'first_name': requestRows.first['first_name'],
            'last_name': requestRows.first['last_name'],
            'role': requestRows.first['role'],
          };

    // Update Auth User
    await _auth.updateUser(UserAttributes(password: password, data: metadata));

    // Mark request as completed
    if (requestRows.isNotEmpty) {
      await Supabase.instance.client
          .from('signup_requests')
          .update({'status': 'completed'})
          .eq('phone', requestRows.first['phone']);
    }
  }

  @override
  Future<String> getSignupStatus(String identifier) async {
    _ensureSupabase();
    final phone = _normalizePhone(identifier);
    final rows = await _fetchSignupRequestsByPhone(phone, columns: 'status');

    if (rows.isEmpty) {
      throw Exception('No signup request found.');
    }

    return (rows.first['status'] as String).toLowerCase();
  }

  // --- Helper Methods ---

  String _normalizePhone(String value) {
    final trimmed = value.trim();
    final digitsOnly = trimmed.replaceAll(RegExp(r'\D'), '');
    if (Validators.isValidPhone(trimmed)) {
      return digitsOnly;
    }
    throw Exception('Enter a valid phone number.');
  }

  Future<List<Map<String, dynamic>>> _fetchSignupRequestsByPhone(
    String phone, {
    String columns = 'status',
  }) async {
    final candidates = _phoneCandidates(phone);
    for (final candidate in candidates) {
      final rows = await Supabase.instance.client
          .from('signup_requests')
          .select(columns)
          .eq('phone', candidate)
          .limit(1);
      if (rows.isNotEmpty) return List<Map<String, dynamic>>.from(rows);
    }
    return [];
  }

  Set<String> _phoneCandidates(String phone) {
    final candidates = <String>{phone};
    if (phone.length > 10) {
      candidates.add(phone.substring(phone.length - 10));
    } else if (phone.length == 10) {
      candidates.add('91$phone');
    }
    return candidates;
  }
}
