import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    final bgColor = isIOS
        ? (isActive
              ? colors.primary.withValues(alpha: 0.16)
              : CupertinoColors.secondarySystemFill.resolveFrom(context))
        : (isActive ? colors.primary : colors.surface);
    final borderColor = isIOS
        ? (isActive
              ? colors.primary.withValues(alpha: 0.45)
              : Colors.transparent)
        : (isActive ? colors.primary : colors.outline);
    final textColor = isIOS
        ? (isActive
              ? colors.primary
              : CupertinoColors.label.resolveFrom(context))
        : (isActive ? Colors.white : colors.onSurface);

    final pill = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );

    if (isIOS) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: CupertinoButton(
          onPressed: onTap,
          minSize: 44,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
          pressedOpacity: 0.6,
          child: Center(child: pill),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Center(
          child: pill,
        ),
      ),
    );
  }
}
