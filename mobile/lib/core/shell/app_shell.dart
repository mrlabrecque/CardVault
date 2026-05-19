import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../scan_immersive.dart';
import '../theme/chrome_metrics.dart';
import '../utils/platform_utils.dart';
import 'glass_shell_bottom_bar.dart';
import 'shell_bottom_search.dart';

/// Scroll offset past which the tab bar morphs to mini mode (Apple Music demo).
const kShellScrollMiniModeThreshold = 50.0;

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  /// Primary bottom-bar destinations (Wishlist is in the overflow menu).
  static const tabPaths = [
    '/dashboard',
    '/catalog',
    '/scan',
    '/collection',
  ];

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _lastTabIndex = 0;
  bool _isMiniMode = false;

  int _tabBarSelectedIndex(String location) {
    final idx = AppShell.tabPaths.indexWhere((p) => location.startsWith(p));
    if (idx >= 0) {
      _lastTabIndex = idx;
      return idx;
    }
    return _lastTabIndex;
  }

  /// Apple Music demo: float over the home indicator on iOS; clear Android nav.
  double _barBottomOffset(BuildContext context) {
    if (isIOS) return ChromeMetrics.shellTabBarOuterBottomInset;
    return MediaQuery.viewPaddingOf(context).bottom +
        ChromeMetrics.shellTabBarOuterBottomInset;
  }

  void _setMiniMode(bool mini) {
    if (_isMiniMode == mini) return;
    setState(() => _isMiniMode = mini);
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final mini = notification.metrics.pixels > kShellScrollMiniModeThreshold;
    if (mini != _isMiniMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _setMiniMode(mini);
      });
    }
    return false;
  }

  void _scrollActiveTabToTop(BuildContext context) {
    final controller = PrimaryScrollController.maybeOf(context);
    if (controller != null && controller.hasClients) {
      controller.animateTo(
        0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _expandFromMiniMode(BuildContext context) {
    _setMiniMode(false);
    _scrollActiveTabToTop(context);
  }

  void _onTabSelected(int index) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIdx = _tabBarSelectedIndex(location);

    if (index == currentIdx && _isMiniMode) {
      _expandFromMiniMode(context);
      return;
    }

    final router = GoRouter.of(context);
    final target = AppShell.tabPaths[index];
    if (!router.state.matchedLocation.startsWith(target)) {
      router.go(target);
      _setMiniMode(false);
    }
    _dismissSearch();
  }

  void _dismissSearch() {
    ref.read(shellBottomSearchProvider.notifier).setActive(false);
  }

  void _onSearchToggle(bool active) {
    final location = GoRouterState.of(context).matchedLocation;

    if (active && !shellLocationSupportsSearch(location)) {
      ref.read(shellBottomSearchProvider.notifier).setActive(true);
      context.go(AppShell.tabPaths[1]);
      return;
    }

    ref.read(shellBottomSearchProvider.notifier).setActive(active);

    if (!active && _isMiniMode) {
      _expandFromMiniMode(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIdx = _tabBarSelectedIndex(location);
    final shellSearch = ref.watch(shellBottomSearchProvider);
    final searchNotifier = ref.read(shellBottomSearchProvider.notifier);
    final barMorphActive = shellSearch.isActive || _isMiniMode;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final systemOverlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemOverlay,
      child: ValueListenableBuilder<bool>(
        valueListenable: scanImmersiveMode,
        builder: (context, hideTabBar, _) {
          return GlassBackdropScope(
            child: Scaffold(
              extendBody: true,
              resizeToAvoidBottomInset: false,
              body: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScrollNotification,
                      child: widget.child,
                    ),
                  ),
                  if (!hideTabBar)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: _barBottomOffset(context),
                      child: ListenableBuilder(
                        listenable: searchNotifier.controller,
                        builder: (context, _) {
                          return GlassShellBottomBar(
                            selectedIndex: selectedIdx,
                            onTabSelected: _onTabSelected,
                            isSearchActive: barMorphActive,
                            searchConfig: shellGlassSearchConfig(
                              context: context,
                              controller: searchNotifier.controller,
                              focusNode: searchNotifier.focusNode,
                              hintText: shellSearchHintForLocation(location),
                              onSearchToggle: _onSearchToggle,
                              onChanged: (_) {},
                              selectedTabIndex: selectedIdx,
                              isMiniMode: _isMiniMode,
                              isSearching: shellSearch.isActive,
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
