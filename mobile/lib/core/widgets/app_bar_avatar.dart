import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_service.dart';
import '../services/cards_service.dart';
import '../theme/app_theme.dart';
import '../utils/adaptive_ui.dart';
import 'modal_sheet_scaffold.dart';

class AppBarAvatar extends ConsumerWidget {
  const AppBarAvatar({
    super.key,
    this.iconOnly = false,
    this.tint,
    this.buttonStyle = PopupButtonStyle.plain,
    this.padding = const EdgeInsets.only(right: 12),
  });

  final bool iconOnly;
  final Color? tint;
  final PopupButtonStyle buttonStyle;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final initial = (user?.email ?? '?')[0].toUpperCase();
    final isAdmin = ref.watch(isAppAdminProvider).asData?.value ?? false;
    final pendingCount = isAdmin
        ? (ref.watch(pendingParallelCountProvider).asData?.value ?? 0)
        : 0;

    if (iconOnly) {
      final menuItems = <AdaptivePopupMenuEntry>[
        if ((user?.email ?? '').isNotEmpty)
          AdaptivePopupMenuItem<String>(
            label: user!.email!,
            icon: 'envelope',
            enabled: false,
          ),
        if (isAdmin) ...[
          const AdaptivePopupMenuDivider(),
          const AdaptivePopupMenuItem<String>(
            label: 'Catalog',
            icon: 'books.vertical',
            value: '/admin/catalog',
          ),
          const AdaptivePopupMenuItem<String>(
            label: 'Portfolio Movers (admin)',
            icon: 'info.circle',
            value: '/admin/portfolio-movers',
          ),
          AdaptivePopupMenuItem<String>(
            label: pendingCount > 0
                ? 'Pending Parallels ($pendingCount)'
                : 'Pending Parallels',
            icon: 'clock.badge.exclamationmark',
            value: '/admin/pending-parallels',
          ),
        ],
        const AdaptivePopupMenuDivider(),
        const AdaptivePopupMenuItem<String>(
          label: 'Sign Out',
          icon: 'rectangle.portrait.and.arrow.right',
          value: '__signout__',
        ),
      ];

      return Padding(
        padding: padding,
        child: AdaptivePopupMenuButton.icon<String>(
          icon: 'person.circle',
          tint: tint ?? Colors.white,
          buttonStyle: buttonStyle,
          items: menuItems,
          onSelected: (_, entry) async {
            final value = entry.value;
            if (value == null) return;
            if (value == '__signout__') {
              await ref.read(supabaseProvider).auth.signOut();
              return;
            }
            if (context.mounted) context.go(value);
          },
        ),
      );
    }

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
        child: iconOnly
            ? Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white,
                ),
                child: const Icon(
                  Icons.person_outline,
                  size: 18,
                  color: Color(0xFF6B7280),
                ),
              )
            : Container(
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

    return ModalSheetScaffold(
      title: 'Account',
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
              _AdminLink(
                label: 'Portfolio Movers (admin)',
                icon: Icons.info_outline,
                onTap: () => onNavigate('/admin/portfolio-movers'),
              ),
              const SizedBox(height: 4),
              Divider(color: Colors.grey.shade100),
              const SizedBox(height: 4),
            ],
            const SizedBox(height: 8),
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
