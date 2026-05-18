import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';

/// Flutter backdrop glass tuned to read like the native shell tab bar capsule.
///
/// Native UITabBar uses `systemUltraThinMaterial` plus `systemBackground` at ~80%
/// opacity — this stack adds a brighter white wash on top of the blur so the
/// search pill matches the tab bar's light frosted look (not smoky grey).
class TabBarGlassSurface extends StatelessWidget {
  const TabBarGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.height,
    this.width,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double? height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final isDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final colors = Theme.of(context).colorScheme;
    final surface = colors.surface;
    // Solid separator stroke (HIG uses semantic separators, not low-alpha outlines).
    final borderColor = colors.outline;

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        height: height,
        width: width ?? double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            BackdropFilter(
              filter: BlurStyle.systemUltraThinMaterial.toImageFilter(),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [
                            Colors.white.withValues(alpha: 0.06),
                            Colors.white.withValues(alpha: 0.08),
                            Colors.white.withValues(alpha: 0.06),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.42),
                            Colors.white.withValues(alpha: 0.52),
                            Colors.white.withValues(alpha: 0.42),
                          ],
                  ),
                ),
              ),
            ),
            // Mirrors UITabBarAppearance backgroundColor @ ~0.8 on light.
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                color: isDark
                    ? surface.withValues(alpha: 0.38)
                    : Colors.white.withValues(alpha: 0.58),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? [
                          Colors.white.withValues(alpha: 0.06),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.04),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.28),
                          Colors.white.withValues(alpha: 0.10),
                          Colors.white.withValues(alpha: 0.06),
                        ],
                ),
              ),
            ),
            // Hairline so the pill reads on a plain background before scroll blur.
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  border: Border.all(color: borderColor, width: 1),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
