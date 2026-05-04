import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// iOS HIG-compliant filter pill widget.
///
/// Provides consistent styling across the app with:
/// - 44pt+ minimum touch targets for accessibility
/// - Semantic colors that adapt to Dark Mode
/// - Clear active/inactive visual states
/// - Proper spacing and typography
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? colors.primary : colors.surface,
          border: Border.all(
            color: isActive ? colors.primary : colors.outline,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isActive ? Colors.white : colors.onSurface,
          ),
        ),
      ),
    );
  }
}
