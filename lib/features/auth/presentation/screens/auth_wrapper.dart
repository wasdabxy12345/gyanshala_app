import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/auth_provider.dart';
import '../../../dashboard/presentation/screens/mentor_dashboard_screen.dart';
import 'login_screen.dart';

class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (data) {
        // If there is a session, the user is logged in
        if (data.session != null) {
          return const MentorDashboardScreen();
        }
        return const LoginScreen();
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, trace) => Scaffold(body: Center(child: Text("Error: $e"))),
    );
  }
}
