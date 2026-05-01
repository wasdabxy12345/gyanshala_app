import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/validators.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._supabase);
  final SupabaseClient _supabase;
  GoTrueClient get _auth => _supabase.auth;
  void _ensureSupabase() {}

  @override
  Future<void> login({
    required String identifier,
    required String password,
    required String role,
  }) async {
    final phone = _normalizePhone(identifier);

    final response = await _auth.signInWithPassword(
      phone: phone,
      password: password,
    );

    final status = response.user?.userMetadata?['status'];

    if (status != 'approved') {
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

    await _auth.signUp(
      phone: phone,
      password: password,
      data: {
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
        'role': role,
        'status': 'pending',
        'push_token': pushToken,
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

    final status = await getSignupStatus(identifier);

    if (status == 'pending' || status == 'rejected') {
      throw Exception('Your account is still $status. OTP cannot be sent.');
    }

    try {
      await _auth.signInWithOtp(phone: phone, shouldCreateUser: false);
    } on AuthException catch (e) {
      if (e.message.contains('User not found')) {
        throw Exception('No account found for this phone number.');
      }
      rethrow;
    }
  }

  @override
  Future<void> verifyOtp({
    required String identifier,
    required String otp,
  }) async {
    try {
      final response = await _supabase.auth.verifyOTP(
        phone: identifier,
        token: otp,
        type: OtpType.sms,
      );

      if (response.user != null) {
        int retryCount = 0;
        bool profileExists = false;

        while (retryCount < 3 && !profileExists) {
          final profile = await _supabase
              .from('profiles')
              .select()
              .eq('id', response.user!.id)
              .maybeSingle();

          if (profile != null) {
            profileExists = true;
            break;
          }

          await Future.delayed(Duration(seconds: 1));
          retryCount++;
        }

        if (!profileExists) {
          if (kDebugMode) {
            print("Warning: Profile record still not found after retries.");
          }
        }
      }
    } on AuthException catch (e) {
      throw e.message;
    } catch (e) {
      throw e.toString();
    }
  }

  @override
  Future<void> updatePassword({
    required String identifier,
    required String password,
  }) async {
    _ensureSupabase();
    final phone = _normalizePhone(identifier);

    await _auth.updateUser(UserAttributes(password: password));

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

    await _auth.updateUser(UserAttributes(password: password, data: metadata));

    if (requestRows.isNotEmpty) {
      await _supabase
          .from('signup_requests')
          .update({'status': 'completed'})
          .eq('phone', requestRows.first['phone']);
    }
  }

  @override
  Future<String> getSignupStatus(String identifier) async {
    final phone = _normalizePhone(identifier);
    final rows = await _fetchSignupRequestsByPhone(phone, columns: 'status');

    if (rows.isEmpty) return 'not_found';
    return (rows.first['status'] as String).toLowerCase();
  }

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
      final rows = await _supabase
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

  @override
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}
