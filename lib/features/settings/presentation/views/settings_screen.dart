import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/inactivity_provider.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:gyanshala_app/features/auth/presentation/screens/welcome_screen.dart';
import 'package:gyanshala_app/features/settings/presentation/views/edit_profile_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _showInactivityTimeoutDialog(BuildContext context, WidgetRef ref, int currentTimeout) {
    final timeoutOptions = [1, 2, 5, 10, 15, 20, 30];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Auto-Logout Timeout"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Select the time after which you'll be automatically logged out due to inactivity:"),
            const SizedBox(height: 16),
            RadioGroup<int>(
              groupValue: currentTimeout,
              onChanged: (value) {
                if (value != null) {
                  ref.read(setInactivityTimeoutProvider(value));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Auto-logout timeout set to $value minutes"), duration: const Duration(seconds: 2)),
                  );
                }
              },
              child: Column(
                children: timeoutOptions.map((timeout) {
                  return RadioListTile<int>(title: Text("$timeout minutes"), value: timeout);
                }).toList(),
              ),
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inactivityTimeoutAsync = ref.watch(inactivityTimeoutProvider);

    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text("Edit Profile"),
            onTap: () async {
              final supabase = ref.read(supabaseClientProvider);
              final user = supabase.auth.currentUser;

              if (user == null) return;

              final data = await supabase.from('profiles').select().eq('id', user.id).single();

              if (context.mounted) {
                Navigator.push(context, MaterialPageRoute(builder: (context) => EditProfileScreen(initialData: data)));
              }
            },
          ),
          const Divider(),
          inactivityTimeoutAsync.when(
            data: (timeout) => ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text("Auto-Logout Timeout"),
              subtitle: Text("$timeout minutes"),
              onTap: () => _showInactivityTimeoutDialog(context, ref, timeout),
            ),
            loading: () => const ListTile(
              leading: Icon(Icons.schedule),
              title: Text("Auto-Logout Timeout"),
              trailing: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (error, st) => ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text("Auto-Logout Timeout"),
              subtitle: const Text("Error loading setting"),
              onTap: () => _showInactivityTimeoutDialog(context, ref, 999),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              "Logout",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Logout"),
                  content: const Text("Are you sure you want to exit?"),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Logout")),
                  ],
                ),
              );

              if (confirm == true) {
                try {
                  await ref.read(supabaseClientProvider).auth.signOut();

                  if (context.mounted) {
                    Navigator.of(
                      context,
                    ).pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const WelcomeScreen()), (route) => false);
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error logging out: $e")));
                  }
                }
              }
            },
          ),
        ],
      ),
    );
  }
}
