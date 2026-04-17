import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';

import '../widgets/action_grid.dart';
import '../widgets/attendance_card.dart';

class MentorDashboardScreen extends ConsumerStatefulWidget {
  const MentorDashboardScreen({super.key});

  @override
  ConsumerState<MentorDashboardScreen> createState() =>
      _MentorDashboardScreenState();
}

class _MentorDashboardScreenState extends ConsumerState<MentorDashboardScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("GS + UNM Portal"),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {
              // Quick Sign Out for testing
              ref.read(supabaseClientProvider).auth.signOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            "Welcome, Mentor",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // GPS Check-in Section
          const AttendanceCard(),

          const SizedBox(height: 24),
          const Text(
            "Quick Actions",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),

          // Action Grid
          const ActionGrid(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
          // Add navigation logic for reports/settings here later
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment),
            label: "Reports",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: "Settings",
          ),
        ],
      ),
    );
  }
}
