import 'package:flutter/widgets.dart';

/// Shared layout tokens for top chrome (app bar + sticky frosted areas).
class ChromeMetrics {
  const ChromeMetrics._();

  /// Vertical space between sticky chrome and first scroll content.
  static const double contentTopGap = 12;
  static const double contentTopGapTight = 0;

  /// Common horizontal inset used by sticky chrome controls.
  static const double horizontalInset = 16;
  static const double compactHorizontalInset = 12;

  /// Segment-only sticky rhythm.
  static const double segmentOnlyTopInset = 4;
  static const double segmentOnlyBottomInset = 6;

  /// Gap between segment row and search/filter row in sticky chrome.
  static const double segmentToSearchGap = 8;

  /// Default bottom inset when sticky chrome includes multiple rows.
  static const double multiRowBottomInset = 8;

  /// Vertical rhythm for sticky headers that only contain a search/filter row.
  static const double searchOnlyTopInset = 4;
  static const double searchOnlyBottomInset = 6;
  static const double searchOnlyExtraHeight =
      searchOnlyTopInset + searchOnlyBottomInset;
  static const double searchOnlyTightTopInset = 2;
  static const double searchOnlyTightBottomInset = 2;
  static const double searchOnlyTightExtraHeight =
      searchOnlyTightTopInset + searchOnlyTightBottomInset;

  /// Shared list/chrome rhythm for list count labels + first row spacing.
  static const double listCountBottomInset = 2;
  static const double listCountBottomInsetRoomy = 8;
  static const double listTopInsetAfterCount = 2;
  static const double listTopInsetAfterCountRoomy = 8;

  /// Canonical pinned chrome extents (excluding navOffset).
  static const double segmentSearchHeaderExtent = 96;
  static const double searchHeaderExtent = 44;
  static const double lotBasketHeaderExtent = 40;
  static const double lotBrowseHeaderExtent = 92;
  static const double gradingHeaderExtent = 116;

  static EdgeInsets segmentOnlyPadding(
    double navOffset, {
    double horizontal = compactHorizontalInset,
  }) {
    return EdgeInsets.fromLTRB(
      horizontal,
      navOffset + segmentOnlyTopInset,
      horizontal,
      segmentOnlyBottomInset,
    );
  }

  static EdgeInsets searchOnlyPadding(
    double navOffset, {
    double horizontal = horizontalInset,
  }) {
    return EdgeInsets.fromLTRB(
      horizontal,
      navOffset + searchOnlyTopInset,
      horizontal,
      searchOnlyBottomInset,
    );
  }

  static EdgeInsets searchOnlyTightPadding(
    double navOffset, {
    double horizontal = horizontalInset,
  }) {
    return EdgeInsets.fromLTRB(
      horizontal,
      navOffset + searchOnlyTightTopInset,
      horizontal,
      searchOnlyTightBottomInset,
    );
  }

  static EdgeInsets listCountPadding({
    double horizontal = horizontalInset,
    double bottom = listCountBottomInset,
  }) {
    return EdgeInsets.fromLTRB(horizontal, 0, horizontal, bottom);
  }

  static EdgeInsets listBodyPadding({
    double horizontal = horizontalInset,
    double top = listTopInsetAfterCount,
    double bottom = 100,
  }) {
    return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
  }

  static EdgeInsets gradingHeaderPadding(double navOffset) {
    return EdgeInsets.only(
      top: navOffset,
      left: horizontalInset,
      right: horizontalInset,
      bottom: 6,
    );
  }
}
