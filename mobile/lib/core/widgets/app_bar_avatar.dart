import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_service.dart';
import '../services/cards_service.dart';
import '../theme/app_theme.dart';
import '../utils/adaptive_ui.dart';

class AppBarAvatar extends ConsumerWidget {
  const AppBarAvatar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final initial = (user?.email ?? '?')[0].toUpperCase();

    return GestureDetector(
      onTap: () {
        final router = GoRouter.of(context);
        final supabase = ref.read(supabaseProvider);
        showAdaptiveSheet(
          context: context,
          builder: (sheetCtx) => _AvatarSheet(
            email: user?.email,
            onNavigate: (path) {
              Navigator.of(sheetCtx).pop();
              router.go(path);
            },
            onSignOut: () async {
              Navigator.of(sheetCtx).pop();
              await supabase.auth.signOut();
            },
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: AppTheme.primary,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
                label: 'Catalog',
                icon: Icons.library_books_outlined,
                onTap: () => onNavigate('/admin/catalog'),
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
