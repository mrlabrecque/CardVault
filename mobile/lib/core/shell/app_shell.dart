import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_service.dart';
import '../services/cards_service.dart';
import '../theme/app_theme.dart';

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

  static const _tabTitles = {
    '/dashboard': 'Dashboard',
    '/catalog': 'Catalog',
    '/collection': 'Collection',
    '/tools': 'Tools',
    '/wishlist': 'Wishlist',
    '/admin/catalog-import': 'Catalog Import',
    '/admin/releases': 'Manage Releases',
    '/admin/pending-parallels': 'Pending Parallels',
  };

  int _selectedIndex(String location) {
    final idx = _tabs.indexWhere((t) => location.startsWith(t.path));
    return idx < 0 ? 0 : idx;
  }

  bool _isTabRoute(String location) {
    // Only show header for main tab routes
    return _tabTitles.keys.any((p) => location == p);
  }

  String _pageTitle(String location) {
    for (final entry in _tabTitles.entries) {
      if (location.startsWith(entry.key)) return entry.value;
    }
    return 'Card Vault';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIdx = _selectedIndex(location);
    final showShellHeader = _isTabRoute(location);
    final user = ref.watch(currentUserProvider);
    final initial = (user?.email ?? '?')[0].toUpperCase();

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          if (showShellHeader)
            _ShellHeader(
              title: _pageTitle(location),
              initial: initial,
              onAvatarTap: () => _showAvatarSheet(context, ref, user?.email),
            ),
          Expanded(child: child),
        ],
      ),
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

  void _showAvatarSheet(BuildContext context, WidgetRef ref, String? email) {
    final router = GoRouter.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => _AvatarSheet(
        email: email,
        onNavigate: (path) {
          Navigator.of(sheetCtx).pop();
          router.go(path);
        },
        onSignOut: () async {
          Navigator.pop(context);
          await ref.read(supabaseProvider).auth.signOut();
        },
      ),
    );
  }
}

// ── Shell header ───────────────────────────────────────────────────────────────

class _ShellHeader extends StatelessWidget {
  const _ShellHeader({
    required this.title,
    required this.initial,
    required this.onAvatarTap,
  });

  final String title;
  final String initial;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'CARD VAULT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: const Color(0xFF800020).withValues(alpha: 0.7),
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onAvatarTap,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0xFF800020),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Avatar bottom sheet ────────────────────────────────────────────────────────

class _AvatarSheet extends ConsumerWidget {
  const _AvatarSheet({
    this.email,
    required this.onNavigate,
    required this.onSignOut,
  });
  final String? email;
  final void Function(String path) onNavigate;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAppAdminProvider).asData?.value ?? false;
    final pendingCount = isAdmin
        ? (ref.watch(pendingParallelCountProvider).asData?.value ?? 0)
        : 0;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Account',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            if (email != null) ...[
              Text(
                email!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              Divider(color: Colors.grey.shade100),
              const SizedBox(height: 8),
            ],
            if (isAdmin) ...[
              _AdminLink(
                label: 'Catalog Import',
                icon: Icons.download_outlined,
                onTap: () => onNavigate('/admin/catalog-import'),
              ),
              _AdminLink(
                label: 'Manage Releases',
                icon: Icons.library_books_outlined,
                onTap: () => onNavigate('/admin/releases'),
              ),
              _AdminLink(
                label: 'Pending Parallels',
                icon: Icons.pending_outlined,
                badge: pendingCount > 0 ? pendingCount : null,
                onTap: () => onNavigate('/admin/pending-parallels'),
              ),
              const SizedBox(height: 4),
              Divider(color: Colors.grey.shade100),
              const SizedBox(height: 4),
            ],
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: onSignOut,
                icon: Icon(Icons.logout, size: 16, color: Colors.red.shade400),
                label: Text(
                  'Sign Out',
                  style: TextStyle(
                    color: Colors.red.shade400,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminLink extends StatelessWidget {
  const _AdminLink({
    required this.label,
    required this.icon,
    required this.onTap,
    this.badge,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: AppTheme.primary),
        label: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade600,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        ),
      ),
    );
  }
}
