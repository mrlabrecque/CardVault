import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth/auth_service.dart';
import 'models/user_card.dart';
import '../features/collection/collection_screen.dart';
import '../features/collection/item_detail_screen.dart';
import '../features/collection/master_card_detail_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/comps/comps_screen.dart';
import '../features/wishlist/wishlist_screen.dart';
import '../features/scan/scan_models.dart';
import '../features/scan/scan_screen.dart';
import '../features/tools/tools_screen.dart';
import '../features/collection/catalog_screen.dart';
import '../features/collection/bulk_add_screen.dart';
import '../features/lot_builder/lot_builder_screen.dart';
import '../features/grading/grading_screen.dart';
import '../features/market_data/market_data_screen.dart';
import '../features/admin/admin_catalog_screen.dart';
import '../features/admin/admin_portfolio_movers_screen.dart';
import '../features/admin/pending_parallels_screen.dart';
import 'auth/login_screen.dart';
import 'shell/app_shell.dart';

Page<void> _page(Widget child) => MaterialPage(child: child);

/// `go_router` / map literals often yield `Map<String, Object?>`, not `Map<String, dynamic>`.
CatalogScanEntry? _catalogScanEntryFromExtra(Object? extra) {
  if (extra is! Map) return null;
  final map = Map<String, dynamic>.from(extra as Map);
  final sportRaw = map['sport'];
  final sport = sportRaw is String ? sportRaw : '';
  final detectionRaw = map['detection'];
  if (detectionRaw is ImageScanMatchResult) {
    return CatalogScanEntry(detection: detectionRaw, sport: sport);
  }
  if (detectionRaw is Map) {
    try {
      final parsed = ImageScanMatchResult.fromJson(
        Map<String, dynamic>.from(detectionRaw as Map),
      );
      return CatalogScanEntry(detection: parsed, sport: sport);
    } catch (_) {}
  }
  return null;
}

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
            pageBuilder: (_, state) {
              final card = state.extra;
              if (card is! UserCard) {
                return _page(const CollectionScreen());
              }
              return _page(ItemDetailScreen(card: card));
            },
          ),
          GoRoute(
            path: '/catalog',
            pageBuilder: (context, state) {
              final scanEntry = _catalogScanEntryFromExtra(state.extra);
              return _page(CatalogScreen(scanEntry: scanEntry));
            },
          ),
          GoRoute(
            path: '/catalog/master',
            pageBuilder: (context, state) {
              final args = state.extra;
              if (args is! MasterCardDetailArgs) {
                return _page(const CatalogScreen());
              }
              return _page(
                MasterCardDetailScreen(
                  key: ValueKey(
                    '${args.masterCard.id}|${args.parallelName}|${args.parallelSerialMax ?? ''}',
                  ),
                  masterCard: args.masterCard,
                  parallelName: args.parallelName,
                  parallelSerialMax: args.parallelSerialMax,
                  parallelIsAuto: args.parallelIsAuto,
                  releaseName: args.releaseName,
                  setName: args.setName,
                  year: args.year,
                  sport: args.sport,
                  onAddToCollection: args.onAddToCollection,
                  onAddToWishlist: args.onAddToWishlist,
                  openedFromScanResults: args.openedFromScanResults,
                  openedFromScanSingleRoute: args.openedFromScanSingleRoute,
                  resyncGuidePricesFromCatalog: args.resyncGuidePricesFromCatalog,
                ),
              );
            },
          ),
          GoRoute(path: '/bulk-add', pageBuilder: (context, state) => _page(const BulkAddScreen())),
          GoRoute(path: '/tools', pageBuilder: (context, state) => _page(const ToolsScreen())),
          GoRoute(path: '/comps', pageBuilder: (context, state) => _page(const CompsScreen())),
          GoRoute(path: '/lot-builder', pageBuilder: (context, state) => _page(const LotBuilderScreen())),
          GoRoute(path: '/grading', pageBuilder: (context, state) => _page(const GradingScreen())),
          GoRoute(path: '/wishlist', pageBuilder: (context, state) => _page(const WishlistScreen())),
          GoRoute(path: '/scan', pageBuilder: (context, state) => _page(const ScanScreen())),
          GoRoute(path: '/market-data', pageBuilder: (context, state) => _page(const MarketDataScreen())),
          GoRoute(path: '/portfolio-movers', pageBuilder: (context, state) => _page(const MarketDataScreen())),
          GoRoute(path: '/market-movers', pageBuilder: (context, state) => _page(const MarketDataScreen())),
          GoRoute(path: '/admin/catalog', pageBuilder: (_, _) => _page(const AdminCatalogScreen())),
          GoRoute(path: '/admin/portfolio-movers', pageBuilder: (_, _) => _page(const AdminPortfolioMoversScreen())),
          GoRoute(path: '/admin/market-movers', pageBuilder: (_, _) => _page(const AdminPortfolioMoversScreen())),
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
