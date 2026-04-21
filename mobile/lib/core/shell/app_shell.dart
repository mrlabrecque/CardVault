import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_service.dart';
import '../theme/app_theme.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  static const _tabs = [
    (path: '/dashboard',  icon: Icons.bar_chart_outlined, activeIcon: Icons.bar_chart, label: 'Dashboard'),
    (path: '/collection', icon: Icons.style_outlined,    activeIcon: Icons.style,    label: 'Collection'),
    (path: '/scan',       icon: Icons.camera_alt_outlined, activeIcon: Icons.camera_alt, label: ''),
    (path: '/tools',      icon: Icons.handyman_outlined,  activeIcon: Icons.handyman, label: 'Tools'),
    (path: '/wishlist',   icon: Icons.bookmark_outline,   activeIcon: Icons.bookmark, label: 'Wishlist'),
  ];

  static const _tabTitles = {
    '/dashboard':  'Dashboard',
    '/collection': 'Collection',
    '/scan':       'Scan',
    '/tools':      'Tools',
    '/wishlist':   'Wishlist',
  };

  int _selectedIndex(String location) {
    final idx = _tabs.indexWhere((t) => location.startsWith(t.path));
    return idx < 0 ? 0 : idx;
  }

  bool _isTabRoute(String location) => _tabTitles.keys.any((p) => location == p);

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
        destinations: _tabs.mapIndexed((i, t) {
          if (t.path == '/scan') {
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

  void _showAvatarSheet(BuildContext context, WidgetRef ref, String? email) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AvatarSheet(
        email: email,
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
              width: 36, height: 36,
              decoration: const BoxDecoration(
                color: Color(0xFF800020),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(initial,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Avatar bottom sheet ────────────────────────────────────────────────────────

class _AvatarSheet extends StatelessWidget {
  const _AvatarSheet({this.email, required this.onSignOut});
  final String? email;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (email != null) ...[
              Text(email!,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
              const SizedBox(height: 16),
              Divider(color: Colors.grey.shade100),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: onSignOut,
                icon: Icon(Icons.logout, size: 16, color: Colors.red.shade400),
                label: Text('Sign Out',
                    style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── FAB scan button ────────────────────────────────────────────────────────────

class _ScanFab extends StatelessWidget {
  const _ScanFab({required this.active, required this.selected});
  final bool active;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 1.5,
      child: Transform.translate(
        offset: const Offset(0, -12),
        child: Container(
          width: 48, height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(Icons.camera_alt, color: AppTheme.primary, size: 24),
        ),
      ),
    );
  }
}

extension<T> on List<T> {
  Iterable<R> mapIndexed<R>(R Function(int index, T item) fn) sync* {
    for (var i = 0; i < length; i++) { yield fn(i, this[i]); }
  }
}
