import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/models/user_model.dart';
import 'package:gyanshala_app/core/providers/auth_provider.dart';
import 'package:gyanshala_app/features/dashboard/presentation/screens/admin_dashboard_screen.dart';
import 'package:gyanshala_app/features/dashboard/presentation/screens/mentor_dashboard_screen.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/validators.dart';
import '../widgets/auth_shell.dart';
import '../widgets/role_selector.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  // final _authRepository = AuthRepositoryImpl.instance;
  UserRole _selectedRole = UserRole.mentor;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _onLoginPressed() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    try {
      await ref
          .read(authRepositoryProvider)
          .login(
            identifier: _identifierController.text,
            password: _passwordController.text,
            role: _selectedRole.label ?? '',
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Signed in as ${_selectedRole.label ?? ''}')),
      );

      if (_selectedRole == UserRole.mentor) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MentorDashboardScreen()),
          (route) =>
              false, // This clears the login screen from the "back" history
        );
      } else if (_selectedRole == UserRole.seniorMentor) {
        // Navigator.of(context).pushAndRemoveUntil(
        //   MaterialPageRoute(
        //     builder: (_) => const SeniorMentorDashboardScreen(),
        //   ),
        //   (route) =>
        //       false, // This clears the login screen from the "back" history
        // );
      } else if (_selectedRole == UserRole.admin) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
          (route) =>
              false, // This clears the login screen from the "back" history
        );
      } else {
        // For any other roles, you can add more conditions here
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Role not recognized.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: AppStrings.loginTitle,
      subtitle: AppStrings.loginSubtitle,
      formChild: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Role',
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
            TextFormField(
              controller: _identifierController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              validator: (value) {
                final phone = value?.trim() ?? '';
                if (phone.isEmpty) {
                  return 'Phone Number is required';
                }
                if (!Validators.isValidPhone(phone)) {
                  return 'Enter a valid phone number';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: AppStrings.passwordLabel,
                prefixIcon: Icon(Icons.lock_outline),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Password is required';
                }
                if (value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ForgotPasswordScreen(),
                    ),
                  );
                },
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _onLoginPressed,
                child: const Text(AppStrings.logIn),
              ),
            ),
          ],
        ),
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('New user? '),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SignupScreen()),
              );
            },
            child: const Text(AppStrings.signUp),
          ),
        ],
      ),
    );
  }
}
