import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/models/user_model.dart';
import 'package:gyanshala_app/core/providers/auth_provider.dart';
import 'package:gyanshala_app/features/auth/presentation/screens/login_screen.dart';
import 'package:gyanshala_app/features/auth/presentation/screens/welcome_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/validators.dart';
import '../widgets/auth_shell.dart';
import '../widgets/role_selector.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _qualificationController = TextEditingController();
  final _villageController = TextEditingController();
  final _clusterController = TextEditingController();
  final _schoolController = TextEditingController();

  UserRole _selectedRole = UserRole.mentor;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();

    _qualificationController.dispose();
    _villageController.dispose();
    _clusterController.dispose();
    _schoolController.dispose();
    super.dispose();
  }

  Future<void> _onSignupPressed() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    try {
      debugPrint('--- Signup Attempt Start ---');

      String? pushToken = await FirebaseMessaging.instance.getToken();

      await ref
          .read(authRepositoryProvider)
          .signup(
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            identifier: _phoneController.text.trim(),
            password: _passwordController.text,
            role: _selectedRole.label ?? '',
            pushToken: pushToken,
            qualification: _qualificationController.text.trim(),
            village: _villageController.text.trim(),
            cluster: _clusterController.text.trim(),
            school: _schoolController.text.trim(),
          );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_id', _phoneController.text.trim());

      debugPrint('Signup successful and ID persisted.');

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const WelcomeScreen(showPendingMessage: true),
        ),
        (route) => false,
      );
    } catch (e) {
      debugPrint('--- SIGNUP ERROR ---');
      debugPrint(e.toString());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMentorType =
        _selectedRole == UserRole.mentor ||
        _selectedRole == UserRole.seniorMentor;

    return AuthShell(
      title: 'Signup',
      subtitle: 'Submit details for admin approval',
      formChild: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Position *',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            RoleSelector(
              selectedRole: _selectedRole,
              onRoleSelected: (role) {
                setState(() => _selectedRole = role);
              },
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _firstNameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'First Name *',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Required'
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lastNameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Last Name *'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Required'
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            if (isMentorType) ...[
              TextFormField(
                controller: _qualificationController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Qualification *',
                  prefixIcon: Icon(Icons.school_outlined),
                ),
                validator: (value) =>
                    (value == null || value.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _villageController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Village *'),
                      validator: (value) =>
                          (value == null || value.isEmpty) ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _clusterController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Cluster *'),
                      validator: (value) =>
                          (value == null || value.isEmpty) ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _schoolController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'School *',
                  prefixIcon: Icon(Icons.location_city_outlined),
                ),
                validator: (value) =>
                    (value == null || value.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
            ],

            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Phone Number *',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              validator: (value) {
                final phone = value?.trim() ?? '';
                if (phone.isEmpty) return 'Phone Number is required';
                if (!Validators.isValidPhone(phone))
                  return 'Enter a valid phone number';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Password *',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              validator: (value) {
                if (value == null || value.isEmpty)
                  return 'Password is required';
                if (value.length < 6) return 'At least 6 characters';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm Password *',
                prefixIcon: Icon(Icons.lock_person_outlined),
              ),
              validator: (value) {
                if (value != _passwordController.text)
                  return 'Passwords do not match';
                return null;
              },
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _onSignupPressed,
                child: const Text('Signup'),
              ),
            ),
          ],
        ),
      ),
      footer: _buildFooter(),
    );
  }

  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Already have an account? '),
        TextButton(
          onPressed: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
            );
          },
          child: const Text('Log In'),
        ),
      ],
    );
  }
}
