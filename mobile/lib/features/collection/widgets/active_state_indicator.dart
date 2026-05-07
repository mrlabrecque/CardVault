import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Non-interactive "current state" pill that mirrors a disabled `AdaptiveButton`
/// (e.g. "In Collection", "In Wishlist").
///
/// We can't just pass `enabled: false` to `AdaptiveButton.child` on iOS 26+:
/// the native UIKit button dims its background but the overlaid Flutter
/// text/icon stays at full opacity, leaving bright white text floating on a
/// washed-out background. Instead, we render a non-interactive [Material]
/// that matches a disabled filled control beside an [AdaptiveButton]: same height,
/// continuous-corner capsule shape, and horizontal insets comparable to
/// `UIButton.Configuration` defaults.
class ActiveStateIndicator extends StatelessWidget {
  const ActiveStateIndicator({
    super.key,
    required this.icon,
    required this.label,
    this.animateIcon = false,
  });

  final IconData icon;
  final String label;

  /// When true, plays a one-shot elastic scale-in on the icon — useful for
  /// the moment a user transitions from "Add to X" to "In X".
  final bool animateIcon;

  // Native iOS 26 medium control geometry (see iOS26ButtonView.swift —
  // `getHeightForSize` and the `UIButton.Configuration.contentInsets`).
  // `cornerStyle = .dynamic` on a 36pt-tall control renders effectively as a
  // capsule, so we mirror that with `radius == height / 2`. HIG keeps body-
  // weight 15pt labels for control titles.
  static const double _height = 36;
  static const double _radius = _height / 2;
  static const double _horizontalPadding = 16;
  static const double _fontSize = 15;
  static const FontWeight _fontWeight = FontWeight.w500;
  static const double _disabledOpacity = 0.5;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: 16, color: Colors.white);

    return Opacity(
      opacity: _disabledOpacity,
      child: Container(
        height: _height,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(_radius),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (animateIcon)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                curve: Curves.elasticOut,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: iconWidget,
              )
            else
              iconWidget,
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textHeightBehavior: const TextHeightBehavior(
                  applyHeightToFirstAscent: false,
                  applyHeightToLastDescent: false,
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: _fontWeight,
                  fontSize: _fontSize,
                  height: 1.0,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
