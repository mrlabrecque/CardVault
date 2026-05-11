import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/fonts.dart';
import '../../core/widgets/app_bar_shell_trailing_actions.dart';
import '../../core/widgets/glass_nav_bar.dart';

class AdminPortfolioMoversScreen extends ConsumerWidget {
  const AdminPortfolioMoversScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: buildGlassNavBar(
        context,
        centerTitle: false,
        title: Text('Portfolio Movers (admin)', style: AppFonts.appBarTitle.copyWith(color: colors.onSurface)),
        actions: appBarShellTrailingActions(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: const Text(
              'Portfolio Movers reads from the database only—no batch eBay scrape. '
              'The Tools screen calls RPC `portfolio_movers_from_vault`, which aggregates '
              'all users’ `user_cards` (avg current vs previous value per player/sport after comps refresh).',
              style: TextStyle(
                color: Color(0xFF1E3A8A),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: const Text(
              'Legacy: `market-movers-refresh` (ESPN + Bright Data) is not used by the app. '
              'Disable its cron in Supabase if you want zero scraping.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF374151),
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Apply migration `20260511120000` / `20260512120000` so `portfolio_movers_from_vault` exists. '
            'If the screen errors with a missing function, run `supabase db push` or apply SQL from migrations.',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280), height: 1.4),
          ),
        ],
      ),
    );
  }
}
