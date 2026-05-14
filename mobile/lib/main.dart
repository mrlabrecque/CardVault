import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/app_theme.dart';
import 'core/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-edge on Android — let Flutter draw behind status bar + nav bar
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Status bar: transparent, nav bar: match our tab bar color
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,       // white icons (over burgundy login)
    systemNavigationBarColor: AppTheme.primary,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Lock to portrait — cards app doesn't need landscape
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    throw StateError(
      'Missing SUPABASE_URL or SUPABASE_ANON_KEY. '
      'Rebuild with --dart-define (see Makefile DART_DEFINES). '
      'In VS Code/Cursor, use launch.json "toolArgs", not "args", for dart-define.',
    );
  }

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(const ProviderScope(child: CardVaultApp()));
}

class CardVaultApp extends ConsumerWidget {
  const CardVaultApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Card Locker',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => Builder(
        builder: (context) => _CupertinoTypographyBridge(child: child!),
      ),
    );
  }
}

/// Applies [AppTheme.cupertinoShellTheme] below [MaterialApp]'s [Theme] so
/// `Theme.of(context).brightness` is correct for Cupertino text defaults.
class _CupertinoTypographyBridge extends StatelessWidget {
  const _CupertinoTypographyBridge({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CupertinoTheme(
      data: AppTheme.cupertinoShellTheme(Theme.of(context).brightness),
      child: child,
    );
  }
}