import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Frosts content behind this widget using Flutter's [BackdropFilter].
///
/// Use for stacked chrome (segment strips, sticky headers) instead of
/// [AdaptiveBlurView]: on iOS 26+, that widget switches to a native
/// [UiKitView] blur that does **not** sample the Flutter scene, so it reads as
/// a flat tint with no real blur.
class FlutterBackdropBlur extends StatelessWidget {
  const FlutterBackdropBlur({
    super.key,
    required this.child,
    this.sigma = 10,
  });

  final Widget child;

  /// Default matches adaptive ultra-thin material blur (~10 sigma).
  final double sigma;

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );
  }
}
