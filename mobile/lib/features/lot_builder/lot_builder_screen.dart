import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/user_card.dart';
import '../../core/services/cards_service.dart';
import '../../core/services/lot_service.dart';
import '../../core/theme/chrome_metrics.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/fonts.dart';
import '../../core/widgets/card_info_section.dart';
import '../../core/utils/currency_format.dart';
import '../../core/widgets/list_item_usd_text.dart';
import '../../core/widgets/card_thumbnail.dart';
import '../../core/widgets/adaptive_list_card.dart';
import '../../core/widgets/card_fan_loader.dart';
import '../../core/widgets/app_bar_action_capsule.dart';
import '../../core/widgets/app_bar_shell_trailing_actions.dart';
import '../../core/widgets/app_segmented_control.dart';
import '../../core/widgets/frosted_chrome_layer.dart';
import '../../core/widgets/glass_nav_bar.dart';
import '../../core/widgets/sliver_frosted_header.dart';
import '../collection/widgets/filter_sort_action_bar.dart';

enum _SortOption { dateDesc, playerAz, valueDesc }

class LotBuilderScreen extends ConsumerStatefulWidget {
  const LotBuilderScreen({super.key});

  @override
  ConsumerState<LotBuilderScreen> createState() => _LotBuilderScreenState();
}

class _LotBuilderScreenState extends ConsumerState<LotBuilderScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Set<String> _filters = {};
  _SortOption _sort = _SortOption.dateDesc;
  bool _showBasket = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<UserCard> _filtered(List<UserCard> all) {
    var result = all
        .where((c) => c.displayValue != null && c.displayValue! > 0)
        .toList();
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      result = result.where((c) =>
        c.player.toLowerCase().contains(q) ||
        (c.set?.toLowerCase().contains(q) ?? false) ||
        (c.checklist?.toLowerCase().contains(q) ?? false) ||
        c.sport.toLowerCase().contains(q),
      ).toList();
    }
    if (_filters.contains('RC'))    result = result.where((c) => c.rookie).toList();
    if (_filters.contains('AUTO'))  result = result.where((c) => c.autograph).toList();
    if (_filters.contains('PATCH')) result = result.where((c) => c.memorabilia).toList();

    result.sort((a, b) => switch (_sort) {
      _SortOption.playerAz  => a.player.compareTo(b.player),
      _SortOption.valueDesc => (b.displayValue ?? 0).compareTo(a.displayValue ?? 0),
      _SortOption.dateDesc  => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    });

    return result;
  }

  void _toggleFilter(String f) => setState(() {
    _filters.contains(f) ? _filters.remove(f) : _filters.add(f);
  });

  @override
  Widget build(BuildContext context) {
    final lot       = ref.watch(lotProvider);
    final notifier  = ref.read(lotProvider.notifier);
    final colors = Theme.of(context).colorScheme;
    final navOffset = MediaQuery.of(context).padding.top + kToolbarHeight;
    final hasActiveFilter = _filters.isNotEmpty;
    final hasActiveSort = _sort != _SortOption.dateDesc;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: buildGlassNavBar(
        context,
        useBlurBackground: _showBasket,
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: Text(
          'Lot Builder',
          style: AppFonts.appBarTitle.copyWith(color: colors.onSurface),
        ),
        actions: [
          AppBarActionCapsule(
            children: [
              AdaptivePopupMenuButton.icon<String>(
                icon: hasActiveFilter
                    ? 'line.3.horizontal.decrease.circle.fill'
                    : 'line.3.horizontal.decrease.circle',
                tint: hasActiveFilter ? colors.primary : colors.onSurface,
                buttonStyle: PopupButtonStyle.plain,
                items: [
                  for (final filter in const ['RC', 'AUTO', 'PATCH'])
                    AdaptivePopupMenuItem(
                      label: _filters.contains(filter) ? '✓ $filter' : filter,
                      icon: _filters.contains(filter) ? 'checkmark.circle.fill' : 'circle',
                      value: filter,
                    ),
                  if (_filters.isNotEmpty)
                    const AdaptivePopupMenuItem(
                      label: 'Clear Filters',
                      icon: 'xmark.circle',
                      value: '__clear__',
                    ),
                ],
                onSelected: (_, entry) {
                  if (entry.value == '__clear__') {
                    setState(_filters.clear);
                    return;
                  }
                  final value = entry.value;
                  if (value != null) _toggleFilter(value);
                },
              ),
              AdaptivePopupMenuButton.icon<_SortOption>(
                icon: hasActiveSort ? 'arrow.up.arrow.down.circle.fill' : 'arrow.up.arrow.down.circle',
                tint: hasActiveSort ? colors.primary : colors.onSurface,
                buttonStyle: PopupButtonStyle.plain,
                items: [
                  AdaptivePopupMenuItem(
                    value: _SortOption.dateDesc,
                    label: _sort == _SortOption.dateDesc ? '✓ Date Added' : 'Date Added',
                    icon: 'calendar',
                  ),
                  AdaptivePopupMenuItem(
                    value: _SortOption.playerAz,
                    label: _sort == _SortOption.playerAz ? '✓ Player A-Z' : 'Player A-Z',
                    icon: 'textformat.abc',
                  ),
                  AdaptivePopupMenuItem(
                    value: _SortOption.valueDesc,
                    label: _sort == _SortOption.valueDesc ? '✓ Value ↓' : 'Value ↓',
                    icon: 'chart.line.uptrend.xyaxis',
                  ),
                ],
                onSelected: (_, entry) {
                  final value = entry.value;
                  if (value == null) return;
                  setState(() => _sort = value);
                },
              ),
            ],
          ),
          const SizedBox(width: 6),
          ...appBarShellTrailingActions(context),
        ],
      ),
      body: Column(
        children: [
          if (_showBasket) ...[
            Expanded(
              child: _BasketScrollView(
                navOffset: navOffset,
                basketCount: lot.items.length,
                onToggleBrowseBasket: (v) => setState(() => _showBasket = v),
                lot: lot,
                notifier: notifier,
              ),
            ),
          ] else
            Expanded(
              child: _BrowseView(
                navOffset: navOffset,
                onToggleBrowseBasket: (v) => setState(() => _showBasket = v),
                searchCtrl: _searchCtrl,
                query: _query,
                sort: _sort,
                onSortChanged: (s) => setState(() => _sort = s),
                filters: _filters,
                notifier: notifier,
                onQueryChanged: (v) => setState(() => _query = v),
                onFilterToggle: _toggleFilter,
                filteredCards: _filtered,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Browse view ───────────────────────────────────────────────────────────────

class _BasketHeader extends StatelessWidget {
  const _BasketHeader({
    required this.navOffset,
    required this.basketCount,
    required this.onToggleBrowseBasket,
  });

  final double navOffset;
  final int basketCount;
  final ValueChanged<bool> onToggleBrowseBasket;

  /// Segment + subtle frost bleed below it. Keep in sync with pinned header height.
  static const double extentBelowNav = ChromeMetrics.lotBasketHeaderExtent + ChromeMetrics.segmentOnlyTopInset;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final basketLabel = basketCount > 0 ? 'Basket ($basketCount)' : 'Basket';
    final topInset = navOffset + ChromeMetrics.segmentOnlyTopInset;
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        return FrostedChromeLayer(
          height: h.isFinite ? h : null,
          child: Padding(
            padding: EdgeInsets.only(
              top: topInset,
              left: ChromeMetrics.horizontalInset,
              right: ChromeMetrics.horizontalInset,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSegmentedControl(
                  key: ValueKey<String>('basket_tab_$basketCount'),
                  labels: ['Browse', basketLabel],
                  selectedIndex: 1,
                  onValueChanged: (index) => onToggleBrowseBasket(index == 1),
                  color: colors.primary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BasketScrollView extends StatelessWidget {
  const _BasketScrollView({
    required this.navOffset,
    required this.basketCount,
    required this.onToggleBrowseBasket,
    required this.lot,
    required this.notifier,
  });

  final double navOffset;
  final int basketCount;
  final ValueChanged<bool> onToggleBrowseBasket;
  final LotState lot;
  final LotNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverFrostedHeader(
          height: navOffset + _BasketHeader.extentBelowNav,
          child: _BasketHeader(
            navOffset: navOffset,
            basketCount: basketCount,
            onToggleBrowseBasket: onToggleBrowseBasket,
          ),
        ),
        // Non-zero gap so basket body clears pinned frost (tight gap lets the first row read blurred).
        const SliverChromeGap(height: ChromeMetrics.contentTopGap),
        SliverToBoxAdapter(
          child: _BasketView(lot: lot, notifier: notifier),
        ),
      ],
    );
  }
}

class _BrowseView extends ConsumerWidget {
  const _BrowseView({
    required this.navOffset,
    required this.onToggleBrowseBasket,
    required this.searchCtrl,
    required this.query,
    required this.sort,
    required this.onSortChanged,
    required this.filters,
    required this.notifier,
    required this.onQueryChanged,
    required this.onFilterToggle,
    required this.filteredCards,
  });

  final double navOffset;
  final ValueChanged<bool> onToggleBrowseBasket;
  final TextEditingController searchCtrl;
  final String query;
  final _SortOption sort;
  final ValueChanged<_SortOption> onSortChanged;
  final Set<String> filters;
  final LotNotifier notifier;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onFilterToggle;
  final List<UserCard> Function(List<UserCard>) filteredCards;

  /// Chrome below app bar: segments + gap + search row + bottom inset (tight fit; avoids dead blur padding).
  static const double _browseChromeExtentBelowNav =
      ChromeMetrics.lotBrowseHeaderExtent + ChromeMetrics.segmentOnlyTopInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lot = ref.watch(lotProvider);
    final cardsAsync = ref.watch(userCardsProvider);
    final basketLabel = lot.items.isNotEmpty ? 'Basket (${lot.items.length})' : 'Basket';

    return cardsAsync.when(
      loading: () => const Center(child: CardFanLoader()),
      error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Color(0xFFDC2626)))),
      data: (allCards) {
        final cards = filteredCards(allCards);
        return CustomScrollView(
          slivers: [
            SliverFrostedHeader(
              height: navOffset + _browseChromeExtentBelowNav,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final h = constraints.maxHeight;
                  return FrostedChromeLayer(
                    height: h.isFinite ? h : null,
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: navOffset + ChromeMetrics.segmentOnlyTopInset,
                        left: ChromeMetrics.horizontalInset,
                        right: ChromeMetrics.horizontalInset,
                        bottom: ChromeMetrics.searchBarBottomInset,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppSegmentedControl(
                            key: ValueKey<String>('browse_tab_${lot.items.length}'),
                            labels: ['Browse', basketLabel],
                            selectedIndex: 0,
                            onValueChanged: (index) => onToggleBrowseBasket(index == 1),
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: ChromeMetrics.segmentToSearchGap),
                          FilterSortActionBar<_SortOption>(
                            searchController: searchCtrl,
                            searchText: query,
                            onSearchChanged: onQueryChanged,
                            onSearchClear: () {
                              searchCtrl.clear();
                              onQueryChanged('');
                            },
                            searchHint: 'Search player, set, sport…',
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SliverChromeGap(height: ChromeMetrics.contentTopGapTight),
            SliverToBoxAdapter(
              child: Padding(
                padding: ChromeMetrics.listCountPadding(
                  bottom: ChromeMetrics.listCountBottomInsetRoomy,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${cards.length} cards',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                ),
              ),
            ),
            if (allCards.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text('No cards in your collection yet.',
                      style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
                ),
              )
            else if (cards.isEmpty &&
                allCards.isNotEmpty &&
                query.isEmpty &&
                filters.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'No cards with a market value. Refresh pricing before adding cards to a lot.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                    ),
                  ),
                ),
              )
            else if (cards.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text('No cards match your search.',
                      style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList.builder(
                  itemCount: cards.length,
                  itemBuilder: (_, i) {
                    final card = cards[i];
                    final inLot = lot.itemIds.contains(card.id);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _BrowseCardRow(
                        card: card,
                        inLot: inLot,
                        onToggle: () => notifier.toggle(card),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BrowseCardRow extends StatelessWidget {
  const _BrowseCardRow({required this.card, required this.inLot, required this.onToggle});
  final UserCard card;
  final bool inLot;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AdaptiveListCard(
        margin: EdgeInsets.zero,
        color: inLot ? const Color(0xFFF0FDF4) : null,
        highlightBorderColor: inLot ? const Color(0xFF86EFAC) : null,
        highlightBorderWidth: 1,
        child: Padding(
          padding: const EdgeInsets.all(0),
          child: IntrinsicHeight(
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardThumbnail(imageUrl: card.imageUrl, sport: card.sport),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 6, 12),                
                        child: CardInfoSection.fromUserCard(card),
              ),
              ),
                  Padding(padding: EdgeInsets.all(12),
                    child:
                    Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ListItemUsdText(value: card.displayValue),
                  const SizedBox(height: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: inLot ? const Color(0xFF22C55E) : AppTheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      inLot ? Icons.check : Icons.add,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

// ── Basket view ───────────────────────────────────────────────────────────────

class _BasketView extends StatelessWidget {
  const _BasketView({required this.lot, required this.notifier});
  final LotState lot;
  final LotNotifier notifier;

  String get _pctLabel {
    if (lot.pct < 100) return '${lot.pct}% — Discount';
    if (lot.pct == 100) return '100% — Market Value';
    return '${lot.pct}% — Premium';
  }

  @override
  Widget build(BuildContext context) {
    if (lot.items.isEmpty) {
      return SizedBox(
        height: 420,
        child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(child: Text('📦', style: TextStyle(fontSize: 30))),
            ),
            const SizedBox(height: 12),
            const Text('Basket is empty', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF9CA3AF))),
            const Text('Switch to Browse and tap cards to add them.', style: TextStyle(fontSize: 12, color: Color(0xFFD1D5DB))),
          ],
        ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Asking price card — centered
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const Text(
                'ASKING PRICE',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFFCA5A5), letterSpacing: 1.5),
              ),
              Text(
                formatUsd(lot.askingPrice),
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 2),
              Text(
                '${lot.pct}% of ${formatUsd(lot.totalValue)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFFFCA5A5)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Slider — bare, with end labels above and pct label below
        Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('50% Discount', style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                const Text('150% Premium', style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
              ],
            ),
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: AppTheme.primary,
                inactiveTrackColor: const Color(0xFFE5E7EB),
                thumbColor: AppTheme.primary,
                overlayColor: AppTheme.primary.withValues(alpha: 0.1),
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              ),
              child: Slider(
                min: 50,
                max: 150,
                divisions: 20,
                value: lot.pct.toDouble(),
                onChanged: (v) => notifier.setPct(v.round()),
              ),
            ),
            Text(
              _pctLabel,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Divider(color: Theme.of(context).colorScheme.outlineVariant, height: 1),
        const SizedBox(height: 16),
        // Summary: stats (left) + Clear (right, same row)
        AdaptiveListCard(
          margin: EdgeInsets.zero,
          cornerRadius: 16,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${lot.items.length} ${lot.items.length == 1 ? 'card' : 'cards'}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                          fontFamily: AppFonts.fontFamily,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Market total: ${formatUsd(lot.totalValue)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                          fontFamily: AppFonts.fontFamily,
                        ),
                      ),
                    ],
                  ),
                ),
                AdaptiveButton.child(
                  onPressed: notifier.clear,
                  style: AdaptiveButtonStyle.bordered,
                  color: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  borderRadius: BorderRadius.circular(12),
                  minSize: const Size(88, 44),
                  child: Text(
                    'Clear',
                    style: TextStyle(
                      fontSize: 15,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600,
                      fontFamily: AppFonts.fontFamily,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Card rows
        ...lot.items.map((card) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _BasketCardRow(card: card, onRemove: () => notifier.remove(card.id)),
        )),
      ],
      ),
    );
  }
}

class _BasketCardRow extends StatelessWidget {
  const _BasketCardRow({required this.card, required this.onRemove});
  final UserCard card;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return AdaptiveListCard(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(0),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardThumbnail(imageUrl: card.imageUrl, sport: card.sport),
             Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 6, 12),                
                        child: CardInfoSection.fromUserCard(card),
                      ),

            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ListItemUsdText(value: card.displayValue),
                const SizedBox(height: 6),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: AdaptiveButton.child(
                    onPressed: onRemove,
                    style: AdaptiveButtonStyle.bordered,
                    color: const Color(0xFFF87171),
                    child: const Icon(Icons.close, size: 14),
                  ),
                ),
              ],
            ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

