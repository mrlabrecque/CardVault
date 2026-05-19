import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Overflow destinations in the app bar ··· menu (Wishlist is not a tab).
const appShellOverflowMenuEntries = <AdaptivePopupMenuEntry>[
  AdaptivePopupMenuItem<String>(
    label: 'Wishlist',
    icon: 'bookmark',
    value: '/wishlist',
  ),
  AdaptivePopupMenuItem<String>(
    label: 'Lot Builder',
    icon: 'shippingbox',
    value: '/lot-builder',
  ),
  AdaptivePopupMenuItem<String>(
    label: 'Market Data',
    icon: 'chart.line.uptrend.xyaxis',
    value: '/market-data',
  ),
  AdaptivePopupMenuItem<String>(
    label: 'Grade Recommendations',
    icon: 'rosette',
    value: '/grading',
  ),
];

void handleAppShellOverflowSelection(
  BuildContext context,
  AdaptivePopupMenuItem<String> entry,
) {
  final route = entry.value;
  if (route == null) return;
  context.go(route);
}

class AppOverflowMenu extends StatelessWidget {
  const AppOverflowMenu({
    super.key,
    this.tint,
    this.buttonStyle = PopupButtonStyle.plain,
    this.padding = const EdgeInsets.only(right: 4),
  });

  final Color? tint;
  final PopupButtonStyle buttonStyle;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: AdaptivePopupMenuButton.icon<String>(
        icon: 'ellipsis.circle',
        tint: tint ?? Colors.white,
        buttonStyle: buttonStyle,
        items: appShellOverflowMenuEntries,
        onSelected: (_, entry) => handleAppShellOverflowSelection(context, entry),
      ),
    );
  }
}
