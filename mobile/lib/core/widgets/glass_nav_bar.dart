import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';

PreferredSizeWidget buildGlassNavBar(
  BuildContext context, {
  Widget? title,
  List<Widget>? actions,
  Widget? leading,
  bool centerTitle = false,
  bool automaticallyImplyLeading = true,
  PreferredSizeWidget? bottom,
  bool useBlurBackground = true,
}) {
  final colors = Theme.of(context).colorScheme;
  return AppBar(
    forceMaterialTransparency: true,
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    shape: const RoundedRectangleBorder(side: BorderSide.none),
    foregroundColor: colors.onSurface,
    centerTitle: centerTitle,
    automaticallyImplyLeading: automaticallyImplyLeading,
    leading: leading,
    title: title,
    actions: actions,
    bottom: bottom,
    flexibleSpace: useBlurBackground
        ? ClipRect(
            child: AdaptiveBlurView(
              blurStyle: BlurStyle.systemUltraThinMaterial,
              child: Container(
                color: colors.surface.withValues(alpha: 0.14),
              ),
            ),
          )
        : const SizedBox.shrink(),
  );
}
