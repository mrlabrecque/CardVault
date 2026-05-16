import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/platform_utils.dart';

String compsDateRangeFilterLabel(int selectedDays) => switch (selectedDays) {
      7 => '7 days',
      30 => '30 days',
      _ => 'All time',
    };

/// Pill chip shared by sold-comps grade and period filters.
class CompsMarketFilterChip extends StatelessWidget {
  const CompsMarketFilterChip({
    super.key,
    required this.label,
    required this.isActive,
    required this.tint,
    required this.leadingIcon,
  });

  final String label;
  final bool isActive;
  final Color tint;
  final IconData leadingIcon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bgColor = isIOS
        ? (isActive
            ? tint.withValues(alpha: 0.16)
            : CupertinoColors.secondarySystemFill.resolveFrom(context))
        : (isActive ? tint.withValues(alpha: 0.12) : colors.surfaceContainerHighest);
    final borderColor = isIOS
        ? (isActive ? tint.withValues(alpha: 0.45) : Colors.transparent)
        : (isActive ? tint.withValues(alpha: 0.35) : colors.outline.withValues(alpha: 0.35));
    final textColor = isIOS
        ? (isActive ? tint : CupertinoColors.label.resolveFrom(context))
        : (isActive ? tint : colors.onSurface);

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            leadingIcon,
            size: 14,
            color: textColor.withValues(alpha: isActive ? 1 : 0.72),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            isIOS ? CupertinoIcons.chevron_down : Icons.keyboard_arrow_down_rounded,
            size: 13,
            color: textColor.withValues(alpha: 0.65),
          ),
        ],
      ),
    );

    return pill;
  }
}

/// 44pt minimum touch target (HIG) around a compact filter chip.
class _CompsFilterTapTarget extends StatelessWidget {
  const _CompsFilterTapTarget({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Align(alignment: Alignment.center, child: child),
    );
  }
}

/// Grade filter for guide sold comps (matches [CompsDateRangeFilter] styling).
class CompsGradeFilter extends StatelessWidget {
  const CompsGradeFilter({
    super.key,
    required this.gradeLabel,
    required this.menuEntries,
    required this.onSelected,
    this.isFiltered = false,
    this.enabled = true,
    this.color,
  });

  final String gradeLabel;
  final List<AdaptivePopupMenuEntry> menuEntries;
  final void Function(int index, AdaptivePopupMenuItem<String> entry) onSelected;
  /// Tinted when the user has changed away from the card's default grade.
  final bool isFiltered;
  final bool enabled;
  final Color? color;

  static IconData get _gradeIcon => isIOS
      ? CupertinoIcons.checkmark_seal
      : Icons.workspace_premium_outlined;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return AbsorbPointer(
      absorbing: !enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: AdaptivePopupMenuButton.widget<String>(
          items: menuEntries,
          buttonStyle: PopupButtonStyle.plain,
          tint: tint,
          onSelected: onSelected,
          child: _CompsFilterTapTarget(
            child: CompsMarketFilterChip(
              label: gradeLabel,
              isActive: isFiltered,
              tint: tint,
              leadingIcon: _gradeIcon,
            ),
          ),
        ),
      ),
    );
  }
}

/// Period filter for sold comps.
class CompsDateRangeFilter extends StatelessWidget {
  const CompsDateRangeFilter({
    super.key,
    required this.selectedDays,
    required this.onChanged,
    this.color,
  });

  final int selectedDays;
  final ValueChanged<int> onChanged;
  final Color? color;

  static const _options = <(int days, String label)>[
    (7, 'Last 7 days'),
    (30, 'Last 30 days'),
    (0, 'All time'),
  ];

  static IconData get _calendarIcon => isIOS
      ? CupertinoIcons.calendar
      : Icons.calendar_today_outlined;

  List<AdaptivePopupMenuEntry> _menuEntries() {
    return [
      for (final (days, label) in _options)
        AdaptivePopupMenuItem<int>(
          value: days,
          label: days == selectedDays ? '✓ $label' : label,
          icon: 'calendar',
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    final label = compsDateRangeFilterLabel(selectedDays);
    final isFiltered = selectedDays != 0;
    return AdaptivePopupMenuButton.widget<int>(
      items: _menuEntries(),
      buttonStyle: PopupButtonStyle.plain,
      tint: tint,
      onSelected: (_, entry) {
        final days = entry.value;
        if (days == null || days == selectedDays) return;
        onChanged(days);
      },
      child: _CompsFilterTapTarget(
        child: CompsMarketFilterChip(
          label: label,
          isActive: isFiltered,
          tint: tint,
          leadingIcon: _calendarIcon,
        ),
      ),
    );
  }
}
