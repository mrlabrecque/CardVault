import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_bar_action_capsule.dart';
import 'app_bar_avatar.dart';
import 'app_overflow_menu.dart';

/// Overflow + avatar for primary shell tabs. Hidden when this route can pop
/// (e.g. `/collection/card`, pushed tools flows) or when [omitShellTrailing]
/// is true (e.g. catalog drill-down with in-flow back).
List<Widget> appBarShellTrailingActions(
  BuildContext context, {
  bool omitShellTrailing = false,
  Color? tint,
}) {
  if (omitShellTrailing || context.canPop()) {
    return const [];
  }
  final resolvedTint = tint ?? Theme.of(context).colorScheme.onSurface;
  return [
    AppBarActionCapsule(
      children: [
        AppOverflowMenu(
          tint: resolvedTint,
          buttonStyle: PopupButtonStyle.plain,
          padding: const EdgeInsets.only(left: 4, right: 0),
        ),
        AppBarAvatar(
          iconOnly: true,
          tint: resolvedTint,
          buttonStyle: PopupButtonStyle.plain,
          padding: const EdgeInsets.only(left: 2, right: 6),
        ),
      ],
    ),
    const SizedBox(width: 8),
  ];
}
