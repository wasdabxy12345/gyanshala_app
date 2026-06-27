import 'package:flutter/material.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:gyanshala_app/features/employees/presentation/screens/available_forms_screen.dart';

class ActionGrid1 extends StatelessWidget {
  ActionGrid1({super.key});

  final List<MenuItem> menuItems = [
    // const MenuItem(title: "Students", icon: Icons.group, color: Colors.red, targetScreen: StudentHubPage()),
    const MenuItem(
      title: "Monitoring and Evaluation Tools",
      icon: Icons.assignment_turned_in,
      color: Colors.amber,
      targetScreen: AvailableFormsScreen(),
    ),
    // const MenuItem(title: "Test Data", icon: Icons.bar_chart, color: Colors.green),
    // const MenuItem(title: "Monthly Reports", icon: Icons.description, color: Colors.blue),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: MediaQuery.of(context).size.width < 600 ? 2 : 4,
      crossAxisSpacing: 13,
      mainAxisSpacing: 13,
      childAspectRatio: 1.3,
      children: menuItems.map((item) => _buildMenuCard(context, item)).toList(),
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
