import 'package:flutter/material.dart';
import 'package:gyanshala_app/features/students/presentation/screens/add_student_screen.dart';

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
      childAspectRatio:
          1.1, // <--- ADD THIS: Ensures cards have a stable height
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
      // Update this inside your ActionGrid buildMenuCard method:
      onTap: () {
        if (title == "Students") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddStudentScreen()),
          );
        } else {
          // Placeholder for others
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("$title feature coming soon!")),
          );
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05), // Updated here
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1), // Updated here
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
