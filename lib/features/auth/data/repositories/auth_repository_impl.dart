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
    final profile = await Supabase.instance.client
        .from('signup_requests')
        .select()
        .eq('phone', identifier)
        .single();

    String dbRole = profile['role'].toString().trim().toLowerCase();
    String selectedRole = role.trim().toLowerCase();

    if (dbRole != selectedRole) {
      throw Exception(
        "Selected role ($selectedRole) does not match account role ($dbRole)",
      );
    }

    _ensureSupabase();
    final phone = _normalizePhone(identifier);

    // Sign in with phone + password
    final response = await _auth.signInWithPassword(
      phone: phone,
      password: password,
    );

    // Sync user metadata with DB role
    final String? userMetadataRole = response.user?.userMetadata?['role']?.toString();
    if (userMetadataRole?.toLowerCase() != role.toLowerCase()) {
      await _auth.updateUser(UserAttributes(data: {'role': role}));
      debugPrint("✓ Updated user metadata role to: $role");
    }

    debugPrint("✓ Login successful for phone: $phone as $role");
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
    _ensureSupabase();
    final phone = _normalizePhone(identifier);

    try {
      // Only create signup_requests record - DO NOT create auth account yet
      // Auth account will be created after admin approval via OTP verification
      final existingRows = await _fetchSignupRequestsByPhone(
        phone,
        columns: 'phone,status',
      );

      if (existingRows.isNotEmpty) {
        final status = (existingRows.first['status'] as String?)?.toLowerCase();
        if (status == 'approved' || status == 'completed') {
          throw Exception(
            'A request for this number is already approved or completed.',
          );
        }

        // Update existing pending/denied request
        await Supabase.instance.client
            .from('signup_requests')
            .update({
              'first_name': firstName.trim(),
              'last_name': lastName.trim(),
              'role': role,
              'password': password, // Store password to be used later
              'status': 'pending',
              'push_token': pushToken,
            })
            .eq('phone', existingRows.first['phone']);
        debugPrint('✓ Updated signup request for phone: $phone');
      } else {
        // Create new request
        await Supabase.instance.client.from('signup_requests').insert({
          'phone': phone,
          'first_name': firstName.trim(),
          'last_name': lastName.trim(),
          'role': role,
          'password': password, // Store password to be used later
          'status': 'pending',
          'push_token': pushToken,
        });
        debugPrint('✓ Created signup request for phone: $phone');
      }
    } on PostgrestException catch (e) {
      if (_isMissingSignupRequestsTable(e)) {
        throw Exception('Signup approval table missing. Please contact admin.');
      }
      rethrow;
    }
  }

  @override
  Future<void> sendOtp({
    required String identifier,
    bool requireApprovedSignup = false,
  }) async {
    _ensureSupabase();
    final phone = _normalizePhone(identifier);

    bool accountCreated = false;

    if (requireApprovedSignup) {
      final status = await getSignupStatus(identifier);
      if (status != 'approved') {
        throw Exception('Your account is not approved yet.');
      }

      // Fetch the stored password from signup_requests
      try {
        final signupData = await _fetchSignupRequestsByPhone(
          phone,
          columns: 'phone,first_name,last_name,role,password',
        );

        if (signupData.isNotEmpty) {
          final data = signupData.first;
          final storedPassword = data['password'] as String?;

          if (storedPassword != null && storedPassword.isNotEmpty) {
            // Create auth account with the stored password BEFORE sending OTP
            try {
              await _auth.signUp(
                phone: phone,
                password: storedPassword,
                data: {
                  'first_name': data['first_name'],
                  'last_name': data['last_name'],
                  'role': data['role'],
                },
              );
              accountCreated = true;
              debugPrint('✓ Auth account created for phone: $phone');
            } on AuthException catch (e) {
              if (!e.message.contains('already registered')) {
                rethrow;
              }
              accountCreated = true;
              debugPrint('⚠ Auth account already exists for: $phone');
            }
          }
        }
      } catch (e) {
        debugPrint('⚠ Warning: Could not create auth account: $e');
      }
    }

    // Send OTP - only create user if we haven't created the account yet
    await _auth.signInWithOtp(
      phone: phone,
      shouldCreateUser: !accountCreated && requireApprovedSignup,
    );
    debugPrint('✓ OTP sent to: $phone');
  }

  @override
  Future<void> verifyOtp({
    required String identifier,
    required String otp,
  }) async {
    _ensureSupabase();
    final phone = _normalizePhone(identifier);

    // Verify the OTP
    await _auth.verifyOTP(type: OtpType.sms, phone: phone, token: otp.trim());
    
    debugPrint("✓ OTP verified for phone: $phone");
    
    // Get signup data and update auth account with password + metadata
    try {
      final signupData = await _fetchSignupRequestsByPhone(
        phone,
        columns: 'phone,first_name,last_name,role,password',
      );
      
      if (signupData.isNotEmpty) {
        final data = signupData.first;
        final storedPassword = data['password'] as String?;

        // Set password and metadata in auth account
        await _auth.updateUser(
          UserAttributes(
            password: storedPassword,
            data: {
              'first_name': data['first_name'],
              'last_name': data['last_name'],
              'role': data['role'],
            },
          ),
        );
        debugPrint("✓ Auth account updated with password and metadata");
      }
    } catch (e) {
      debugPrint("⚠ Warning: Could not update auth account: $e");
    }
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

  bool _isMissingSignupRequestsTable(PostgrestException e) {
    return e.code == 'PGRST205' || e.message.contains("public.signup_requests");
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
