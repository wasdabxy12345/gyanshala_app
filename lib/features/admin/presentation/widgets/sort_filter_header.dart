import 'package:flutter/material.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';

class SortableFilterableHeader extends StatelessWidget {
  final String label;
  final VoidCallback onSort;
  final VoidCallback onFilter;
  final bool isSorted;
  final bool isAscending;
  final bool hasFilter;

  const SortableFilterableHeader({
    super.key,
    required this.label,
    required this.onSort,
    required this.onFilter,
    required this.isSorted,
    required this.isAscending,
    required this.hasFilter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onSort,
              child: Row(
                children: [
                  Flexible(
                    child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Icon(isSorted ? (isAscending ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more, size: 13),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: onFilter,
            child: Icon(Icons.filter_alt, size: 13, color: hasFilter ? AppTheme.primaryBlue : Colors.grey),
          ),
        ],
      ),
    );
  }
}
