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

    // This is the variable the warning is talking about
    final candidates = _phoneCandidates(phone);

    if (requireApprovedSignup) {
      // 1. Check for new signups
      final status = await getSignupStatus(identifier);
      if (status != 'approved') {
        throw Exception('Your account is still $status. OTP cannot be sent.');
      }
    } else {
      // 2. CHECK FOR FORGOT PASSWORD
      // Use the 'candidates' variable here to satisfy the compiler and fix the bug
      final response = await _supabase
          .from('profiles')
          .select('id')
          .inFilter('phone', candidates.toList()) // <--- VARIABLE IS USED HERE
          .maybeSingle();

      if (response == null) {
        throw Exception('No account found with this phone number.');
      }
    }

    // Trigger OTP
    await _auth.signInWithOtp(phone: phone, shouldCreateUser: false);
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
    final rows = await _fetchSignupRequestsByPhone(
      identifier,
      columns: 'status',
    );

    if (rows.isEmpty) {
      throw Exception(
        'No signup request found for $identifier. Please sign up first.',
      );
    }

    return (rows.first['status'] as String).toLowerCase();
  }

  String _normalizePhone(String value) {
    final trimmed = value.trim();
    final digitsOnly = trimmed.replaceAll(RegExp(r'\D'), '');
    debugPrint('Normalized phone for query: $digitsOnly');
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
      // If user entered 919876543210, also search for 9876543210
      candidates.add(phone.substring(phone.length - 10));
    } else if (phone.length == 10) {
      // If user entered 9876543210, also search for 919876543210
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
