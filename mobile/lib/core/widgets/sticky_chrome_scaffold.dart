import 'package:flutter/material.dart';

import '../theme/chrome_metrics.dart';
import 'frosted_chrome_layer.dart';

/// [AppBar] + optional sticky strip + body. The strip’s **height is measured** from the
/// child so there’s no empty frosted padding at the bottom when layout differs from estimates.
///
/// [bodyBuilder] receives [contentTopInset] = safe area + toolbar + measured sticky height.
/// Until the first layout pass, [stickyHeightEstimate] is used so content roughly clears the strip.
///
/// Sticky strip uses [FrostedChromeLayer] (same blur/tint as sliver-pinned chrome elsewhere).
class StickyChromeScaffold extends StatefulWidget {
  const StickyChromeScaffold({
    super.key,
    required this.appBar,
    this.stickyChrome,
    this.stickyHeightEstimate = 52,
    this.contentTopGap = ChromeMetrics.contentTopGap,
    this.blurSigma = 10,
    required this.bodyBuilder,
  });

  final PreferredSizeWidget appBar;
  final Widget? stickyChrome;

  /// Used only until the first successful measurement (typically one frame).
  final double stickyHeightEstimate;
  /// Shared spacing between sticky chrome and first scroll content.
  final double contentTopGap;
  final double blurSigma;
  final Widget Function(BuildContext context, double contentTopInset) bodyBuilder;

  static double navToolbarExtent(BuildContext context) {
    return MediaQuery.paddingOf(context).top + kToolbarHeight;
  }

  @override
  State<StickyChromeScaffold> createState() => _StickyChromeScaffoldState();
}

class _StickyChromeScaffoldState extends State<StickyChromeScaffold> {
  final GlobalKey _stickyKey = GlobalKey();

  /// -1 = not measured yet; otherwise pixel height of [_stickyKey] strip.
  double _measuredStickyHeight = -1;

  double get _effectiveStickyHeight {
    if (widget.stickyChrome == null) return 0;
    if (_measuredStickyHeight >= 0) return _measuredStickyHeight;
    return widget.stickyHeightEstimate;
  }

  void _measureStickyHeight() {
    final box = _stickyKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final h = box.size.height;
    if (_measuredStickyHeight >= 0 && (h - _measuredStickyHeight).abs() < 0.5) return;
    setState(() => _measuredStickyHeight = h);
  }

  @override
  void didUpdateWidget(StickyChromeScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    final estimateChanged =
        oldWidget.stickyHeightEstimate != widget.stickyHeightEstimate;
    final presenceChanged =
        (oldWidget.stickyChrome == null) != (widget.stickyChrome == null);
    if (estimateChanged || presenceChanged) {
      _measuredStickyHeight = -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final navExtent = StickyChromeScaffold.navToolbarExtent(context);
    final contentTopInset = navExtent + _effectiveStickyHeight + widget.contentTopGap;

    if (widget.stickyChrome != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _measureStickyHeight();
      });
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: widget.appBar,
      body: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: widget.bodyBuilder(context, contentTopInset),
          ),
          if (widget.stickyChrome != null)
            Positioned(
              top: navExtent,
              left: 0,
              right: 0,
              child: FrostedChromeLayer(
                contentMeasurementKey: _stickyKey,
                sigma: widget.blurSigma,
                child: widget.stickyChrome!,
              ),
            ),
        ],
      ),
    );
  }
}
