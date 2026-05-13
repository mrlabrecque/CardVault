import 'package:flutter/material.dart';

import 'flutter_backdrop_blur.dart';

PreferredSizeWidget buildGlassNavBar(
  BuildContext context, {
  Widget? title,
  List<Widget>? actions,
  Widget? leading,
  bool centerTitle = false,
  bool automaticallyImplyLeading = true,
  PreferredSizeWidget? bottom,
  bool useBlurBackground = true,
  double blurSigma = 10,
  double surfaceTintAlpha = 0.14,
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
            child: FlutterBackdropBlur(
              sigma: blurSigma,
              child: Container(
                color: colors.surface.withValues(alpha: surfaceTintAlpha),
              ),
            ),
          )
        : const SizedBox.shrink(),
  );
}
