import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/widgets/dashboard_header.dart';
import 'package:gyanshala_app/features/settings/presentation/views/settings_screen.dart';

import '../widgets/action_grid.dart';
import '../widgets/attendance_card.dart';

class MentorBv8DashboardScreen extends ConsumerWidget {
  final String mentorName;
  const MentorBv8DashboardScreen({super.key, required this.mentorName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Gyan Shala UNM Foundation Shiksha Setu App",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 37),
        ),
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
      body: HomeContent(mentorName: mentorName),
    );
  }
}

class HomeContent extends StatelessWidget {
  final String mentorName;
  const HomeContent({super.key, required this.mentorName});

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
            Text("Welcome, $mentorName", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
