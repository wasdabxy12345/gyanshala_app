import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:gyanshala_app/core/widgets/dashboard_header.dart';
import 'package:gyanshala_app/features/admin/presentation/screens/employee_hub_page.dart';
import 'package:gyanshala_app/features/admin/presentation/screens/form_management_screen.dart';
import 'package:gyanshala_app/features/admin/presentation/screens/location_management_screen.dart';
import 'package:gyanshala_app/features/admin/presentation/screens/signup_requests_screen.dart';
import 'package:gyanshala_app/features/settings/presentation/views/settings_screen.dart';
import 'package:gyanshala_app/features/students/presentation/views/student_hub_page.dart';

class AdminDashboardScreen extends ConsumerWidget {
  final String adminName;
  const AdminDashboardScreen({super.key, required this.adminName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Gyan Shala UNM Foundation Shiksha Setu App",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: MediaQuery.of(context).size.width < 842 ? 20 : 37),
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
      MenuItem(title: "Signup Requests", targetScreen: SignupRequestsScreen()),
      MenuItem(title: "Employee Hub", targetScreen: EmployeeHubPage()),
      MenuItem(title: "Locations", targetScreen: LocationManagementScreen()),
      MenuItem(title: "Monitoring and Evaluation Tools", targetScreen: FormManagementScreen()),
      MenuItem(title: "Students", targetScreen: StudentHubPage()),
    ];

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DashboardHeader(),
            const SizedBox(height: 50),
            Text(
              "Welcome, $adminName",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: MediaQuery.of(context).size.width < 842 ? 13 : 20),
            ),
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
        try {
          Navigator.push(context, MaterialPageRoute(builder: (context) => item.targetScreen));
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        }
      },
      child: Container(
        decoration: BoxDecoration(color: AppTheme.lightBlue),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600))],
        ),
      ),
    );
  }
}

class MenuItem {
  final String title;
  final Widget targetScreen;

  const MenuItem({required this.title, required this.targetScreen});
}
