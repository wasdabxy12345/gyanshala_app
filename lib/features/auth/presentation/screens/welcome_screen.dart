import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/constants/app_strings.dart';
import 'package:gyanshala_app/core/providers/auth_provider.dart';
import 'package:gyanshala_app/core/providers/inactivity_provider.dart';
import 'package:gyanshala_app/core/services/update_service.dart';
import 'package:gyanshala_app/features/auth/presentation/screens/login_screen.dart';
import 'package:gyanshala_app/features/auth/presentation/screens/signup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'otp_verification_screen.dart';

enum ApprovalState { loading, pending, approved, denied, none }

class WelcomeScreen extends ConsumerStatefulWidget {
  final bool showPendingMessage;
  final bool showInactivityLogoutMessage;

  const WelcomeScreen({super.key, this.showPendingMessage = false, this.showInactivityLogoutMessage = false});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  ApprovalState _state = ApprovalState.loading;
  String? _pendingId;

  @override
  void initState() {
    super.initState();
    _checkStatus();

    if (widget.showInactivityLogoutMessage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showInactivityLogoutMessage();
        }
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        UpdateService.checkForUpdates(context);
      }
    });
  }

  Future<void> _showInactivityLogoutMessage() async {
    final prefs = await SharedPreferences.getInstance();
    final timeout = prefs.getInt('inactivity_timeout_minutes') ?? 999;

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('You were automatically logged out after $timeout minutes of inactivity.'),
        backgroundColor: Color(0xFF00afef),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        action: SnackBarAction(
          label: 'Dismiss',
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );

    // Reset the inactivity logout flag
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        ref.read(inactivityLogoutProvider.notifier).state = false;
      }
    });
  }

  Future<void> _checkStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('pending_id');

    if (!mounted) return;

    if (id == null || id.isEmpty) {
      setState(() {
        _state = ApprovalState.none;
        _pendingId = null;
      });
      return;
    }

    setState(() {
      _pendingId = id;
      _state = ApprovalState.loading;
    });

    try {
      final status = await ref.read(authRepositoryProvider).getSignupStatus(id).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      setState(() {
        if (status == 'approved') {
          _state = ApprovalState.approved;
        } else if (status == 'denied' || status == 'not_found') {
          _state = ApprovalState.denied;
        } else {
          _state = ApprovalState.pending;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _state = ApprovalState.none);
      }
    }
  }

  Future<void> _clearPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_id');
    _checkStatus();
  }

  void _dismissSnackBar() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  Future<void> _handleNavigateToOtp() async {
    if (_pendingId == null) return;
    _dismissSnackBar();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OtpVerificationScreen(
          identifier: _pendingId!,
          title: 'Verify Phone',
          subtitle: 'Request and enter the OTP sent to your phone',
          onVerified: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('pending_id');
            if (!mounted) return;
            Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: MediaQuery.of(context).size.height * 0.03),

              Image.asset(
                'assets/images/shiksha_setu_logo.png',
                width: MediaQuery.of(context).size.width * 0.75,
                fit: BoxFit.contain,
              ),

              SizedBox(height: MediaQuery.of(context).size.height * 0.13),

              Text(
                'Student Management System',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 2.0, color: const Color(0xFF0D47A1)),
              ),

              const SizedBox(height: 6),

              Container(width: 80, height: 3, color: Color(0xFF0D47A1)),

              const SizedBox(height: 6),

              SizedBox(height: MediaQuery.of(context).size.height * 0.13),

              if (_state != ApprovalState.none) ...[
                _buildStatusCard(),
                SizedBox(height: MediaQuery.of(context).size.height * 0.13),
              ],

              if (_state == ApprovalState.none) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      _dismissSnackBar();

                      Navigator.of(
                        context,
                      ).push(MaterialPageRoute(builder: (_) => const SignupScreen())).then((_) => _checkStatus());
                    },
                    child: const Text(AppStrings.signUp),
                  ),
                ),

                const SizedBox(height: 16),
              ],

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    _dismissSnackBar();

                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
                  },
                  child: const Text(AppStrings.logIn),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    Color bgColor = Colors.blue.shade50;
    Color borderColor = Colors.blue.shade200;
    IconData icon = Icons.info_outline;
    String message = "";
    Widget? action;

    switch (_state) {
      case ApprovalState.loading:
        message = "Checking your signup status...";
        icon = Icons.sync;
        break;
      case ApprovalState.pending:
        bgColor = Colors.amber.shade50;
        borderColor = Colors.amber.shade200;
        icon = Icons.timer_outlined;
        message = "Your signup is pending admin approval.";
        action = TextButton.icon(
          onPressed: () {
            _dismissSnackBar();
            _checkStatus();
          },
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text("Refresh"),
        );
        break;
      case ApprovalState.approved:
        bgColor = Colors.green.shade50;
        borderColor = Colors.green.shade200;
        icon = Icons.check_circle_outline;
        message = "Approved! Verify your phone to continue.";
        action = ElevatedButton(
          onPressed: () {
            _dismissSnackBar();
            _handleNavigateToOtp();
          },
          style: ElevatedButton.styleFrom(visualDensity: VisualDensity.compact),
          child: const Text("Verify Phone via SMS OTP"),
        );
        break;
      case ApprovalState.denied:
        bgColor = Colors.red.shade50;
        borderColor = Colors.red.shade200;
        icon = Icons.error_outline;
        message = "Your signup request was declined.";
        action = TextButton(
          onPressed: () {
            _dismissSnackBar();
            _clearPending();
          },
          child: const Text("Clear & Try Again"),
        );
        break;
      case ApprovalState.none:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (_state == ApprovalState.loading)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(icon, color: borderColor.withValues(alpha: 1.0), size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (action != null) ...[const SizedBox(height: 12), action],
        ],
      ),
    );
  }
}
