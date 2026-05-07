import 'package:flutter/material.dart';

import 'flutter_backdrop_blur.dart';

/// Shared frosted chrome: [BackdropFilter] on the Flutter scene + [ColorScheme.surface] tint.
///
/// **Two widgets to standardize on:**
/// - **FrostedChromeLayer** (this file) — blur + tint; drop into pinned slivers, sheets, or any subtree.
/// - **StickyChromeScaffold** — stack under the app bar with a measured sticky strip and `contentTopInset` for the body.
///
/// Prefer this over [AdaptiveBlurView] when content behind must blur (native iOS blur does not
/// sample the Flutter layer — see [FlutterBackdropBlur]).
class FrostedChromeLayer extends StatelessWidget {
  const FrostedChromeLayer({
    super.key,
    required this.child,
    this.contentMeasurementKey,
    this.sigma = defaultSigma,
    this.surfaceTintAlpha = defaultSurfaceTintAlpha,
    this.width,
    this.height,
    this.alignment = Alignment.topCenter,
    this.clip = true,
  });

  /// Matches ultra-thin material–style blur used across the app.
  static const double defaultSigma = 10;

  /// Matches pinned chrome on collection / catalog.
  static const double defaultSurfaceTintAlpha = 0.14;

  final Widget child;

  /// Optional key on the sizing [Container] (e.g. [StickyChromeScaffold] measures strip height).
  final Key? contentMeasurementKey;

  final double sigma;
  final double surfaceTintAlpha;
  final double? width;
  final double? height;
  final AlignmentGeometry alignment;

  /// When false, skips [ClipRect] (rare; can soften edge artifacts in some parents).
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final blurChild = FlutterBackdropBlur(
      sigma: sigma,
      child: Container(
        key: contentMeasurementKey,
        width: width ?? double.infinity,
        height: height,
        alignment: alignment,
        color: Theme.of(context).colorScheme.surface.withValues(alpha: surfaceTintAlpha),
        child: child,
      ),
    );

    if (clip) {
      return ClipRect(child: blurChild);
    }
    return blurChild;
  }
}
