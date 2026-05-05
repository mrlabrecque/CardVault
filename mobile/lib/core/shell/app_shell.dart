import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../utils/platform_utils.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  static const _paths = [
    '/dashboard',
    '/catalog',
    '/scan',
    '/collection',
    '/wishlist',
  ];

  int _selectedIndex(String location) {
    final idx = _paths.indexWhere((p) => location.startsWith(p));
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIdx = _selectedIndex(location);

    if (isIOS) {
      return IOSAppShell(
        selectedIndex: selectedIdx,
        onTabSelected: (i) => context.go(_paths[i]),
        child: child,
      );
    }

    return AndroidAppShell(
      selectedIndex: selectedIdx,
      onTabSelected: (i) => context.go(_paths[i]),
      child: child,
    );
  }
}

class IOSAppShell extends StatelessWidget {
  const IOSAppShell({
    super.key,
    required this.child,
    required this.selectedIndex,
    required this.onTabSelected,
  });

  final Widget child;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;

  static const _iosItems = <AdaptiveNavigationDestination>[
    AdaptiveNavigationDestination(
      icon: 'chart.bar',
      selectedIcon: 'chart.bar.fill',
      label: 'Dashboard',
    ),
    AdaptiveNavigationDestination(
      icon: 'square.stack.3d.up',
      selectedIcon: 'square.stack.3d.up.fill',
      label: 'Catalog',
    ),
    AdaptiveNavigationDestination(
      icon: 'camera',
      selectedIcon: 'camera.fill',
      label: 'Scan',
    ),
    AdaptiveNavigationDestination(
      icon: 'creditcard',
      selectedIcon: 'creditcard.fill',
      label: 'Collection',
    ),
    AdaptiveNavigationDestination(
      icon: 'bookmark',
      selectedIcon: 'bookmark.fill',
      label: 'Wishlist',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      minimizeBehavior: TabBarMinimizeBehavior.never,
      body: child,
      bottomNavigationBar: AdaptiveBottomNavigationBar(
        items: _iosItems,
        selectedIndex: selectedIndex,
        onTap: onTabSelected,
        useNativeBottomBar: true,
        selectedItemColor: AppTheme.primary,
      ),
    );
  }
}

class AndroidAppShell extends StatelessWidget {
  const AndroidAppShell({
    super.key,
    required this.child,
    required this.selectedIndex,
    required this.onTabSelected,
  });

  final Widget child;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;

  static const _androidDestinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.bar_chart_outlined),
      selectedIcon: Icon(Icons.bar_chart),
      label: 'Dashboard',
    ),
    NavigationDestination(
      icon: Icon(Icons.travel_explore_outlined),
      selectedIcon: Icon(Icons.travel_explore),
      label: 'Catalog',
    ),
    NavigationDestination(
      icon: Icon(Icons.qr_code_scanner_outlined),
      selectedIcon: Icon(Icons.qr_code_scanner),
      label: 'Scan',
    ),
    NavigationDestination(
      icon: Icon(Icons.style_outlined),
      selectedIcon: Icon(Icons.style),
      label: 'Collection',
    ),
    NavigationDestination(
      icon: Icon(Icons.bookmark_outline),
      selectedIcon: Icon(Icons.bookmark),
      label: 'Wishlist',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onTabSelected,
        backgroundColor: AppTheme.primary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        destinations: _androidDestinations,
      ),
    );
  }
}
