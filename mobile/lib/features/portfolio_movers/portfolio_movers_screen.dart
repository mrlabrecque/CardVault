import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/portfolio_mover.dart';
import '../../core/services/portfolio_movers_service.dart';
import '../../core/theme/chrome_metrics.dart';
import '../../core/theme/fonts.dart';
import '../../core/utils/adaptive_ui.dart';
import '../../core/utils/currency_format.dart';
import '../../core/widgets/app_bar_action_capsule.dart';
import '../../core/widgets/app_bar_avatar.dart';
import '../../core/widgets/app_overflow_menu.dart';
import '../../core/widgets/glass_nav_bar.dart';
import '../../core/widgets/modal_sheet_scaffold.dart';

class PortfolioMoversScreen extends ConsumerStatefulWidget {
  const PortfolioMoversScreen({super.key});

  @override
  ConsumerState<PortfolioMoversScreen> createState() => _PortfolioMoversScreenState();
}

class _PortfolioMoversScreenState extends ConsumerState<PortfolioMoversScreen> {
  String? _selectedSport;

  static const _sportChoices = <String>['NBA', 'NFL', 'MLB', 'NHL'];

  bool get _sportFilterActive => _selectedSport != null;

  String _sportIcon(String sport) {
    switch (sport) {
      case 'NBA':
        return 'basketball.fill';
      case 'NFL':
        return 'football.fill';
      case 'MLB':
        return 'baseball.fill';
      case 'NHL':
        return 'hockey.puck.fill';
      default:
        return 'circle.fill';
    }
  }

  @override
  Widget build(BuildContext context) {
    final moversAsync = ref.watch(portfolioMoversProvider(_selectedSport));
    final colors = Theme.of(context).colorScheme;
    final navOffset = MediaQuery.paddingOf(context).top + kToolbarHeight;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: buildGlassNavBar(
        context,
        useBlurBackground: true,
        title: Text(
          'Portfolio Movers',
          style: AppFonts.appBarTitle.copyWith(color: colors.onSurface),
        ),
        actions: [
          AppBarActionCapsule(
            children: [
              AdaptivePopupMenuButton.icon<String>(
                icon: _sportFilterActive
                    ? 'line.3.horizontal.decrease.circle.fill'
                    : 'line.3.horizontal.decrease.circle',
                tint: _sportFilterActive ? colors.primary : colors.onSurface,
                buttonStyle: PopupButtonStyle.plain,
                items: [
                  AdaptivePopupMenuItem(
                    label: _selectedSport == null ? '✓ All sports' : 'All sports',
                    icon: 'circle.grid.3x3',
                    value: 'all',
                  ),
                  ..._sportChoices.map(
                    (s) => AdaptivePopupMenuItem(
                      label: _selectedSport == s ? '✓ $s' : s,
                      icon: _sportIcon(s),
                      value: s,
                    ),
                  ),
                ],
                onSelected: (_, entry) {
                  final v = entry.value;
                  setState(() => _selectedSport = v == null || v == 'all' ? null : v);
                },
              ),
            ],
          ),
          const SizedBox(width: 6),
          AppBarActionCapsule(
            children: [
              AppOverflowMenu(
                tint: colors.onSurface,
                buttonStyle: PopupButtonStyle.plain,
                padding: const EdgeInsets.only(left: 4, right: 0),
              ),
              AppBarAvatar(
                iconOnly: true,
                tint: colors.onSurface,
                buttonStyle: PopupButtonStyle.plain,
                padding: const EdgeInsets.only(left: 2, right: 6),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: moversAsync.when(
        loading: () => _buildSkeleton(navOffset),
        error: (e, _) => _buildError(navOffset, e.toString()),
        data: (data) => _buildContent(navOffset, data),
      ),
    );
  }

  Widget _buildSkeleton(double navOffset) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, navOffset + ChromeMetrics.contentTopGap, 16, 100),
      children: [
        const SizedBox(height: 16),
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 24),
        ...List.generate(5, (_) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            )),
      ],
    );
  }

  Widget _buildError(double navOffset, String error) {
    return Padding(
      padding: EdgeInsets.only(top: navOffset),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Color(0xFF9CA3AF)),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Error: $error',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPortfolioMoversInfo(BuildContext context) {
    showAdaptiveSheet(
      context: context,
      builder: (_) => ModalSheetScaffold(
        title: 'What is Portfolio Movers',
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.info_outline, size: 18, color: Color(0xFFF97316)),
                ),
                const SizedBox(width: 12),
                const SizedBox.shrink(),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Portfolio Movers ranks players by how average card values moved across all Vault collections over time, using each owned card’s current value versus its prior value.',
              style: TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.5),
            ),
            const SizedBox(height: 10),
            const Text(
              '🔥 Rising — Largest average increases\n🧊 Cooling — Largest average decreases',
              style: TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.5),
            ),
            const SizedBox(height: 10),
            const Text(
              'This is not a live market-wide eBay index; it reflects aggregate movement among collectors in Card Vault who have refreshed pricing.',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(double navOffset, PortfolioMoversData data) {
    final colors = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(portfolioMoversProvider(_selectedSport)),
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, navOffset + ChromeMetrics.contentTopGap, 16, 100),
        children: [
          if (data.hot.isEmpty && data.cold.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    const Text('📊', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    const Text('No data yet', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 4),
                    const Text(
                      'Add cards and refresh comps so previous vs current values exist—or check another sport.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else ...[
            if (data.hot.isNotEmpty) ...[
              Row(
                children: [
                  const Text('🔥 Rising', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Text('${data.hot.length} players', style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                ],
              ),
              const SizedBox(height: 8),
              ..._buildMoverRows(data.hot, isHot: true),
              const SizedBox(height: 24),
            ],
            if (data.cold.isNotEmpty) ...[
              Row(
                children: [
                  const Text('🧊 Cooling', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Text('${data.cold.length} players', style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                ],
              ),
              const SizedBox(height: 8),
              ..._buildMoverRows(data.cold, isHot: false),
            ],
          ],
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Center(
              child: TextButton.icon(
                onPressed: () => _showPortfolioMoversInfo(context),
                icon: Icon(Icons.info_outline, size: 18, color: colors.primary),
                label: Text(
                  'How Portfolio Movers works',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMoverRows(List<PortfolioMover> movers, {required bool isHot}) {
    return movers.map((mover) {
      final changeColor = mover.isTrendingUp ? const Color(0xFF059669) : const Color(0xFFef4444);
      final changeBgColor = mover.isTrendingUp ? const Color(0xFFecfdf5) : const Color(0xFFFEF2F2);
      final cardLabel = mover.currentVolume == 1 ? '1 card' : '${mover.currentVolume} cards';

      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(mover.playerName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(mover.sport, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFf3f4f6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          formatUsd(mover.currentAvg),
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF374151)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: changeBgColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${mover.priceChangePct > 0 ? '+' : ''}${mover.priceChangePct.toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: changeColor),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  cardLabel,
                  style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
          ],
        ),
      );
    }).toList();
  }
}
