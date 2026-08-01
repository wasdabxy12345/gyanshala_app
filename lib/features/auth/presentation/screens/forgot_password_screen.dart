import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/auth_provider.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

import '../widgets/auth_shell.dart';
import 'otp_verification_screen.dart';
import 'reset_password_screen.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  String _fullPhoneNumber = '';

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
      final identifier = _fullPhoneNumber.isNotEmpty ? _fullPhoneNumber : _phoneController.text.trim();
      if (AppConfig.useDevBypass) {
        if (!mounted) return;
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
        return;
      }
      await ref.read(authRepositoryProvider).sendOtp(identifier: identifier, requireApprovedSignup: false);
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
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
            IntlPhoneField(
              controller: _phoneController,
              initialCountryCode: 'IN',
              decoration: const InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder()),
              onChanged: (phone) {
                _fullPhoneNumber = phone.completeNumber;
              },
              onCountryChanged: (country) {
                if (_phoneController.text.isNotEmpty) {
                  _fullPhoneNumber = '+${country.dialCode}${_phoneController.text.trim()}';
                }
              },
              validator: (phone) {
                if (phone == null || phone.number.trim().isEmpty) {
                  return 'Phone Number is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _onGenerateOtpPressed, child: const Text('Generate OTP')),
            ),
          ],
        ),
      ),
      footer: const SizedBox.shrink(),
    );
  }
}
