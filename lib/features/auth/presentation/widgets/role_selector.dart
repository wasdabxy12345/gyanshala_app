import 'package:flutter/material.dart';
import 'package:gyanshala_app/core/models/user_role.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';

class RoleSelector extends StatelessWidget {
  const RoleSelector({super.key, required this.selectedRole, required this.onRoleSelected, this.allowedRoles});

  final UserRole selectedRole;
  final ValueChanged<UserRole> onRoleSelected;
  final List<UserRole>? allowedRoles;

  @override
  Widget build(BuildContext context) {
    // Fallback to all roles if no specific allowed roles are provided
    final rolesToDisplay = allowedRoles ?? UserRole.values;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: rolesToDisplay.map((role) {
        final isSelected = role == selectedRole;
        return ChoiceChip(
          label: Text(role.label),
          selected: isSelected,
          onSelected: (_) => onRoleSelected(role),
          selectedColor: Theme.of(context).colorScheme.primary,
          backgroundColor: const Color(0xFFEAF3FF),
          labelStyle: TextStyle(color: isSelected ? Colors.white : const Color(0xFF1B2A41), fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: isSelected ? Theme.of(context).colorScheme.primary : AppTheme.lightBlue),
          ),
          showCheckmark: false,
        );
      }).toList(),
    );
  }
}
