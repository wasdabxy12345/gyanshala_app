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
      body: ShikshaMitraHomeContent(shikshaMitraName: shikshaMitraName),
    );
  }
}

class ShikshaMitraHomeContent extends StatelessWidget {
  final String shikshaMitraName;
  const ShikshaMitraHomeContent({super.key, required this.shikshaMitraName});
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Welcome, $shikshaMitraName", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 22),
            const AttendanceCard(),
            const SizedBox(height: 22),
            ActionGrid(),
          ],
        ),
      ),
    );
  }
}
