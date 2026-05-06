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
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;

  @override
  bool shouldRebuild(covariant FixedSliverHeaderDelegate oldDelegate) =>
      oldDelegate.height != height || oldDelegate.child != child;
}
