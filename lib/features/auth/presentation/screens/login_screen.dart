import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/models/user_role.dart';
import 'package:gyanshala_app/core/providers/auth_provider.dart';
import 'package:gyanshala_app/features/dashboard/presentation/screens/admin_dashboard_screen.dart';
import 'package:gyanshala_app/features/dashboard/presentation/screens/mentor_bv8_dashboard_screen.dart';
import 'package:gyanshala_app/features/dashboard/presentation/screens/shiksha_mitra_dashboard_screen.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

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
  String _fullPhoneNumber = '';
  bool _isLoading = false;
  bool _obscurePassword = true;

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
    ScaffoldMessenger.of(context).clearSnackBars();
    try {
      final authRepo = ref.read(authRepositoryProvider);
      final identifier = _fullPhoneNumber.isNotEmpty ? _fullPhoneNumber : _identifierController.text.trim();
      final user = await authRepo.login(identifier: identifier, password: _passwordController.text);

      final name = (user.firstName ?? '').trim().isEmpty ? 'User' : user.firstName!.trim();
      final userRole = UserRole.fromString(user.role);

      if (kIsWeb && !kDebugMode && userRole != UserRole.admin) {
        await authRepo.signOut();
        throw Exception('Access Denied: Only Administrator accounts can log in via the web platform.');
      }

      if (!mounted) return;
      Widget nextScreen;
      switch (userRole) {
        case UserRole.admin:
          nextScreen = AdminDashboardScreen(adminName: name);
          break;
        case UserRole.designTeamSS:
        case UserRole.designTeamGS:
        case UserRole.fieldCoordinator:
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

      final errorStr = e.toString().toLowerCase();

      final String displayMessage;
      if (errorStr.contains('no account found'))
        displayMessage = 'Incorrect phone number. Please check and try again.\nખોટો ફોન નંબર. કૃપા કરીને તપાસીને ફરી પ્રયાસ કરો.';
      else if (errorStr.contains('invalid login credentials') || errorStr.contains('password') || errorStr.contains('wrong'))
        displayMessage = 'Incorrect password. Please try again.\nખોટો પાસવર્ડ. કૃપા કરીને ફરી પ્રયાસ કરો.';
      else
        displayMessage = e.toString().replaceFirst('Exception: ', '');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(displayMessage),
          duration: const Duration(seconds: 13),
          action: SnackBarAction(
            label: 'Dismiss',
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
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
            if (AppConfig.hideCountryCodeSelector)
              TextFormField(
                controller: _identifierController,
                decoration: InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder()),
                onChanged: (phone) {
                  _fullPhoneNumber = phone;
                },
                validator: (phone) {
                  if (phone == null || phone.trim().isEmpty) return 'Phone Number is required';
                  return null;
                },
                keyboardType: TextInputType.phone,
              )
            else
              IntlPhoneField(
                controller: _identifierController,
                initialCountryCode: 'IN',
                decoration: const InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder()),
                onChanged: (phone) {
                  _fullPhoneNumber = phone.completeNumber;
                },
                onCountryChanged: (country) {
                  if (_identifierController.text.isNotEmpty) {
                    _fullPhoneNumber = '+${country.dialCode}${_identifierController.text.trim()}';
                  }
                },
                validator: (phone) {
                  if (phone == null || phone.number.trim().isEmpty) return 'Phone Number is required';
                  return null;
                },
              ),

            const SizedBox(height: 14),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
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
