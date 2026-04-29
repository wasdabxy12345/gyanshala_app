import 'package:flutter/material.dart';
import 'package:gyanshala_app/core/widgets/inactivity_wrapper.dart';
import 'package:gyanshala_app/features/auth/presentation/screens/auth_wrapper.dart';

import 'core/theme/app_theme.dart';
import 'main.dart';

class GyanshalaApp extends StatelessWidget {
  const GyanshalaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Gyanshala NGO',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AuthWrapper(),
      builder: (context, child) {
        return InactivityWrapper(child: child!);
      },
    );
  }
}
