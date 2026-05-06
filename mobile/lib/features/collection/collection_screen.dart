import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart' hide showAdaptiveDialog;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/fonts.dart';
import '../../core/widgets/app_bar_shell_trailing_actions.dart';
import '../../core/services/cards_service.dart';
import '../../core/services/comps_service.dart';
import '../../core/models/user_card.dart';
import '../../core/widgets/sticky_sub_header_layout.dart';
import '../../core/widgets/card_fan_loader.dart';
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

  void _toggleFilter(String f) => setState(() {
    _activeFilters.contains(f) ? _activeFilters.remove(f) : _activeFilters.add(f);
  });

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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final cardsAsync = ref.watch(userCardsProvider);

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Text(
          'Collection',
          style: AppFonts.appBarTitle,
        ),
        actions: appBarShellTrailingActions(context),
      ),
      body: Column(
        children: [
          // ── Tab toggle ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: AdaptiveSegmentedControl(
              labels: const ['Cards', 'Sets'],
              selectedIndex: _showSets ? 1 : 0,
              onValueChanged: (index) => setState(() => _showSets = index == 1),
              color: colors.primary,
            ),
          ),

          // ── Content ───────────────────────────────────────
          Expanded(
            child: cardsAsync.when(
              loading: () => const Center(child: CardFanLoader()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (allCards) {
                final stacks = CardStack.fromCards(allCards);
                if (_showSets) {
                  return _buildSetsView(allCards, colors);
                }
                final filtered = _filter(stacks);
                return StickySubHeaderLayout(
                  useScaffold: false,
                  header: const SizedBox.shrink(),
                  subHeader: FilterSortActionBar<SortOption>(
                    searchText: _query,
                    onSearchChanged: (v) => setState(() => _query = v),
                    onSearchClear: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                    searchHint: 'Search player, set, sport…',
                    filters: const ['RC', 'AUTO', 'PATCH'],
                    activeFilters: _activeFilters,
                    onFilterToggle: _toggleFilter,
                    sortOptions: [
                      SortMenuOption(value: SortOption.dateDesc, label: 'Date Added', selected: _sort == SortOption.dateDesc, sfSymbol: 'calendar'),
                      SortMenuOption(value: SortOption.playerAz, label: 'Player A–Z', selected: _sort == SortOption.playerAz, sfSymbol: 'textformat.abc'),
                      SortMenuOption(value: SortOption.valueDesc, label: 'Value ↓', selected: _sort == SortOption.valueDesc, sfSymbol: 'chart.line.uptrend.xyaxis'),
                      SortMenuOption(value: SortOption.plPct, label: 'P/L %', selected: _sort == SortOption.plPct, sfSymbol: 'percent'),
                      SortMenuOption(value: SortOption.movingUp, label: 'Moving Up', selected: _sort == SortOption.movingUp, sfSymbol: 'arrow.up'),
                    ],
                    onSortSelected: (s) => setState(() => _sort = s),
                    actionButton: null,
                  ),
                  label: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${allCards.length} ${allCards.length == 1 ? 'card' : 'cards'}'
                      '${filtered.length != stacks.length ? ' · ${filtered.length} shown' : ''}',
                      style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.5)),
                    ),
                  ),
                  body: RefreshIndicator(
                    onRefresh: () async => ref.invalidate(userCardsProvider),
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              _query.isNotEmpty || _activeFilters.isNotEmpty
                                  ? 'No cards match your filters.'
                                  : 'No cards yet. Tap Add Card to get started!',
                              style: TextStyle(color: colors.onSurface.withValues(alpha: 0.5)),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 100),
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetsView(List<UserCard> cards, ColorScheme colors) {
    final allRows = SetRow.fromCards(cards, sortBy: _setSortKey);

    // Get unique sports for filtering
    final sports = <String>{};
    for (final card in cards) {
      sports.add(card.sport);
    }
    final sportsList = sports.map((s) => s.toUpperCase()).toList()..sort();

    // Filter rows by sport and search query
    var filtered = _setViewSports.isEmpty
        ? allRows
        : allRows.where((row) => _setViewSports.contains(row.sport?.toUpperCase())).toList();
    if (_setQuery.isNotEmpty) {
      final q = _setQuery.toLowerCase();
      filtered = filtered.where((row) => row.setName.toLowerCase().contains(q)).toList();
    }

    if (allRows.isEmpty) {
      return Scaffold(
        body: Center(
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
      );
    }

    return StickySubHeaderLayout(
      useScaffold: false,
      header: const SizedBox.shrink(),
      subHeader: FilterSortActionBar<SetSortOption>(
        searchText: _setQuery,
        onSearchChanged: (v) => setState(() => _setQuery = v),
        onSearchClear: () {
          _setSearchCtrl.clear();
          setState(() => _setQuery = '');
        },
        searchHint: 'Search sets…',
        filters: sportsList,
        activeFilters: _setViewSports,
        onFilterToggle: (sport) => setState(() {
          _setViewSports.contains(sport)
              ? _setViewSports.remove(sport)
              : _setViewSports.add(sport);
        }),
        sortOptions: [
          SortMenuOption(value: SetSortOption.pctDesc, label: 'Most Complete', selected: _setSort == SetSortOption.pctDesc, sfSymbol: 'percent'),
          SortMenuOption(value: SetSortOption.valueDesc, label: 'Value ↓', selected: _setSort == SetSortOption.valueDesc, sfSymbol: 'chart.line.uptrend.xyaxis'),
          SortMenuOption(value: SetSortOption.name, label: 'Name A–Z', selected: _setSort == SetSortOption.name, sfSymbol: 'textformat.abc'),
        ],
        onSortSelected: (s) => setState(() => _setSort = s),
      ),
      label: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '${filtered.length} ${filtered.length == 1 ? 'set' : 'sets'}'
          '${filtered.length != allRows.length ? ' · ${allRows.length} total' : ''}',
          style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.5)),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(userCardsProvider),
        child: filtered.isEmpty
            ? Center(
                child: Text(
                  _setViewSports.isNotEmpty
                      ? 'No sets match your sport filter.'
                      : 'No sets in your collection.',
                  style: TextStyle(color: colors.onSurface.withValues(alpha: 0.5)),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 100),
                itemCount: filtered.length,
                itemBuilder: (_, i) => SetRowTile(row: filtered[i]),
              ),
      ),
    );
  }

}
