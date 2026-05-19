import 'package:flutter/widgets.dart';

/// Shared layout tokens for top chrome (app bar + sticky frosted areas).
class ChromeMetrics {
  const ChromeMetrics._();

  /// [GlassShellBottomBar] pill height (tab row) — tighter than package default 64.
  static const double shellTabBarBarHeight = 56;

  /// [GlassSearchableBottomBar] height when search is expanded.
  static const double shellTabBarSearchHeight = 50;

  /// In-bar horizontal inset (inside [AdaptiveLiquidGlassLayer], demo: 20).
  static const double shellTabBarHorizontalPadding = 20;

  /// In-bar vertical breathing room (demo: 16).
  static const double shellTabBarVerticalPadding = 16;

  /// Float above home indicator on iOS; extra lift on Android gesture/nav bar.
  static const double shellTabBarOuterBottomInset = 8;

  /// Scroll padding: bar + in-bar padding + outer float.
  static const double shellTabBarReserveHeight =
      shellTabBarBarHeight +
      shellTabBarVerticalPadding * 2 +
      shellTabBarOuterBottomInset;

  /// Vertical space between sticky chrome and first scroll content.
  static const double contentTopGap = 12;
  static const double contentTopGapTight = 0;

  /// Common horizontal inset used by sticky chrome controls.
  static const double horizontalInset = 16;
  static const double compactHorizontalInset = 12;

  /// Padding for [AdaptiveButton.child] + [AdaptiveButtonStyle.bordered] with text
  /// (or icon+text). adaptive_platform_ui passes null padding for bordered on iOS,
  /// so labels sit flush; this matches the same library's filled Cupertino horizontal
  /// inset and a compact vertical inset for medium-sized actions.
  static const EdgeInsets adaptiveBorderedButtonPadding =
      EdgeInsets.symmetric(horizontal: 16, vertical: 8);

  /// Glass search pill height ([GlassSearchField]); keep in sync with widget.
  static const double searchHeaderExtent = 44;

  /// [AppSegmentedControl] intrinsic height in sticky chrome.
  static const double segmentControlHeight = 38;

  /// Space below [GlassSearchField] — use everywhere for consistent rhythm.
  static const double searchBarBottomInset = 6;

  /// Top inset when search sits in secondary sticky chrome below another row.
  static const double searchBarSecondaryTopInset = 8;

  /// Segment-only sticky rhythm.
  static const double segmentOnlyTopInset = 4;
  static const double segmentOnlyBottomInset = searchBarBottomInset;

  /// Pinned segment row without an inline search field (shell search pill instead).
  static const double segmentOnlyHeaderExtent =
      segmentOnlyTopInset + segmentControlHeight + segmentOnlyBottomInset;

  /// Gap between segment row and search/filter row in sticky chrome.
  static const double segmentToSearchGap = 8;

  /// Segment + gap + search pill + bottom inset (excludes [segmentOnlyTopInset]).
  static const double segmentWithSearchChromeExtent =
      segmentControlHeight +
      segmentToSearchGap +
      searchHeaderExtent +
      searchBarBottomInset;

  /// Default bottom inset when sticky chrome includes multiple rows.
  static const double multiRowBottomInset = searchBarBottomInset;

  /// Vertical rhythm for sticky headers that only contain a search/filter row.
  static const double searchOnlyTopInset = 4;
  static const double searchOnlyBottomInset = searchBarBottomInset;
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

  /// Segment row + glass search pill in collection sticky chrome (excludes navOffset).
  static const double segmentSearchHeaderExtent =
      segmentOnlyTopInset +
      segmentControlHeight +
      segmentToSearchGap +
      searchHeaderExtent +
      segmentOnlyBottomInset;
  static const double lotBasketHeaderExtent = 40;
  static const double lotBrowseHeaderExtent = segmentOnlyHeaderExtent;
  /// Fee card only (search uses shell bottom pill); keep in sync with [GradingScreen].
  static const double gradingHeaderTopInset = 10;
  static const double gradingFeeCardPaddingTop = 10;
  static const double gradingFeeCardPaddingBottom = 10;
  static const double gradingHeaderBottomInset = 6;
  /// [gradingHeaderTopInset] + fee card + [gradingHeaderBottomInset] (excludes nav bar).
  static const double gradingHeaderExtent = 72;

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
      top: navOffset + gradingHeaderTopInset,
      left: horizontalInset,
      right: horizontalInset,
      bottom: gradingHeaderBottomInset,
    );
  }

  /// Padding around search in secondary sticky chrome (below segments/filters).
  static EdgeInsets searchBarSecondaryPadding({
    double horizontal = compactHorizontalInset,
    double top = searchBarSecondaryTopInset,
  }) {
    return EdgeInsets.fromLTRB(
      horizontal,
      top,
      horizontal,
      searchBarBottomInset,
    );
  }

  /// Horizontal + bottom padding for a standalone search row (e.g. catalog browse).
  static EdgeInsets searchBarRowPadding({
    double horizontal = horizontalInset,
    double top = 0,
  }) {
    return EdgeInsets.fromLTRB(
      horizontal,
      top,
      horizontal,
      searchBarBottomInset,
    );
  }
}
