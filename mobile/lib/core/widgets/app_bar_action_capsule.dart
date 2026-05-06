import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';

class AppBarActionCapsule extends StatelessWidget {
  const AppBarActionCapsule({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 2),
  });

  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const radius = 24.0;

    return AdaptiveBlurView(
      blurStyle: BlurStyle.systemUltraThinMaterial,
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: colors.outline.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 3),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.18),
              blurRadius: 2,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.20),
                      Colors.white.withValues(alpha: 0.04),
                    ],
                  ),
                ),
              ),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: children),
          ],
        ),
      ),
    );
  }
}
