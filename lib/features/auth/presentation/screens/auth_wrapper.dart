import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/auth_provider.dart';
import 'package:gyanshala_app/features/auth/presentation/screens/welcome_screen.dart';
import 'package:gyanshala_app/features/dashboard/presentation/screens/mentor_dashboard_screen.dart';

class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        if (user == null) return const WelcomeScreen(); // Show Login/Signup

        // If you want to ALWAYS show login on restart,
        // you would call ref.read(authRepositoryProvider).signOut()
        // in an initState or use a 'firstRun' flag.
        return const MentorDashboardScreen();
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => const WelcomeScreen(),
    );
  }
}
