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

class IOSAppShell extends StatefulWidget {
  const IOSAppShell({
    super.key,
    required this.child,
    required this.selectedIndex,
    required this.onTabSelected,
  });

  final Widget child;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;

  @override
  State<IOSAppShell> createState() => _IOSAppShellState();
}

class _IOSAppShellState extends State<IOSAppShell> {
  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      minimizeBehavior: TabBarMinimizeBehavior.automatic,
      body: widget.child,
      bottomNavigationBar: AdaptiveBottomNavigationBar(
        items: const [
          AdaptiveNavigationDestination(
            icon: 'house.fill',
            selectedIcon: 'house.fill',
            label: 'Dashboard',
          ),
          AdaptiveNavigationDestination(
            icon: 'square.grid.2x2.fill',
            selectedIcon: 'square.grid.2x2.fill',
            label: 'Catalog',
          ),
          AdaptiveNavigationDestination(
            icon: 'camera.fill',
            selectedIcon: 'camera.fill',
            label: 'Scan',
          ),
          AdaptiveNavigationDestination(
            icon: 'square.stack.3d.up.fill',
            selectedIcon: 'square.stack.3d.up.fill',
            label: 'Collection',
          ),
          AdaptiveNavigationDestination(
            icon: 'bookmark.fill',
            selectedIcon: 'bookmark.fill',
            label: 'Wishlist',
          ),
        ],
        selectedIndex: widget.selectedIndex,
        onTap: widget.onTabSelected,
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
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: 'Dashboard',
    ),
    NavigationDestination(
      icon: Icon(Icons.search_outlined),
      selectedIcon: Icon(Icons.search),
      label: 'Catalog',
    ),
    NavigationDestination(
      icon: Icon(Icons.camera_alt_outlined),
      selectedIcon: Icon(Icons.camera_alt_rounded),
      label: 'Scan',
    ),
    NavigationDestination(
      icon: Icon(Icons.credit_card_outlined),
      selectedIcon: Icon(Icons.credit_card),
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
