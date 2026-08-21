import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/auth_provider.dart';

import '../widgets/auth_shell.dart';
import 'login_screen.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({
    super.key,
    required this.identifier,
    this.title = 'Set Password',
    this.subtitle = 'Create your account password',
    this.successMessage = 'Password saved successfully',
  });

  final String identifier;
  final String title;
  final String subtitle;
  final String successMessage;

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _onResetPressed() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    try {
      await ref.read(authRepositoryProvider).updatePassword(identifier: widget.identifier, password: _passwordController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.successMessage)));
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute<void>(builder: (_) => const LoginScreen()), (_) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: widget.title,
      subtitle: widget.subtitle,
      formChild: Form(
        key: _formKey,
        child: Column(
          children: [
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: InputDecoration(
                labelText: 'Password *',
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
                final hasMinLength = value.length >= 8;
                final hasUppercase = value.contains(RegExp(r'[A-Z]'));
                final hasLowercase = value.contains(RegExp(r'[a-z]'));
                final hasDigit = value.contains(RegExp(r'[0-9]'));
                final hasSpecialChar = value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
                List<String> missingEnglish = [];
                List<String> missingGujarati = [];
                if (!hasMinLength) {
                  missingEnglish.add('at least 8 characters');
                  missingGujarati.add('ઓછામાં ઓછા 8 અક્ષરો');
                }
                if (!hasUppercase) {
                  missingEnglish.add('an uppercase letter');
                  missingGujarati.add('મોટો અક્ષર');
                }
                if (!hasLowercase) {
                  missingEnglish.add('a lowercase letter');
                  missingGujarati.add('નાનો અક્ષર');
                }
                if (!hasDigit) {
                  missingEnglish.add('a number');
                  missingGujarati.add('નંબર');
                }
                if (!hasSpecialChar) {
                  missingEnglish.add('a special character');
                  missingGujarati.add('વિશેષ ચિહ્ન');
                }
                if (missingEnglish.isNotEmpty) {
                  String englishMsg = 'Password must include ${_formatEnglishList(missingEnglish)}.';
                  String gujaratiMsg = 'પાસવર્ડમાં ${_formatGujaratiList(missingGujarati)} હોવું જોઈએ.';
                  return '$englishMsg\n$gujaratiMsg';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: InputDecoration(
                labelText: 'Confirm Password *',
                prefixIcon: Icon(Icons.lock_person_outlined),
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () {
                    setState(() {
                      _obscureConfirmPassword = !_obscureConfirmPassword;
                    });
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please confirm your password';
                }
                if (value != _passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _onResetPressed, child: const Text('Reset Password')),
            ),
          ],
        ),
      ),
      footer: const SizedBox.shrink(),
    );
  }

  String _formatEnglishList(List<String> items) {
    if (items.length == 1) return items[0];
    if (items.length == 2) return '${items[0]} and ${items[1]}';
    return '${items.sublist(0, items.length - 1).join(', ')}, and ${items.last}';
  }

  String _formatGujaratiList(List<String> items) {
    if (items.length == 1) return items[0];
    if (items.length == 2) return '${items[0]} અને ${items[1]}';
    return '${items.sublist(0, items.length - 1).join(', ')}, અને ${items.last}';
  }
}
