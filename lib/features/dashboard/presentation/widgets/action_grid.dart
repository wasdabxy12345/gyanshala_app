import 'package:flutter/material.dart';
import 'package:gyanshala_app/features/students/presentation/student_hub_page.dart';

class ActionGrid extends StatelessWidget {
  const ActionGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.1,
      children: [
        _buildMenuCard(context, "Students", Icons.group, Colors.orange),
        _buildMenuCard(
          context,
          "Observation",
          Icons.assignment_turned_in,
          Colors.purple,
        ),
        _buildMenuCard(context, "Test Data", Icons.bar_chart, Colors.teal),
        _buildMenuCard(
          context,
          "Monthly Reports",
          Icons.description,
          Colors.indigo,
        ),
      ],
    );
  }

  Widget _buildMenuCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
  ) {
    return InkWell(
      onTap: () {
        if (title == "Students") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const StudentHubPage()),
          );
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("working on it: $title")));
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
