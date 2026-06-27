import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/models/user_role.dart';
import 'package:gyanshala_app/core/providers/auth_provider.dart';
import 'package:gyanshala_app/features/dashboard/presentation/screens/admin_dashboard_screen.dart';
import 'package:gyanshala_app/features/dashboard/presentation/screens/mentor_bv8_dashboard_screen.dart';
import 'package:gyanshala_app/features/dashboard/presentation/screens/shiksha_mitra_dashboard_screen.dart';

import '../../../../core/utils/validators.dart';
import '../widgets/auth_shell.dart';
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
  bool _isLoading = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _onLoginPressed() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    try {
      final authRepo = ref.read(authRepositoryProvider);
      final user = await authRepo.login(identifier: _identifierController.text.trim(), password: _passwordController.text);
      final name = (user.firstName ?? '').trim().isEmpty ? 'User' : user.firstName!.trim();
      if (!mounted) return;
      Widget nextScreen;
      final userRole = UserRole.fromString(user.role);

      switch (userRole) {
        case UserRole.admin:
          nextScreen = AdminDashboardScreen(adminName: name);
          break;
        case UserRole.mentorBV8:
          nextScreen = MentorBv8DashboardScreen(mentorName: name);
          break;
        case UserRole.shikshaMitra38:
        case UserRole.shikshaMitra910:
          nextScreen = ShikshaMitraDashboardScreen(shikshaMitraName: name);
          break;
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Welcome back, $name!')));

      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => nextScreen), (route) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Login',
      subtitle: 'Enter your phone number and password',
      formChild: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _identifierController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone_outlined)),
              validator: (value) {
                final phone = value?.trim() ?? '';
                if (phone.isEmpty) return 'Phone Number is required';
                if (!Validators.isValidPhone(phone)) return 'Enter a valid phone number';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Password is required';
                return null;
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ForgotPasswordScreen())),
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _onLoginPressed,
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Log In'),
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
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SignupScreen())),
            child: const Text('Sign Up'),
          ),
        ],
      ),
    );
  }
}
