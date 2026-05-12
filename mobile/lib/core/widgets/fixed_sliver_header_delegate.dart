import 'package:flutter/widgets.dart';

class FixedSliverHeaderDelegate extends SliverPersistentHeaderDelegate {
  const FixedSliverHeaderDelegate({
    required this.height,
    required this.child,
  });

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    // Fill the persistent header slot so [BackdropFilter] in pinned chrome samples
    // the full viewport width (avoids partial / "half" blur in tight layouts).
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(covariant FixedSliverHeaderDelegate oldDelegate) =>
      oldDelegate.height != height || oldDelegate.child != child;
}
