// ignore_for_file: curly_braces_in_flow_control_structures

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
  // final _authRepository = AuthRepositoryImpl.instance;
  String? _persistedIdentifier;
  ApprovalState _state = ApprovalState.loading;

  @override
  void initState() {
    super.initState();
    _loadAndCheckStatus();
  }

  Future<void> _loadAndCheckStatus() async {
    final prefs = await SharedPreferences.getInstance();

    // Priority 1: Widget argument (passed directly from Signup)
    // Priority 2: Stored preference (if returning to the app later)
    final String? idToUse = widget.identifier ?? prefs.getString('pending_id');

    if (idToUse == null || idToUse.isEmpty) {
      debugPrint("Error: No identifier found in widget or storage");
      setState(() => _state = ApprovalState.error);
      return;
    }

    // Ensure it's saved for next time
    await prefs.setString('pending_id', idToUse);

    // 1. Get identifier from widget (if coming from Signup) or Prefs (if coming from Welcome)
    _persistedIdentifier = widget.identifier ?? prefs.getString('pending_id');

    setState(() {
      _persistedIdentifier = idToUse;
    });

    if (_persistedIdentifier == null) {
      setState(() => _state = ApprovalState.error);
      return;
    }

    // 2. If we have a new identifier from a fresh signup, save it immediately
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
      debugPrint(
        "DEBUG: Status fetch failed because: $e",
      ); // CHECK THIS IN CONSOLE
      setState(() => _state = ApprovalState.error);
    }
  }

  // Inside _SignupVerificationScreenState

  bool _isSendingOtp = false;

  Future<void> _handleSendOtp() async {
    if (_isSendingOtp || _persistedIdentifier == null) return;

    setState(() => _isSendingOtp = true); // Lock the button

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
            // FIX: Use _persistedIdentifier instead of _idController
            identifier: _persistedIdentifier!,
            title: 'Verify Phone',
            onVerified: () async {
              try {
                // 2. Clean up local storage
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('pending_id');

                // 3. Show the success message
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

                // 4. Wait a moment for the user to read the message
                await Future.delayed(const Duration(seconds: 2));

                // 5. Finally, Navigate and clear the stack
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
      setState(() => _isSendingOtp = false); // Unlock on error
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
        mainAxisSize: MainAxisSize.min, // Keeps the column compact
        children: [_buildContent()],
      ),
      // Fix: Added the required footer argument
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
