import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/widgets/dashboard_header.dart';
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
        title: const Text("Gyan Shala UNM Foundation Shiksha Setu App"),
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
      body: ShikshaMitraHome(shikshaMitraName: shikshaMitraName),
    );
  }
}

class ShikshaMitraHome extends StatelessWidget {
  final String shikshaMitraName;
  const ShikshaMitraHome({super.key, required this.shikshaMitraName});
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DashboardHeader(),
            const SizedBox(height: 50),
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
