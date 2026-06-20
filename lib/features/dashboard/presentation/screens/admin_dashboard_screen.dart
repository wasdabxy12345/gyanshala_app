import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:gyanshala_app/core/widgets/dashboard_header.dart';
import 'package:gyanshala_app/features/admin/presentation/screens/employee_hub_page.dart';
import 'package:gyanshala_app/features/admin/presentation/screens/form_management_screen.dart';
import 'package:gyanshala_app/features/admin/presentation/screens/location_management_screen.dart';
import 'package:gyanshala_app/features/admin/presentation/screens/signup_requests_screen.dart';
import 'package:gyanshala_app/features/settings/presentation/views/settings_screen.dart';

class AdminDashboardScreen extends ConsumerWidget {
  final String adminName;
  const AdminDashboardScreen({super.key, required this.adminName});

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
      body: AdminHome(adminName: adminName),
    );
  }
}

class AdminHome extends StatelessWidget {
  final String adminName;
  const AdminHome({super.key, required this.adminName});
  @override
  Widget build(BuildContext context) {
    final List<MenuItem> menuItems = [
      const MenuItem(title: "Signup Requests", icon: Icons.how_to_reg, color: Colors.red, targetScreen: SignupRequestsScreen()),
      const MenuItem(title: "Employees", icon: Icons.groups, color: Colors.amber, targetScreen: EmployeeHubPage()),
      const MenuItem(title: "Locations", icon: Icons.map, color: Colors.green, targetScreen: LocationManagementScreen()),
      const MenuItem(title: "Forms", icon: Icons.description, color: Colors.blue, targetScreen: FormManagementScreen()),
    ];

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DashboardHeader(),
            const SizedBox(height: 50),
            Text("Welcome, $adminName", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
            const SizedBox(height: 13),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: MediaQuery.of(context).size.width < 600 ? 2 : 4,
              crossAxisSpacing: 13,
              mainAxisSpacing: 13,
              childAspectRatio: 1.3,
              children: menuItems.map((item) => _buildMenuCard(context, item)).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard(BuildContext context, MenuItem item) {
    return InkWell(
      onTap: () {
        if (item.targetScreen != null) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => item.targetScreen!));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("not yet implemented")));
        }
      },
      child: Container(
        decoration: BoxDecoration(color: AppTheme.lightBlue),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: item.color.withValues(alpha: 0.13),
              child: Icon(item.icon, color: item.color),
            ),
            const SizedBox(height: 13),
            Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class MenuItem {
  final String title;
  final IconData icon;
  final Color color;
  final Widget? targetScreen;

  const MenuItem({required this.title, required this.icon, required this.color, this.targetScreen});
}
