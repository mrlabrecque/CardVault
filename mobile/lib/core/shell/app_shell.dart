import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

// TODO: Liquid glass tab bar (iOS)
// Explored liquid_glass_easy + liquid_glacier — the backgroundWidget snapshot
// mechanism causes a flicker on tab switch that needs solving before shipping.
// Re-add the packages, restore _buildIOSGlassShell, and tackle the timing fix.

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  static const _tabs = [
    (
      path: '/dashboard',
      icon: Icons.bar_chart_outlined,
      activeIcon: Icons.bar_chart,
      label: 'Dashboard',
    ),
    (
      path: '/catalog',
      icon: Icons.travel_explore_outlined,
      activeIcon: Icons.travel_explore,
      label: 'Catalog',
    ),
    (
      path: '/collection',
      icon: Icons.style_outlined,
      activeIcon: Icons.style,
      label: 'Collection',
    ),
    (
      path: '/wishlist',
      icon: Icons.bookmark_outline,
      activeIcon: Icons.bookmark,
      label: 'Wishlist',
    ),
    (
      path: '/tools',
      icon: Icons.handyman_outlined,
      activeIcon: Icons.handyman,
      label: 'Tools',
    ),
  ];

  int _selectedIndex(String location) {
    final idx = _tabs.indexWhere((t) => location.startsWith(t.path));
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIdx = _selectedIndex(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIdx,
        onDestinationSelected: (i) => context.go(_tabs[i].path),
        backgroundColor: AppTheme.primary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        destinations: _tabs.map((t) {
          return NavigationDestination(
            icon: Icon(t.icon),
            selectedIcon: Icon(t.activeIcon),
            label: t.label,
          );
        }).toList(),
      ),
    );
  }
}
