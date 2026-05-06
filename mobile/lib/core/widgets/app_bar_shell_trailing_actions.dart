import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

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
  return [
    AppOverflowMenu(tint: tint),
    AppBarAvatar(iconOnly: true, tint: tint),
  ];
}
