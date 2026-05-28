import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/features/admin/presentation/screens/form_management_screen.dart';
import 'package:gyanshala_app/features/admin/presentation/screens/location_management_screen.dart';
import 'package:gyanshala_app/features/admin/presentation/screens/signup_requests_screen.dart';
import 'package:gyanshala_app/features/employees/presentation/screens/employee_hub_page.dart';
import 'package:gyanshala_app/features/settings/presentation/views/settings_screen.dart';

class AdminDashboardScreen extends ConsumerWidget {
  final String adminName;
  const AdminDashboardScreen({super.key, required this.adminName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("GS + UNM Admin"),
        centerTitle: true,
        backgroundColor: Color(0xFF00AFEF),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
            },
          ),
        ],
      ),
      body: AdminHomeContent(adminName: adminName),
    );
  }
}

class AdminHomeContent extends StatelessWidget {
  final String adminName;
  const AdminHomeContent({super.key, required this.adminName});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Welcome, ${adminName}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                _AdminActionTile(
                  title: "Approve Signups",
                  icon: Icons.how_to_reg,
                  color: Colors.blue,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const SignupRequestsScreen()));
                  },
                ),
                _AdminActionTile(
                  title: "Employee List and Attendance",
                  icon: Icons.groups,
                  color: Colors.purple,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const EmployeeHubPage()));
                  },
                ),
                _AdminActionTile(
                  title: "Manage Locations",
                  icon: Icons.map_outlined,
                  color: Colors.deepOrange,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const LocationManagementScreen()));
                  },
                ),
                _AdminActionTile(
                  title: "Manage Forms",
                  icon: Icons.description_outlined,
                  color: Colors.teal,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const FormManagementScreen()));
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminActionTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _AdminActionTile({required this.title, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
