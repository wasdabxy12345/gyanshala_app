import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/auth_provider.dart';

import '../widgets/auth_shell.dart';

class OtpVerificationScreen extends ConsumerStatefulWidget {
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
  ConsumerState<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends ConsumerState<OtpVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();

  bool _isLoading = false;
  int _timerSeconds = 0;
  Timer? _timer;
  void _startTimer() {
    setState(() => _timerSeconds = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timerSeconds == 0) {
        timer.cancel();
      } else {
        setState(() => _timerSeconds--);
      }
    });
  }

  @override
  void dispose() {
    _otpController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (_timerSeconds > 0) return;

    setState(() => _isLoading = true);
    try {
      if (AppConfig.useDevBypass) {
        _startTimer();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("[DEV MODE] Bypass active: Enter '123456' to proceed.")));
        return;
      }
      await ref.read(authRepositoryProvider).sendOtp(identifier: widget.identifier, requireApprovedSignup: true);
      _startTimer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("OTP request sent!")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onVerifyPressed() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);

    try {
      if (AppConfig.useDevBypass) {
        if (mounted) {
          await widget.onVerified();
        }
        return;
      }
      await ref.read(authRepositoryProvider).verifyOtp(identifier: widget.identifier, otp: _otpController.text.trim());
      if (!mounted) return;
      await widget.onVerified();
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
      title: widget.title,
      subtitle: widget.subtitle,
      formChild: Form(
        key: _formKey,
        child: Column(
          children: [
            TextFormField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'OTP', prefixIcon: Icon(Icons.password_outlined)),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'OTP is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_isLoading || _timerSeconds > 0) ? null : _sendOtp,
                child: Text(_timerSeconds > 0 ? "Resend OTP in ${_timerSeconds}s" : "Send OTP"),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _onVerifyPressed,
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(widget.buttonText),
              ),
            ),
          ],
        ),
      ),
      footer: const SizedBox.shrink(),
    );
  }
}
