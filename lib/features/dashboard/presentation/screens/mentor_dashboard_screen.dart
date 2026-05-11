import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/features/settings/presentation/views/settings_screen.dart';

import '../widgets/action_grid.dart';
import '../widgets/attendance_card.dart';

class MentorDashboardScreen extends ConsumerWidget {
  final String mentorName;
  const MentorDashboardScreen({super.key, required this.mentorName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        title: const Text("GS + UNM Portal"),
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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Welcome, ${mentorName.trim().isEmpty ? 'Mentor' : mentorName}",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            AttendanceCard(),
            SizedBox(height: 24),
            Text("Quick Actions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            SizedBox(height: 12),
            ActionGrid(),
          ],
        ),
      ),
    );
  }
}
