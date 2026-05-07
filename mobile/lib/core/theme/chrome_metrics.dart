import 'package:flutter/widgets.dart';

/// Shared layout tokens for top chrome (app bar + sticky frosted areas).
class ChromeMetrics {
  const ChromeMetrics._();

  /// Vertical space between sticky chrome and first scroll content.
  static const double contentTopGap = 12;

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
}
