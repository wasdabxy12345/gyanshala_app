import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/auth_provider.dart';

import '../../../../core/utils/validators.dart';
import '../widgets/auth_shell.dart';
import 'otp_verification_screen.dart';
import 'reset_password_screen.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  // final _authRepository = AuthRepositoryImpl.instance;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _onGenerateOtpPressed() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    try {
      final identifier = _phoneController.text.trim();
      await ref
          .read(authRepositoryProvider)
          .sendOtp(
            identifier: _phoneController.text.trim(),
            requireApprovedSignup: false,
          );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OtpVerificationScreen(
            identifier: identifier,
            title: 'OTP Verification',
            subtitle: 'Enter OTP sent on registered phone number',
            onVerified: () async {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => ResetPasswordScreen(
                    identifier: identifier,
                    title: 'Reset Password',
                    subtitle: 'Create a new password for your account',
                    successMessage: 'Password reset successful',
                  ),
                ),
              );
            },
          ),
        ),
      );
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
      title: 'Forgot Password',
      subtitle: 'Enter registered phone number',
      formChild: Form(
        key: _formKey,
        child: Column(
          children: [
            TextFormField(
              controller: _phoneController,
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
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _onGenerateOtpPressed,
                child: const Text('Generate OTP'),
              ),
            ),
          ],
        ),
      ),
      footer: const SizedBox.shrink(),
    );
  }
}
