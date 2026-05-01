import 'package:flutter/material.dart';
import 'package:gyanshala_app/core/models/user_model.dart';

class RoleSelector extends StatelessWidget {
  const RoleSelector({
    super.key,
    required this.selectedRole,
    required this.onRoleSelected,
  });

  final UserRole selectedRole;
  final ValueChanged<UserRole> onRoleSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: UserRole.values.map((role) {
        final isSelected = role == selectedRole;
        return ChoiceChip(
          label: Text(role.label),
          selected: isSelected,
          onSelected: (_) => onRoleSelected(role),
          selectedColor: Theme.of(context).colorScheme.primary,
          backgroundColor: const Color(0xFFEAF3FF),
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF1B2A41),
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : const Color(0xFFBFD8F5),
            ),
          ),
          showCheckmark: false,
        );
      }).toList(),
    );
  }
}
