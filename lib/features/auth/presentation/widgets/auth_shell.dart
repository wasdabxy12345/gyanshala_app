import 'package:flutter/material.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';

class AuthShell extends StatelessWidget {
  const AuthShell({super.key, required this.title, required this.subtitle, required this.formChild, required this.footer});
  final String title;
  final String subtitle;
  final Widget formChild;
  final Widget footer;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF5F9FF), Color(0xFFEAF3FF)],
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _FormPanel(title: title, subtitle: subtitle, formChild: formChild, footer: footer),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FormPanel extends StatelessWidget {
  const _FormPanel({required this.title, required this.subtitle, required this.formChild, required this.footer});
  final String title;
  final String subtitle;
  final Widget formChild;
  final Widget footer;
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(side: const BorderSide(color: AppTheme.lightBlue)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(25, 28, 25, 25),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 24),
              formChild,
              const SizedBox(height: 16),
              footer,
            ],
          ),
        ),
      ),
    );
  }
}
