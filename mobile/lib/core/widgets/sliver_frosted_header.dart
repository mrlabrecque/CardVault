import 'package:flutter/widgets.dart';

import '../theme/chrome_metrics.dart';
import 'fixed_sliver_header_delegate.dart';

/// Shared pinned sliver header wrapper for fixed-height chrome regions.
class SliverFrostedHeader extends StatelessWidget {
  const SliverFrostedHeader({
    super.key,
    required this.height,
    required this.child,
    this.pinned = true,
  });

  final double height;
  final Widget child;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: pinned,
      delegate: FixedSliverHeaderDelegate(
        height: height,
        child: child,
      ),
    );
  }
}

/// Shared top spacing between pinned chrome and first scroll content.
class SliverChromeGap extends StatelessWidget {
  const SliverChromeGap({
    super.key,
    this.height = defaultHeight,
  });

  static const double defaultHeight = ChromeMetrics.contentTopGap;

  final double height;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: SizedBox(height: height),
    );
  }
}
