import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/validators.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._supabase);
  final SupabaseClient _supabase;
  GoTrueClient get _auth => _supabase.auth;

  @override
  Future<void> login({
    required String identifier,
    required String password,
    required String role, // This is the role selected in the UI
  }) async {
    final phone = _normalizePhone(identifier);

    // 1. Perform standard login
    final response = await _auth.signInWithPassword(
      phone: phone,
      password: password,
    );

    final user = response.user;
    if (user == null) throw Exception("User not found.");

    // 2. Check Approval Status (Existing logic)
    final status = user.userMetadata?['status'];
    if (status != 'approved') {
      await _auth.signOut();
      throw Exception("Your account is still pending admin approval.");
    }

    // 3. ROLE VERIFICATION (The Fix)
    // Check the role stored in metadata (or you could query the 'profiles' table)
    final actualRole = user.userMetadata?['role'];

    if (actualRole != role) {
      // If they logged in as "Mentor" but are an "Admin" in DB, kick them out
      await _auth.signOut();
      throw Exception(
        "Access Denied: You are registered as $actualRole, not $role.",
      );
    }

    debugPrint("✓ Login successful as $actualRole");
  }

  @override
  Future<void> signup({
    required String firstName,
    required String lastName,
    required String identifier,
    required String password,
    required String role,
    required String qualification, // Added
    required String village, // Added
    required String cluster, // Added
    required String school, // Added
    String? pushToken,
  }) async {
    final phone = _normalizePhone(identifier);

    // This call passes all metadata to the Supabase Auth user.
    // Your database trigger will then pick these up to create the profile/request.
    await _auth.signUp(
      phone: phone,
      password: password,
      data: {
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
        'role': role,
        'status': 'pending',
        'qualification': qualification.trim(), // Pass to metadata
        'village': village.trim(), // Pass to metadata
        'cluster': cluster.trim(), // Pass to metadata
        'school': school.trim(), // Pass to metadata
        'push_token': pushToken,
      },
    );

    debugPrint(
      '✓ Signup initiated with mentor details. Database trigger is handling the request entry.',
    );
  }

  @override
  Future<void> sendOtp({
    required String identifier,
    bool requireApprovedSignup = true,
  }) async {
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
    try {
      final response = await _supabase.auth.verifyOTP(
        phone: identifier,
        token: otp,
        type: OtpType.sms,
      );

      if (response.user != null) {
        // 1. Give the DB a moment or implement a retry mechanism
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

          // Wait 1 second before retrying
          await Future.delayed(Duration(seconds: 1));
          retryCount++;
        }

        if (!profileExists) {
          // Log this but don't necessarily crash the auth flow
          if (kDebugMode) {
            print("Warning: Profile record still not found after retries.");
          }
          // Decide if you want to allow them in or redirect to a 'Setup' page
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
      await _supabase
          .from('signup_requests')
          .update({'status': 'completed'})
          .eq('phone', requestRows.first['phone']);
    }
  }

  @override
  Future<String> getSignupStatus(String identifier) async {
    final phone = _normalizePhone(identifier);
    final rows =
        await _supabase // Changed from Supabase.instance.client
            .from('signup_requests')
            .select('status')
            .eq('phone', phone)
            .limit(1);

    if (rows.isEmpty) throw Exception('No signup request found.');
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

  @override
  Future<void> updateProfile({
    required String firstName,
    required String lastName,
    String? qualification, // Added optional parameters
    String? village,
    String? cluster,
    String? school,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final Map<String, dynamic> updateData = {
      'first_name': firstName,
      'last_name': lastName,
      'updated_at': DateTime.now().toIso8601String(),
    };

    // Only add these to the update map if they aren't null
    if (qualification != null) updateData['qualification'] = qualification;
    if (village != null) updateData['village'] = village;
    if (cluster != null) updateData['cluster'] = cluster;
    if (school != null) updateData['school'] = school;

    await _supabase.from('profiles').update(updateData).eq('id', user.id);
  }
}
