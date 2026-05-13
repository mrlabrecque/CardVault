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
import '../../core/widgets/app_segmented_control.dart';
import '../../core/widgets/card_fan_loader.dart';
import '../../core/widgets/glass_nav_bar.dart';
import '../../core/widgets/modal_sheet_scaffold.dart';
import '../../core/widgets/sticky_chrome_scaffold.dart';

enum _MarketDataTab { portfolioMovers, topMovers }

class MarketDataScreen extends ConsumerStatefulWidget {
  const MarketDataScreen({super.key});

  @override
  ConsumerState<MarketDataScreen> createState() => _MarketDataScreenState();
}

class _MarketDataScreenState extends ConsumerState<MarketDataScreen> {
  _MarketDataTab _tab = _MarketDataTab.portfolioMovers;
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
    final colors = Theme.of(context).colorScheme;

    return StickyChromeScaffold(
      stickyHeightEstimate: 58,
      blurSigma: 12,
      stickySurfaceTintAlpha: 0.2,
      appBar: buildGlassNavBar(
        context,
        useBlurBackground: true,
        blurSigma: 14,
        surfaceTintAlpha: 0.22,
        title: Text(
          'Market Data',
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
      stickyChrome: Padding(
        padding: const EdgeInsets.fromLTRB(
          ChromeMetrics.compactHorizontalInset,
          ChromeMetrics.segmentOnlyTopInset,
          ChromeMetrics.compactHorizontalInset,
          ChromeMetrics.segmentOnlyBottomInset,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSegmentedControl(
              segmentKey: const ValueKey('market-data-tabs'),
              labels: const ['Portfolio movers', 'Top gainers'],
              selectedIndex: _tab == _MarketDataTab.portfolioMovers ? 0 : 1,
              onValueChanged: (index) {
                setState(() {
                  _tab = index == 0 ? _MarketDataTab.portfolioMovers : _MarketDataTab.topMovers;
                });
              },
              color: colors.primary,
            ),
            // Same rhythm as collection pinned chrome: gap below segment before the next row.
            const SizedBox(height: ChromeMetrics.segmentOnlyBottomInset),
          ],
        ),
      ),
      bodyBuilder: (context, contentTopInset) {
        return _tab == _MarketDataTab.portfolioMovers
            ? _buildVaultTab(contentTopInset)
            : _buildTopMoversTab(contentTopInset);
      },
    );
  }

  Widget _buildVaultTab(double contentTopInset) {
    final async = ref.watch(vaultPortfolioMoversRawProvider);
    return async.when(
      loading: () => _buildLoading(contentTopInset),
      error: (e, _) => _buildError(contentTopInset, e.toString()),
      data: (raw) {
        final data = vaultMoversForDisplay(raw, _selectedSport);
        return _buildVaultScrollable(contentTopInset, data);
      },
    );
  }

  Widget _buildTopMoversTab(double contentTopInset) {
    final async = ref.watch(marketTopMoversRawProvider);
    return async.when(
      loading: () => _buildLoading(contentTopInset),
      error: (e, _) => _buildError(contentTopInset, e.toString()),
      data: (raw) {
        final hot = marketTopMoversForDisplay(raw, _selectedSport);
        final data = PortfolioMoversData(
          hot: hot,
          cold: const [],
          lastUpdated: DateTime.now(),
        );
        return _buildTopMoversScrollable(contentTopInset, data);
      },
    );
  }

  Widget _buildVaultScrollable(double contentTopInset, PortfolioMoversData data) {
    final colors = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(vaultPortfolioMoversRawProvider),
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, contentTopInset, 16, 100),
        children: [
          if (data.hot.isEmpty && data.cold.isEmpty)
            _buildEmptyVault(colors)
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
              ..._buildMoverRows(data.hot, topMoversFooter: false),
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
              ..._buildMoverRows(data.cold, topMoversFooter: false),
            ],
          ],
          _buildInfoFooter(
            colors,
            label: 'How Portfolio movers works',
            onPressed: () => _showVaultInfo(context),
          ),
        ],
      ),
    );
  }

  Widget _buildTopMoversScrollable(double contentTopInset, PortfolioMoversData data) {
    final colors = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(marketTopMoversRawProvider),
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, contentTopInset, 16, 100),
        children: [
          if (data.hot.isEmpty && data.cold.isEmpty)
            _buildEmptyTopMovers()
          else ...[
            if (data.hot.isNotEmpty) ...[
              Row(
                children: [
                  const Text('🔥 Top gainers', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Text('${data.hot.length} cards', style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                ],
              ),
              const SizedBox(height: 8),
              ..._buildMoverRows(data.hot, topMoversFooter: true),
            ],
          ],
          _buildInfoFooter(
            colors,
            label: 'How Top movers works',
            onPressed: () => _showTopMoversInfo(context),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyVault(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Text('📊', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text('No data yet', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            _selectedSport == null
                ? 'Add cards and refresh comps so previous vs current values exist—or pull to refresh.'
                : 'No ${_selectedSport!} rows in this snapshot. Try All sports or another filter.',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTopMovers() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Text('📊', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text('No data yet', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            _selectedSport == null
                ? 'Card Hedge returned no priced rows in the allowed sports—or try pull-to-refresh.'
                : 'No ${_selectedSport!} cards in this batch. Try All sports or another filter.',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoFooter(ColorScheme colors, {required String label, required VoidCallback onPressed}) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Center(
        child: TextButton.icon(
          onPressed: onPressed,
          icon: Icon(Icons.info_outline, size: 18, color: colors.primary),
          label: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading(double contentTopInset) {
    return Padding(
      padding: EdgeInsets.only(top: contentTopInset),
      child: const Center(child: CardFanLoader(size: 72)),
    );
  }

  Widget _buildError(double contentTopInset, String error) {
    return Padding(
      padding: EdgeInsets.only(top: contentTopInset + 24),
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

  void _showVaultInfo(BuildContext context) {
    showAdaptiveSheet(
      context: context,
      builder: (_) => ModalSheetScaffold(
        title: 'Portfolio movers',
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Portfolio movers ranks players by how average card values moved across all user\'s collections, using each owned card’s current value versus its prior value.',
              style: TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.5),
            ),
            SizedBox(height: 10),
            Text(
              '🔥 Rising — largest average increases\n🧊 Cooling — largest average decreases',
              style: TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.5),
            ),
            SizedBox(height: 10),
            Text(
              'This is not a live market-wide index.',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  void _showTopMoversInfo(BuildContext context) {
    showAdaptiveSheet(
      context: context,
      builder: (_) => ModalSheetScaffold(
        title: 'Top movers',
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top gainers lists market-wide cards with the strongest recent price gains. Each row shows a headline grade price and the published gain percentage.',
              style: TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.5),
            ),
            SizedBox(height: 10),
            Text(
              '🔥 Top gainers — We filter out unrealistic spikes.',
              style: TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.5),
            ),
            SizedBox(height: 10),
            Text(
              'Data is market-wide; use the collection list and card detail for owned-card P/L.',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMoverRows(
    List<PortfolioMover> movers, {
    required bool topMoversFooter,
  }) {
    return movers.map((mover) {
      final changeColor = mover.isTrendingUp ? const Color(0xFF059669) : const Color(0xFFef4444);
      final changeBgColor = mover.isTrendingUp ? const Color(0xFFecfdf5) : const Color(0xFFFEF2F2);
      final cardLabel = topMoversFooter
          ? (mover.currentVolume > 0 ? '${mover.currentVolume} sales (30d/7d)' : 'Sales volume n/a')
          : (mover.currentVolume == 1 ? '1 card' : '${mover.currentVolume} cards');

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
                  if (mover.cardDescription != null && mover.cardDescription!.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      mover.cardDescription!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280), height: 1.25),
                    ),
                  ],
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
