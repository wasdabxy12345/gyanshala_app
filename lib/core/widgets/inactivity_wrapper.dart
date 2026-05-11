import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/auth_provider.dart';
import 'package:gyanshala_app/core/providers/inactivity_provider.dart';
import 'package:gyanshala_app/features/auth/presentation/screens/welcome_screen.dart';
import 'package:gyanshala_app/main.dart';

class InactivityWrapper extends ConsumerStatefulWidget {
  final Widget child;
  const InactivityWrapper({super.key, required this.child});

  @override
  ConsumerState<InactivityWrapper> createState() => _InactivityWrapperState();
}

class _InactivityWrapperState extends ConsumerState<InactivityWrapper> {
  Timer? _timer;
  Duration _getDuration(int minutes) => Duration(minutes: minutes);
  void _resetTimer() async {
    _timer?.cancel();

    final timeoutMinutes = await ref.read(inactivityTimeoutProvider.future);

    _timer = Timer(_getDuration(timeoutMinutes), _logoutUser);
  }

  void _logoutUser() async {
    ref.read(inactivityLogoutProvider.notifier).state = true;
    await ref.read(authRepositoryProvider).signOut();

    if (mounted) {
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen(showInactivityLogoutMessage: true)),
        (_) => false,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _resetTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(onPointerDown: (_) => _resetTimer(), behavior: HitTestBehavior.translucent, child: widget.child);
  }
}
