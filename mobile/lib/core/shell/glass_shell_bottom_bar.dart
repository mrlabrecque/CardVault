import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../theme/app_theme.dart';
import '../theme/chrome_metrics.dart';
import 'shell_glass_settings.dart';

/// App shell bottom chrome using [GlassSearchableBottomBar] from
/// `liquid_glass_widgets` (Apple Music iOS 26 demo layout).
class GlassShellBottomBar extends StatelessWidget {
  const GlassShellBottomBar({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
    required this.isSearchActive,
    required this.searchConfig,
  });

  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final bool isSearchActive;
  final GlassSearchBarConfig searchConfig;

  static const _indicatorExpansion = 12.0;

  static double _barBorderRadius(double barHeight) => barHeight / 2;

  /// Tab definitions shared with [shellGlassSearchConfig] (collapsed mini pill).
  static const shellTabs = <GlassBottomBarTab>[
    GlassBottomBarTab(
      icon: Icon(CupertinoIcons.house),
      activeIcon: Icon(CupertinoIcons.house_fill),
    ),
    GlassBottomBarTab(
      icon: Icon(CupertinoIcons.square_grid_2x2),
      activeIcon: Icon(CupertinoIcons.square_grid_2x2_fill),
    ),
    GlassBottomBarTab(
      icon: Icon(CupertinoIcons.camera),
      activeIcon: Icon(CupertinoIcons.camera_fill),
    ),
    GlassBottomBarTab(
      icon: Icon(CupertinoIcons.square_stack_3d_up),
      activeIcon: Icon(CupertinoIcons.square_stack_3d_up_fill),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final colors = Theme.of(context).colorScheme;
    final isDark = brightness == Brightness.dark;
    final selectedColor = AppTheme.primary;
    final unselectedColor = isDark ? Colors.white.withValues(alpha: 0.85) : Colors.black;
    final glass = ShellGlassSettings.bottomBarGlass(brightness);
    final indicatorLens = ShellGlassSettings.indicatorLens(brightness);
    final barHeight = ChromeMetrics.shellTabBarBarHeight;
    final borderRadius = _barBorderRadius(barHeight);

    // Standard (not premium): each pill uses its own shape-clipped glass.
    // Premium batches all shapes into one layer whose backdrop rect spans the
    // full bar width, which blurs the gap between the tab pill and search pill
    // in mini / search-collapsed mode.
    final bar = GlassSearchableBottomBar(
      tabs: shellTabs,
      selectedIndex: selectedIndex,
      onTabSelected: onTabSelected,
      isSearchActive: isSearchActive,
      searchConfig: searchConfig,
      quality: GlassQuality.standard,
      blendAmount: 0,
      maskingQuality: MaskingQuality.high,
      interactionBehavior: GlassInteractionBehavior.scaleOnly,
      pressScale: 1.04,
      glassSettings: glass,
      indicatorSettings: indicatorLens,
      indicatorColor: ShellGlassSettings.indicatorFill(brightness, colors),
      indicatorExpansion: _indicatorExpansion,
      barHeight: barHeight,
      searchBarHeight: ChromeMetrics.shellTabBarSearchHeight,
      horizontalPadding: ChromeMetrics.shellTabBarHorizontalPadding,
      verticalPadding: ChromeMetrics.shellTabBarVerticalPadding,
      spacing: 8,
      barBorderRadius: borderRadius,
      selectedIconColor: selectedColor,
      unselectedIconColor: unselectedColor,
      interactionGlowColor: Colors.transparent,
      glowOpacity: 0,
      magnification: 1.0,
      innerBlur: 0,
      iconSize: 24,
    );

    return Theme(
      data: ShellGlassSettings.searchFieldTheme(Theme.of(context)),
      child: bar,
    );
  }
}

/// Search field config for [GlassShellBottomBar] (neutral borders, no theme primary).
GlassSearchBarConfig shellGlassSearchConfig({
  required BuildContext context,
  required TextEditingController controller,
  required FocusNode focusNode,
  required String hintText,
  required ValueChanged<bool> onSearchToggle,
  required ValueChanged<String> onChanged,
  required int selectedTabIndex,
  required bool isMiniMode,
  required bool isSearching,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final iconMuted = isDark ? Colors.white.withValues(alpha: 0.55) : Colors.black;
  final tab = GlassShellBottomBar.shellTabs[selectedTabIndex.clamp(
    0,
    GlassShellBottomBar.shellTabs.length - 1,
  )];

  return GlassSearchBarConfig(
    controller: controller,
    focusNode: focusNode,
    hintText: hintText,
    onSearchToggle: onSearchToggle,
    onChanged: onChanged,
    textColor: isDark ? Colors.white : Colors.black,
    searchIcon: Icon(CupertinoIcons.search, size: 20, color: iconMuted),
    searchIconColor: iconMuted,
    autocorrect: false,
    textInputAction: TextInputAction.search,
    autoFocusOnExpand: true,
    expandWhenActive: !isMiniMode || isSearching,
    showsCancelButton: true,
    collapsedLogoBuilder: (ctx) {
      final iconColor = isMiniMode && !isSearching
          ? AppTheme.primary
          : iconMuted;
      return Center(
        child: IconTheme(
          data: IconThemeData(color: iconColor, size: 24),
          child: tab.activeIcon ?? tab.icon,
        ),
      );
    },
    onTapOutside: (_) => FocusScope.of(context).unfocus(),
    trailingBuilder: (ctx) {
      if (controller.text.isEmpty) return const SizedBox.shrink();
      return GestureDetector(
        onTap: () {
          controller.clear();
          onChanged('');
        },
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(
            CupertinoIcons.xmark_circle_fill,
            size: 18,
            color: iconMuted,
          ),
        ),
      );
    },
  );
}
