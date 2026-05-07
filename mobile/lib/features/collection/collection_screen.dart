import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart' hide showAdaptiveDialog;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/chrome_metrics.dart';
import '../../core/theme/fonts.dart';
import '../../core/widgets/app_bar_avatar.dart';
import '../../core/services/cards_service.dart';
import '../../core/services/comps_service.dart';
import '../../core/models/user_card.dart';
import '../../core/widgets/card_fan_loader.dart';
import '../../core/widgets/frosted_chrome_layer.dart';
import '../../core/widgets/sliver_frosted_header.dart';
import '../../core/utils/adaptive_ui.dart';
import 'widgets/list_item_card.dart';
import 'widgets/set_row_tile.dart';
import 'widgets/filter_sort_action_bar.dart';

enum SortOption { dateDesc, playerAz, valueDesc, plPct, movingUp }
enum SetSortOption { pctDesc, valueDesc, name }

class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key});

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  final _searchCtrl = TextEditingController();
  final _setSearchCtrl = TextEditingController();
  String _query = '';
  String _setQuery = '';
  SortOption _sort = SortOption.dateDesc;
  SetSortOption _setSort = SetSortOption.pctDesc;
  final Set<String> _activeFilters = {};
  final Set<String> _refreshingStacks = {};
  final Set<String> _setViewSports = {};
  bool _showSets = false;

  List<CardStack> _filter(List<CardStack> stacks) {
    var result = stacks.where((s) {
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        if (!s.player.toLowerCase().contains(q) &&
            !(s.set?.toLowerCase().contains(q) ?? false) &&
            !s.sport.toLowerCase().contains(q)) { return false; }
      }
      if (_activeFilters.contains('RC') && !s.rookie) return false;
      if (_activeFilters.contains('AUTO') && !s.autograph) return false;
      if (_activeFilters.contains('PATCH') && !s.memorabilia) return false;
      return true;
    }).toList();

    result.sort((a, b) => switch (_sort) {
      SortOption.playerAz  => a.player.compareTo(b.player),
      SortOption.valueDesc => b.totalValue.compareTo(a.totalValue),
      SortOption.plPct     => b.plPct.compareTo(a.plPct),
      SortOption.movingUp  => b.valueTrend != a.valueTrend
          ? b.valueTrend.compareTo(a.valueTrend)
          : b.valueChangePct.compareTo(a.valueChangePct),
      SortOption.dateDesc  => (b.latestCreatedAt ?? DateTime(0)).compareTo(a.latestCreatedAt ?? DateTime(0)),
    });
    return result;
  }

  Future<void> _deleteCard(String cardId) async {
    final confirm = await showAdaptiveDialog<bool>(
      context: context,
      title: 'Delete Card',
      content: 'Remove this card from your collection?',
      cancelLabel: 'Cancel',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (confirm == true) {
      await ref.read(cardsServiceProvider).deleteCard(cardId);
      ref.invalidate(userCardsProvider);
    }
  }

  String _stackKey(CardStack stack) => stack.stackKey;

  Future<void> _refreshStack(CardStack stack) async {
    final key = _stackKey(stack);
    setState(() => _refreshingStacks.add(key));
    final comps = ref.read(compsServiceProvider);
    try {
      await Future.wait(stack.cards.map((c) => comps.refreshCardValue(c.id)));
      ref.invalidate(userCardsProvider);
      if (mounted) AdaptiveSnackBar.show(context, message: 'Market value updated', type: AdaptiveSnackBarType.success, duration: const Duration(seconds: 2));
    } catch (e) {
      if (mounted) AdaptiveSnackBar.show(context, message: 'Refresh failed: $e', type: AdaptiveSnackBarType.error, duration: const Duration(seconds: 3));
    } finally {
      if (mounted) setState(() => _refreshingStacks.remove(key));
    }
  }

  String get _setSortKey => switch (_setSort) {
    SetSortOption.valueDesc => 'value-desc',
    SetSortOption.name      => 'name',
    _                       => 'pct-desc',
  };

  Widget _buildTopControls({
    required ColorScheme colors,
    required bool showSets,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ChromeMetrics.compactHorizontalInset,
        ChromeMetrics.segmentOnlyTopInset,
        ChromeMetrics.compactHorizontalInset,
        ChromeMetrics.segmentOnlyBottomInset,
      ),
      child: Column(
        children: [
          AdaptiveSegmentedControl(
            labels: const ['Cards', 'Sets'],
            selectedIndex: showSets ? 1 : 0,
            onValueChanged: (index) => setState(() => _showSets = index == 1),
            color: colors.primary,
          ),
          const SizedBox(height: ChromeMetrics.segmentOnlyBottomInset),
          FilterSortActionBar<void>(
            searchText: showSets ? _setQuery : _query,
            onSearchChanged: (v) => setState(() {
              if (showSets) {
                _setQuery = v;
              } else {
                _query = v;
              }
            }),
            onSearchClear: () {
              if (showSets) {
                _setSearchCtrl.clear();
                setState(() => _setQuery = '');
              } else {
                _searchCtrl.clear();
                setState(() => _query = '');
              }
            },
            searchHint: showSets ? 'Search sets…' : 'Search player, set, sport…',
          ),
        ],
      ),
    );
  }

  Widget _buildPinnedChromeHeader({
    required ColorScheme colors,
    required bool showSets,
    required double navOffset,
  }) {
    return FrostedChromeLayer(
      child: Padding(
        padding: EdgeInsets.only(top: navOffset),
        child: _buildTopControls(colors: colors, showSets: showSets),
      ),
    );
  }

  Widget _buildActionCapsule({
    required ColorScheme colors,
    required List<Widget> children,
  }) {
    const radius = 24.0;
    return AdaptiveBlurView(
      blurStyle: BlurStyle.systemUltraThinMaterial,
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: colors.outline.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 3),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.18),
              blurRadius: 2,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.20),
                      Colors.white.withValues(alpha: 0.04),
                    ],
                  ),
                ),
              ),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: children),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final cardsAsync = ref.watch(userCardsProvider);
    final navOffset = MediaQuery.of(context).padding.top + kToolbarHeight;
    final sportsList = (cardsAsync.asData?.value ?? const <UserCard>[])
        .map((c) => c.sport.toUpperCase())
        .toSet()
        .toList()
      ..sort();
    final hasActiveFilters = _showSets ? _setViewSports.isNotEmpty : _activeFilters.isNotEmpty;
    final hasActiveSort = _showSets
        ? _setSort != SetSortOption.pctDesc
        : _sort != SortOption.dateDesc;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        forceMaterialTransparency: true,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        foregroundColor: colors.onSurface,
        flexibleSpace: const SizedBox.shrink(),
        centerTitle: false,
        title: Text(
          'Collection',
          style: AppFonts.appBarTitle.copyWith(color: colors.onSurface),
        ),
        actions: [
          _buildActionCapsule(
            colors: colors,
            children: [
              AdaptivePopupMenuButton.icon<String>(
                icon: hasActiveFilters
                    ? 'line.3.horizontal.decrease.circle.fill'
                    : 'line.3.horizontal.decrease.circle',
                tint: hasActiveFilters ? colors.primary : colors.onSurface,
                buttonStyle: PopupButtonStyle.plain,
                items: _showSets
                    ? [
                        for (final sport in sportsList)
                          AdaptivePopupMenuItem<String>(
                            label: _setViewSports.contains(sport) ? '✓ $sport' : sport,
                            icon: _setViewSports.contains(sport) ? 'checkmark.circle.fill' : 'circle',
                            value: 'set:$sport',
                          ),
                        if (_setViewSports.isNotEmpty)
                          const AdaptivePopupMenuItem<String>(
                            label: 'Clear Filters',
                            icon: 'xmark.circle',
                            value: '__clear_set_filters__',
                          ),
                      ]
                    : [
                        for (final filter in const ['RC', 'AUTO', 'PATCH'])
                          AdaptivePopupMenuItem<String>(
                            label: _activeFilters.contains(filter) ? '✓ $filter' : filter,
                            icon: _activeFilters.contains(filter) ? 'checkmark.circle.fill' : 'circle',
                            value: 'card:$filter',
                          ),
                        if (_activeFilters.isNotEmpty)
                          const AdaptivePopupMenuItem<String>(
                            label: 'Clear Filters',
                            icon: 'xmark.circle',
                            value: '__clear_card_filters__',
                          ),
                      ],
                onSelected: (_, entry) {
                  final value = entry.value;
                  if (value == null) return;
                  switch (value) {
                    case '__clear_set_filters__':
                      setState(_setViewSports.clear);
                      break;
                    case '__clear_card_filters__':
                      setState(_activeFilters.clear);
                      break;
                    default:
                      if (value.startsWith('set:')) {
                        final sport = value.substring(4);
                        setState(() {
                          _setViewSports.contains(sport)
                              ? _setViewSports.remove(sport)
                              : _setViewSports.add(sport);
                        });
                      } else if (value.startsWith('card:')) {
                        final filter = value.substring(5);
                        setState(() {
                          _activeFilters.contains(filter)
                              ? _activeFilters.remove(filter)
                              : _activeFilters.add(filter);
                        });
                      }
                  }
                },
              ),
              AdaptivePopupMenuButton.icon<String>(
                icon: hasActiveSort
                    ? 'arrow.up.arrow.down.circle.fill'
                    : 'arrow.up.arrow.down.circle',
                tint: hasActiveSort ? colors.primary : colors.onSurface,
                buttonStyle: PopupButtonStyle.plain,
                items: _showSets
                    ? [
                        AdaptivePopupMenuItem<String>(
                          label: _setSort == SetSortOption.pctDesc ? '✓ Most Complete' : 'Most Complete',
                          icon: 'percent',
                          value: 'set:pct',
                        ),
                        AdaptivePopupMenuItem<String>(
                          label: _setSort == SetSortOption.valueDesc ? '✓ Value ↓' : 'Value ↓',
                          icon: 'chart.line.uptrend.xyaxis',
                          value: 'set:value',
                        ),
                        AdaptivePopupMenuItem<String>(
                          label: _setSort == SetSortOption.name ? '✓ Name A-Z' : 'Name A-Z',
                          icon: 'textformat.abc',
                          value: 'set:name',
                        ),
                      ]
                    : [
                        AdaptivePopupMenuItem<String>(
                          label: _sort == SortOption.dateDesc ? '✓ Date Added' : 'Date Added',
                          icon: 'calendar',
                          value: 'card:date',
                        ),
                        AdaptivePopupMenuItem<String>(
                          label: _sort == SortOption.playerAz ? '✓ Player A-Z' : 'Player A-Z',
                          icon: 'textformat.abc',
                          value: 'card:player',
                        ),
                        AdaptivePopupMenuItem<String>(
                          label: _sort == SortOption.valueDesc ? '✓ Value ↓' : 'Value ↓',
                          icon: 'chart.line.uptrend.xyaxis',
                          value: 'card:value',
                        ),
                        AdaptivePopupMenuItem<String>(
                          label: _sort == SortOption.plPct ? '✓ P/L %' : 'P/L %',
                          icon: 'percent',
                          value: 'card:pl',
                        ),
                        AdaptivePopupMenuItem<String>(
                          label: _sort == SortOption.movingUp ? '✓ Moving Up' : 'Moving Up',
                          icon: 'arrow.up',
                          value: 'card:moving',
                        ),
                      ],
                onSelected: (_, entry) {
                  switch (entry.value) {
                    case 'set:pct':
                      setState(() => _setSort = SetSortOption.pctDesc);
                      break;
                    case 'set:value':
                      setState(() => _setSort = SetSortOption.valueDesc);
                      break;
                    case 'set:name':
                      setState(() => _setSort = SetSortOption.name);
                      break;
                    case 'card:date':
                      setState(() => _sort = SortOption.dateDesc);
                      break;
                    case 'card:player':
                      setState(() => _sort = SortOption.playerAz);
                      break;
                    case 'card:value':
                      setState(() => _sort = SortOption.valueDesc);
                      break;
                    case 'card:pl':
                      setState(() => _sort = SortOption.plPct);
                      break;
                    case 'card:moving':
                      setState(() => _sort = SortOption.movingUp);
                      break;
                  }
                },
              ),
            ],
          ),
          const SizedBox(width: 6),
          _buildActionCapsule(
            colors: colors,
            children: [
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
      body: Column(
        children: [
          // ── Content ───────────────────────────────────────
          Expanded(
            child: cardsAsync.when(
              loading: () => const Center(child: CardFanLoader()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (allCards) {
                final stacks = CardStack.fromCards(allCards);
                if (_showSets) {
                  return _buildSetsView(allCards, colors, navOffset);
                }
                final filtered = _filter(stacks);
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(userCardsProvider),
                  child: CustomScrollView(
                    slivers: [
                      SliverFrostedHeader(
                        height: navOffset + ChromeMetrics.segmentSearchHeaderExtent,
                        child: _buildPinnedChromeHeader(
                          colors: colors,
                          showSets: false,
                          navOffset: navOffset,
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
                            child: Text(
                              '${allCards.length} ${allCards.length == 1 ? 'card' : 'cards'}'
                              '${filtered.length != stacks.length ? ' · ${filtered.length} shown' : ''}',
                              style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.5)),
                            ),
                          ),
                        ),
                      ),
                      if (filtered.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Text(
                              _query.isNotEmpty || _activeFilters.isNotEmpty
                                  ? 'No cards match your filters.'
                                  : 'No cards yet. Tap Add Card to get started!',
                              style: TextStyle(color: colors.onSurface.withValues(alpha: 0.5)),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.only(bottom: 100),
                          sliver: SliverList.builder(
                            itemCount: filtered.length,
                            itemBuilder: (_, i) => ListItemCard(
                              index: i,
                              stack: filtered[i],
                              onDelete: _deleteCard,
                              onRefresh: _refreshStack,
                              isRefreshing: _refreshingStacks.contains(_stackKey(filtered[i])),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetsView(List<UserCard> cards, ColorScheme colors, double navOffset) {
    final allRows = SetRow.fromCards(cards, sortBy: _setSortKey);

    // Get unique sports for filtering
    final sports = <String>{};
    for (final card in cards) {
      sports.add(card.sport);
    }
    // Filter rows by sport and search query
    var filtered = _setViewSports.isEmpty
        ? allRows
        : allRows.where((row) => _setViewSports.contains(row.sport?.toUpperCase())).toList();
    if (_setQuery.isNotEmpty) {
      final q = _setQuery.toLowerCase();
      filtered = filtered.where((row) => row.setName.toLowerCase().contains(q)).toList();
    }

    if (allRows.isEmpty) {
      return CustomScrollView(
        slivers: [
            SliverFrostedHeader(
              height: navOffset + ChromeMetrics.segmentSearchHeaderExtent,
              child: _buildPinnedChromeHeader(
                colors: colors,
                showSets: true,
                navOffset: navOffset,
              ),
            ),
            const SliverChromeGap(height: ChromeMetrics.contentTopGapTight),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('📦', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 12),
                  const Text('No sets yet', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('Add cards from an imported release to track set completion.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: colors.onSurface.withValues(alpha: 0.5))),
                ]),
              ),
            ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(userCardsProvider),
      child: CustomScrollView(
        slivers: [
          SliverFrostedHeader(
            height: navOffset + ChromeMetrics.segmentSearchHeaderExtent,
            child: _buildPinnedChromeHeader(
              colors: colors,
              showSets: true,
              navOffset: navOffset,
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
                child: Text(
                  '${filtered.length} ${filtered.length == 1 ? 'set' : 'sets'}'
                  '${filtered.length != allRows.length ? ' · ${allRows.length} total' : ''}',
                  style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.5)),
                ),
              ),
            ),
          ),
          if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  _setViewSports.isNotEmpty
                      ? 'No sets match your sport filter.'
                      : 'No sets in your collection.',
                  style: TextStyle(color: colors.onSurface.withValues(alpha: 0.5)),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 100),
              sliver: SliverList.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) => SetRowTile(row: filtered[i]),
              ),
            ),
        ],
      ),
    );
  }

}

