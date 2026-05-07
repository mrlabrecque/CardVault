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

/// Circular control using the same adaptive blur + glass plate as [AppBarActionCapsule].
class AppBarGlassCircleButton extends StatelessWidget {
  const AppBarGlassCircleButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.size = 46,
    this.iconSize = 26,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final r = size / 2;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: AdaptiveBlurView(
        blurStyle: BlurStyle.systemUltraThinMaterial,
        borderRadius: BorderRadius.circular(r),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(r),
            color: colors.surface.withValues(alpha: 0.20),
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
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(r),
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
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(r),
                  onTap: onPressed,
                  child: Center(
                    child: Icon(icon, color: colors.onSurface, size: iconSize),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
