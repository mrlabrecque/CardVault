import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';

/// List-row chrome wrapping [AdaptiveCard]: 12pt corners and default horizontal gutters.
/// Optional [highlightBorderColor] for emphasized rows (e.g. wishlist alerts).
class AdaptiveListCard extends StatelessWidget {
  const AdaptiveListCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    this.color,
    this.clipBehavior = Clip.antiAlias,
    this.cornerRadius = 12,
    this.highlightBorderColor,
    this.highlightBorderWidth = 1.5,
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final Clip clipBehavior;
  final double cornerRadius;
  final Color? highlightBorderColor;
  final double highlightBorderWidth;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(cornerRadius);
    final core = AdaptiveCard(
      margin: EdgeInsets.zero,
      borderRadius: radius,
      clipBehavior: clipBehavior,
      color: color,
      child: child,
    );

    if (highlightBorderColor != null) {
      return Container(
        margin: margin,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: highlightBorderColor!, width: highlightBorderWidth),
        ),
        clipBehavior: Clip.antiAlias,
        child: core,
      );
    }

    return AdaptiveCard(
      margin: margin,
      borderRadius: radius,
      clipBehavior: clipBehavior,
      color: color,
      child: child,
    );
  }
}

