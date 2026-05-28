import 'package:flutter/foundation.dart';
import 'package:gyanshala_app/core/models/user_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/validators.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._supabase);
  final SupabaseClient _supabase;
  GoTrueClient get _auth => _supabase.auth;

  @override
  Future<UserModel> login({required String identifier, required String password}) async {
    final response = await _supabase.auth.signInWithPassword(phone: identifier, password: password);

    if (response.user == null) throw Exception("Login failed");

    final profileData = await _supabase.from('profiles').select().eq('id', response.user!.id).single();

    return UserModel.fromJson(profileData);
  }

  @override
  Future<void> signup({
    required String firstName,
    required String lastName,
    required String identifier,
    required String password,
    required String role,
    String? qualification,
    String? village,
    String? cluster,
    String? school,
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
        'qualification': qualification,
        'village': village,
        'cluster': cluster,
        'school': school,
      },
    );
  }

  @override
  Future<void> sendOtp({required String identifier, bool requireApprovedSignup = true}) async {
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
  Future<void> verifyOtp({required String identifier, required String otp}) async {
    try {
      AuthResponse response;
      try {
        response = await _supabase.auth.verifyOTP(phone: identifier, token: otp, type: OtpType.phoneChange);
      } on AuthException catch (e) {
        if (kDebugMode) {
          print("phoneChange verification failed, attempting standard sms fallback: ${e.message}");
        }
        response = await _supabase.auth.verifyOTP(phone: identifier, token: otp, type: OtpType.sms);
      }
      if (response.user != null) {
        int retryCount = 0;
        bool profileExists = false;
        while (retryCount < 3 && !profileExists) {
          final profile = await _supabase.from('profiles').select().eq('id', response.user!.id).maybeSingle();
          if (profile != null) {
            profileExists = true;
            break;
          }
          await Future.delayed(const Duration(seconds: 1));
          retryCount++;
        }
        if (!profileExists && kDebugMode) {
          print("Warning: Profile record still not found after retries.");
        }
      }
    } on AuthException catch (e) {
      throw e.message;
    } catch (e) {
      throw e.toString();
    }
  }

  @override
  Future<void> updatePassword({required String password, String? identifier, String? oldPassword}) async {
    try {
      if (identifier != null) {
        final phone = _normalizePhone(identifier);
        final requestRows = await _fetchSignupRequestsByPhone(phone, columns: 'first_name,last_name,role');

        Map<String, dynamic> metadata = {};
        if (requestRows.isNotEmpty) {
          metadata = {
            'first_name': requestRows.first['first_name'],
            'last_name': requestRows.first['last_name'],
            'role': requestRows.first['role'],
          };
        }

        await _auth.updateUser(UserAttributes(password: password, data: metadata));
        await _supabase.from('signup_requests').update({'status': 'completed'}).eq('phone', phone);
      }
    } on AuthException catch (e) {
      if (e.message.contains('Invalid login credentials')) {
        throw Exception("The current password you entered is incorrect.");
      }
      throw Exception(e.message);
    } catch (e) {
      throw Exception("Update failed: $e");
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

  Future<List<Map<String, dynamic>>> _fetchSignupRequestsByPhone(String phone, {String columns = 'status'}) async {
    final candidates = _phoneCandidates(phone);
    for (final candidate in candidates) {
      final rows = await _supabase.from('signup_requests').select(columns).eq('phone', candidate).limit(1);
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

  @override
  Future<void> updateProfile({
    required String firstName,
    required String lastName,
    String? qualification,
    String? village,
    String? cluster,
    String? school,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception("No authenticated user found.");

    final String role = (user.userMetadata?['role'] ?? '').toString().toLowerCase();
    final bool isAdmin = role == 'Admin';

    final Map<String, dynamic> updateData = {
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (!isAdmin) {
      if (qualification != null) updateData['qualification'] = qualification;
      if (village != null) updateData['village'] = village;
      if (cluster != null) updateData['cluster'] = cluster;
      if (school != null) updateData['school'] = school;
    }

    await _supabase.from('profiles').update(updateData).eq('id', user.id);

    await _auth.updateUser(UserAttributes(data: {'first_name': firstName.trim(), 'last_name': lastName.trim()}));
  }
}
