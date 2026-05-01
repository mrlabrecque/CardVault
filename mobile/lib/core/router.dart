import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth/auth_service.dart';
import 'utils/platform_utils.dart';
import 'models/user_card.dart';
import '../features/collection/collection_screen.dart';
import '../features/collection/item_detail_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/comps/comps_screen.dart';
import '../features/wishlist/wishlist_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/tools/tools_screen.dart';
import '../features/collection/add_card_screen.dart';
import '../features/collection/bulk_add_screen.dart';
import '../features/lot_builder/lot_builder_screen.dart';
import '../features/grading/grading_screen.dart';
import '../features/market_movers/market_movers_screen.dart';
import '../features/admin/admin_catalog_screen.dart';
import '../features/admin/pending_parallels_screen.dart';
import 'auth/login_screen.dart';
import 'shell/app_shell.dart';

Page<void> _page(Widget child) =>
  isIOS ? CupertinoPage(child: child) : MaterialPage(child: child);

final routerProvider = Provider<GoRouter>((ref) {
  final supabase = ref.watch(supabaseProvider);

  return GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) {
      final isLoggedIn = supabase.auth.currentUser != null;
      final isLoginRoute = state.matchedLocation == '/login';
      if (!isLoggedIn && !isLoginRoute) return '/login';
      if (isLoggedIn && isLoginRoute) return '/dashboard';
      return null;
    },
    refreshListenable: GoRouterRefreshStream(supabase.auth.onAuthStateChange),
    routes: [
      GoRoute(path: '/login', pageBuilder: (context, state) => _page(const LoginScreen())),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/dashboard', pageBuilder: (context, state) => _page(const DashboardScreen())),
          GoRoute(path: '/collection', pageBuilder: (context, state) => _page(const CollectionScreen())),
          GoRoute(
            path: '/collection/card',
            pageBuilder: (_, state) => _page(ItemDetailScreen(card: state.extra as UserCard)),
          ),
          GoRoute(path: '/catalog', pageBuilder: (context, state) => _page(const AddCardScreen())),
          GoRoute(path: '/bulk-add', pageBuilder: (context, state) => _page(const BulkAddScreen())),
          GoRoute(path: '/tools', pageBuilder: (context, state) => _page(const ToolsScreen())),
          GoRoute(path: '/comps', pageBuilder: (context, state) => _page(const CompsScreen())),
          GoRoute(path: '/lot-builder', pageBuilder: (context, state) => _page(const LotBuilderScreen())),
          GoRoute(path: '/grading', pageBuilder: (context, state) => _page(const GradingScreen())),
          GoRoute(path: '/wishlist', pageBuilder: (context, state) => _page(const WishlistScreen())),
          GoRoute(path: '/scan', pageBuilder: (context, state) => _page(const ScanScreen())),
          GoRoute(path: '/market-movers', pageBuilder: (context, state) => _page(const MarketMoversScreen())),
          GoRoute(path: '/admin/catalog', pageBuilder: (_, _) => _page(const AdminCatalogScreen())),
          GoRoute(path: '/admin/pending-parallels', pageBuilder: (_, _) => _page(const PendingParallelsScreen())),
        ],
      ),
    ],
  );
});

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<AuthState> stream) {
    stream.listen((_) => notifyListeners());
  }
}
