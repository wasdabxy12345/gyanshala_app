import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/auth_shell.dart';
import 'login_screen.dart';
import 'otp_verification_screen.dart';

enum ApprovalState { loading, pending, approved, denied, error }

class SignupVerificationScreen extends ConsumerStatefulWidget {
  final String? identifier;
  final String? password;

  const SignupVerificationScreen({super.key, this.identifier, this.password});

  @override
  ConsumerState<SignupVerificationScreen> createState() =>
      _SignupVerificationScreenState();
}

class _SignupVerificationScreenState
    extends ConsumerState<SignupVerificationScreen> {
  String? _persistedIdentifier;
  ApprovalState _state = ApprovalState.loading;

  @override
  void initState() {
    super.initState();
    _loadAndCheckStatus();
  }

  Future<void> _loadAndCheckStatus() async {
    final prefs = await SharedPreferences.getInstance();

    final String? idToUse = widget.identifier ?? prefs.getString('pending_id');

    if (idToUse == null || idToUse.isEmpty) {
      debugPrint("Error: No identifier found in widget or storage");
      setState(() => _state = ApprovalState.error);
      return;
    }

    await prefs.setString('pending_id', idToUse);

    _persistedIdentifier = widget.identifier ?? prefs.getString('pending_id');

    setState(() {
      _persistedIdentifier = idToUse;
    });

    if (_persistedIdentifier == null) {
      setState(() => _state = ApprovalState.error);
      return;
    }

    if (widget.identifier != null) {
      await prefs.setString('pending_id', widget.identifier!);
    }

    _fetchStatus();
  }

  Future<void> _fetchStatus() async {
    setState(() => _state = ApprovalState.loading);
    try {
      final status = await ref
          .read(authRepositoryProvider)
          .getSignupStatus(_persistedIdentifier!);
      setState(() {
        if (status == 'approved') {
          _state = ApprovalState.approved;
        } else if (status == 'denied')
          _state = ApprovalState.denied;
        else
          _state = ApprovalState.pending;
      });
    } catch (e) {
      debugPrint("DEBUG: Status fetch failed because: $e");
      setState(() => _state = ApprovalState.error);
    }
  }

  bool _isSendingOtp = false;

  Future<void> _handleSendOtp() async {
    if (_isSendingOtp || _persistedIdentifier == null) return;

    setState(() => _isSendingOtp = true);

    try {
      await ref
          .read(authRepositoryProvider)
          .sendOtp(
            identifier: _persistedIdentifier!,
            requireApprovedSignup: true,
          );

      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            identifier: _persistedIdentifier!,
            title: 'Verify Phone',
            onVerified: () async {
              try {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('pending_id');

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Account verified! Please login with your password.",
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                }

                await Future.delayed(const Duration(seconds: 2));

                if (!mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
                );
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Finalizing failed: ${e.toString()}"),
                    ),
                  );
                }
              }
            },
            subtitle: 'Enter OTP sent to your phone',
          ),
        ),
      );
    } catch (e) {
      setState(() => _isSendingOtp = false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: _getTitle(),
      subtitle: _getSubtitle(),
      formChild: Column(
        mainAxisSize: MainAxisSize.min,
        children: [_buildContent()],
      ),
      footer: const SizedBox.shrink(),
    );
  }

  String _getTitle() {
    switch (_state) {
      case ApprovalState.loading:
        return "Checking Status";
      case ApprovalState.pending:
        return "Request Pending";
      case ApprovalState.approved:
        return "Signup Approved";
      case ApprovalState.denied:
        return "Request Denied";
      case ApprovalState.error:
        return "No Session Found";
    }
  }

  String _getSubtitle() {
    if (_persistedIdentifier == null) {
      return "Please start the signup process first.";
    }
    switch (_state) {
      case ApprovalState.pending:
        return "Admin is reviewing your details for $_persistedIdentifier.";
      case ApprovalState.approved:
        return "You can now verify your phone number.";
      case ApprovalState.denied:
        return "Your request was declined by the admin.";
      default:
        return "Connecting to server...";
    }
  }

  Widget _buildContent() {
    if (_state == ApprovalState.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        if (_state == ApprovalState.pending)
          ElevatedButton(
            onPressed: _fetchStatus,
            child: const Text("Refresh Status"),
          ),
        if (_state == ApprovalState.approved)
          ElevatedButton(
            onPressed: _handleSendOtp,
            child: const Text("Send OTP"),
          ),
        if (_state == ApprovalState.error)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Go Back"),
          ),
      ],
    );
  }
}
