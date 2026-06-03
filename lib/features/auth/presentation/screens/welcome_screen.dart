import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/auth_provider.dart';
import 'package:gyanshala_app/core/providers/inactivity_provider.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:gyanshala_app/core/utils/update_checker.dart';
import 'package:gyanshala_app/features/auth/presentation/screens/login_screen.dart';
import 'package:gyanshala_app/features/auth/presentation/screens/signup_screen.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
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
  String _appVersion = "Loading...";

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _loadAppVersion();

    if (widget.showInactivityLogoutMessage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showInactivityLogoutMessage();
        }
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _runGitHubUpdateCheck();
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

    if (AppConfig.useDevBypass) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_id');
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
      return;
    }
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

  Future<void> _runGitHubUpdateCheck() async {
    final downloadUrl = await UpdateChecker.checkForUpdate();
    if (downloadUrl != null && mounted) {
      _showUpdateDialog(downloadUrl);
    }
  }

  void _showUpdateDialog(String downloadUrl) {
    bool isDownloading = false;
    double downloadProgress = 0.0;
    String statusMessage = "A new version of Gyanshala is available. Please update to continue.";
    http.Client? client;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Update Available'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(statusMessage),
                  if (isDownloading) ...[
                    const SizedBox(height: 20),
                    LinearProgressIndicator(value: downloadProgress),
                    const SizedBox(height: 10),
                    Text(
                      '${(downloadProgress * 100).toStringAsFixed(0)}% Downloaded',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
              actions: isDownloading
                  ? []
                  : [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
                      ElevatedButton(
                        onPressed: () async {
                          setDialogState(() {
                            isDownloading = true;
                            statusMessage = "Downloading update file. Please wait...";
                          });

                          try {
                            client = http.Client();
                            final request = http.Request('GET', Uri.parse(downloadUrl));
                            final response = await client!.send(request);

                            if (response.statusCode != 200) {
                              throw Exception('Server error: ${response.statusCode}');
                            }

                            final contentLength = response.contentLength ?? 0;
                            final directory = await getTemporaryDirectory();
                            final apkPath = '${directory.path}/gyanshala_update.apk';
                            final file = File(apkPath);
                            if (await file.exists()) {
                              await file.delete();
                            }

                            List<int> bytes = [];

                            response.stream.listen(
                              (chunk) {
                                bytes.addAll(chunk);
                                if (contentLength > 0) {
                                  setDialogState(() {
                                    downloadProgress = bytes.length / contentLength;
                                  });
                                }
                              },
                              onDone: () async {
                                await file.writeAsBytes(bytes);
                                client?.close();

                                setDialogState(() {
                                  statusMessage = "Opening installer...";
                                });
                                if (mounted) Navigator.pop(context);
                                await OpenFilex.open(apkPath);
                              },
                              onError: (error) {
                                client?.close();
                                setDialogState(() {
                                  isDownloading = false;
                                  statusMessage = "Download stream interrupted.";
                                });
                              },
                              cancelOnError: true,
                            );
                          } catch (e) {
                            client?.close();
                            setDialogState(() {
                              isDownloading = false;
                              statusMessage = "Failed to launch network download.";
                            });
                          }
                        },
                        child: const Text('Update Now'),
                      ),
                    ],
            );
          },
        );
      },
    );
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          if (kIsWeb && (packageInfo.version.isEmpty || packageInfo.version.contains('undefined'))) {
            _appVersion = '0.0.1';
          } else {
            _appVersion = packageInfo.version;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _appVersion = '0.0.1');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWeb = constraints.maxWidth > 800;

            if (isWeb) {
              return _buildWebLayout(context, constraints.maxWidth);
            }
            return _buildMobileLayout(context);
          },
        ),
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 24.0, bottom: 60.0),
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
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  color: AppTheme.textPrimary,
                ),
              ),

              const SizedBox(height: 6),
              Container(width: 80, height: 3, color: const Color(0xFF0D47A1)),
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
                    child: const Text('Sign Up'),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    _dismissSnackBar();
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
                  },
                  child: const Text('Log In'),
                ),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Text(_appVersion, style: TextStyle(fontSize: 12, color: Colors.grey.shade500, letterSpacing: 0.5)),
          ),
        ),
      ],
    );
  }

  Widget _buildWebLayout(BuildContext context, double width) {
    final logoSize = width * 0.22;
    final buttonWidth = width * 0.18;

    return Center(
      child: SizedBox(
        width: width * 0.9,
        height: width * 0.45,
        child: Stack(
          children: [
            Positioned(
              left: (width * 0.9) / 2,
              top: width * 0.08,
              bottom: width * 0.08,
              child: Container(width: 1, color: Colors.grey.shade300),
            ),
            Row(
              children: [
                SizedBox(
                  width: (width * 0.9) / 2,
                  child: Center(
                    child: Image.asset('assets/images/shiksha_setu_logo.png', width: logoSize, fit: BoxFit.contain),
                  ),
                ),
                SizedBox(
                  width: (width * 0.9) / 2,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Student Management System',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: width * 0.02,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.0,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        SizedBox(height: width * 0.01),
                        Container(width: width * 0.08, height: 3, color: const Color(0xFF0D47A1)),
                        SizedBox(height: width * 0.03),
                        if (_state != ApprovalState.none) ...[_buildStatusCard(), SizedBox(height: width * 0.03)],
                        SizedBox(
                          width: buttonWidth,
                          child: ElevatedButton(
                            onPressed: () {
                              _dismissSnackBar();
                              Navigator.of(
                                context,
                              ).push(MaterialPageRoute(builder: (_) => const SignupScreen())).then((_) => _checkStatus());
                            },
                            child: const Text('Sign Up'),
                          ),
                        ),
                        SizedBox(height: width * 0.015),
                        SizedBox(
                          width: buttonWidth,
                          child: ElevatedButton(
                            onPressed: () {
                              _dismissSnackBar();
                              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
                            },
                            child: const Text('Log In'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  _appVersion,
                  style: TextStyle(fontSize: width * 0.009, color: Colors.grey.shade400, letterSpacing: 0.5),
                ),
              ),
            ),
          ],
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
