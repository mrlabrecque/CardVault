import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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

  static const _quickActions = <AdaptivePopupMenuEntry>[
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: AdaptivePopupMenuButton.icon<String>(
        icon: 'ellipsis.circle',
        tint: tint ?? Colors.white,
        buttonStyle: buttonStyle,
        items: _quickActions,
        onSelected: (_, entry) {
          final route = entry.value;
          if (route == null) return;
          context.go(route);
        },
      ),
    );
  }
}
