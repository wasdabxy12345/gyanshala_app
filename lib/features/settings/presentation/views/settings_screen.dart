import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:gyanshala_app/features/auth/presentation/screens/welcome_screen.dart';
import 'package:gyanshala_app/features/settings/presentation/views/edit_profile_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text("Edit Profile"),
            onTap: () async {
              // 1. Fetch the latest profile data from Supabase
              final supabase = ref.read(supabaseClientProvider);
              final user = supabase.auth.currentUser;

              if (user == null) return;

              final data = await supabase
                  .from('profiles')
                  .select()
                  .eq('id', user.id)
                  .single();

              if (context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EditProfileScreen(initialData: data),
                  ),
                );
              }
            },
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
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text("Cancel"),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(context, true), // This returns 'true'
                      child: const Text("Logout"),
                    ),
                  ],
                ),
              );

              // If the user clicked 'Logout', confirm will be true
              if (confirm == true) {
                try {
                  await ref.read(supabaseClientProvider).auth.signOut();

                  // Force navigation to WelcomeScreen if your Auth wrapper doesn't do it automatically
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (context) => const WelcomeScreen(),
                      ),
                      (route) => false,
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Error logging out: $e")),
                    );
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
