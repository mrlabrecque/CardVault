import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth/auth_service.dart';
import '../features/collection/collection_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/comps/comps_screen.dart';
import '../features/wishlist/wishlist_screen.dart';
import '../features/scan/scan_screen.dart';
import 'auth/login_screen.dart';
import 'shell/app_shell.dart';

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
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),
          GoRoute(path: '/collection', builder: (context, state) => const CollectionScreen()),
          GoRoute(path: '/comps', builder: (context, state) => const CompsScreen()),
          GoRoute(path: '/wishlist', builder: (context, state) => const WishlistScreen()),
          GoRoute(path: '/scan', builder: (context, state) => const ScanScreen()),
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
