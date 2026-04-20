import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/auth_provider.dart';

class InactivityWrapper extends ConsumerStatefulWidget {
  final Widget child;
  const InactivityWrapper({super.key, required this.child});

  @override
  ConsumerState<InactivityWrapper> createState() => _InactivityWrapperState();
}

class _InactivityWrapperState extends ConsumerState<InactivityWrapper> {
  Timer? _timer;

  // Set inactivity duration (e.g., 15 minutes)
  static const _inactivityDuration = Duration(minutes: 15);

  void _resetTimer() {
    _timer?.cancel();
    _timer = Timer(_inactivityDuration, _logoutUser);
  }

  void _logoutUser() {
    // This logs the user out from Supabase
    ref.read(authRepositoryProvider).signOut();

    // Optional: Show a message
    debugPrint("User logged out due to inactivity");
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
    return Listener(
      onPointerDown: (_) =>
          _resetTimer(), // Reset timer whenever screen is touched
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }
}
