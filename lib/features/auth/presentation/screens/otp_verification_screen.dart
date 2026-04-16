import 'package:flutter/material.dart';

import '../../data/repositories/auth_repository_impl.dart';
import '../widgets/auth_shell.dart';

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({
    super.key,
    required this.identifier,
    required this.title,
    required this.subtitle,
    required this.onVerified,
    this.buttonText = 'Verify OTP',
  });

  final String identifier;
  final String title;
  final String subtitle;
  final Future<void> Function() onVerified;
  final String buttonText;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  final _authRepository = AuthRepositoryImpl.instance;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _onVerifyPressed() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    try {
      debugPrint('Step 1: Verifying OTP for ${widget.identifier}...');
      await _authRepository.verifyOtp(
        identifier: widget.identifier,
        otp: _otpController.text.trim(),
      );

      debugPrint(
        'Step 2: OTP Verified successfully. Running onVerified callback...',
      );

      if (!mounted) return;

      try {
        // This is usually the updatePassword() call from your SignupVerificationScreen
        await widget.onVerified();
        debugPrint('Step 3: onVerified callback completed.');
      } catch (e) {
        // Silencing the same_password error as discussed
        if (e.toString().contains('same_password')) {
          debugPrint('Step 3: Handled same_password exception. Proceeding...');
        } else {
          rethrow;
        }
      }

      // If we got here, the process is done.
      // Note: Usually navigation happens inside onVerified,
      // but let's add a fallback check here.
      debugPrint(
        'Step 4: All steps done. If the screen did not change, check the onVerified function.',
      );
    } catch (e) {
      debugPrint('OTP Error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
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
              controller: _otpController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'OTP',
                prefixIcon: Icon(Icons.password_outlined),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'OTP is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _onVerifyPressed,
                child: Text(widget.buttonText),
              ),
            ),
          ],
        ),
      ),
      footer: const SizedBox.shrink(),
    );
  }
}
