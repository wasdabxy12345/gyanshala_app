import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/features/settings/presentation/views/settings_screen.dart';

import '../widgets/action_grid.dart';
import '../widgets/attendance_card.dart';

class ShikshaMitraDashboardScreen extends ConsumerWidget {
  final String shikshaMitraName;
  const ShikshaMitraDashboardScreen({super.key, required this.shikshaMitraName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gyanshala app"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
            },
          ),
        ],
      ),
      body: HomeContent(shikshaMitraName: shikshaMitraName),
    );
  }
}

class HomeContent extends StatelessWidget {
  final String shikshaMitraName;
  const HomeContent({super.key, required this.shikshaMitraName});
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Welcome, $shikshaMitraName", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                const AttendanceCard(),
                const SizedBox(height: 24),
                const Text("Quick Actions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                const ActionGrid(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
