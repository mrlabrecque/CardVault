import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  static const _tabs = [
    (path: '/collection', icon: Icons.style_outlined,    activeIcon: Icons.style,    label: 'Collection'),
    (path: '/dashboard',  icon: Icons.bar_chart_outlined, activeIcon: Icons.bar_chart, label: 'Dashboard'),
    (path: '/scan',       icon: Icons.camera_alt_outlined, activeIcon: Icons.camera_alt, label: 'Scan'),
    (path: '/comps',      icon: Icons.search_outlined,    activeIcon: Icons.search,   label: 'Comps'),
    (path: '/wishlist',   icon: Icons.bookmark_outline,   activeIcon: Icons.bookmark, label: 'Wishlist'),
  ];

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final idx = _tabs.indexWhere((t) => location.startsWith(t.path));
    return idx < 0 ? 1 : idx;
  }

  @override
  Widget build(BuildContext context) {
    final selectedIdx = _selectedIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIdx,
        onDestinationSelected: (i) => context.go(_tabs[i].path),
        backgroundColor: AppTheme.primary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        destinations: _tabs.mapIndexed((i, t) {
          final isScan = t.path == '/scan';
          if (isScan) {
            return NavigationDestination(
              icon: _ScanFab(active: selectedIdx == i, selected: false),
              selectedIcon: _ScanFab(active: selectedIdx == i, selected: true),
              label: t.label,
            );
          }
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

class _ScanFab extends StatelessWidget {
  const _ScanFab({required this.active, required this.selected});
  final bool active;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Icon(Icons.camera_alt, color: AppTheme.primary, size: 24),
    );
  }
}

extension<T> on List<T> {
  Iterable<R> mapIndexed<R>(R Function(int index, T item) fn) sync* {
    for (var i = 0; i < length; i++) { yield fn(i, this[i]); }
  }
}
