import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/cards_service.dart';
import '../../core/services/comps_service.dart';
import '../../core/models/user_card.dart';
import '../../core/widgets/sticky_sub_header_layout.dart';
import 'widgets/card_stack_tile.dart';
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Card'),
        content: const Text('Remove this card from your collection?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
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
    final messenger = ScaffoldMessenger.of(context);
    final comps = ref.read(compsServiceProvider);
    try {
      await Future.wait(stack.cards.map((c) => comps.refreshCardValue(c.id)));
      ref.invalidate(userCardsProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Market value updated'), duration: Duration(seconds: 2)),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Refresh failed: $e'), duration: const Duration(seconds: 3)),
      );
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
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          // ── Tab toggle ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                _tab('Cards', !_showSets, colors, () => setState(() => _showSets = false)),
                _tab('Sets',   _showSets, colors, () => setState(() => _showSets = true)),
              ]),
            ),
          ),

          // ── Content ───────────────────────────────────────
          Expanded(
            child: cardsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
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
                    sortMenuBuilder: (_) => [
                      PopupMenuItem(value: SortOption.dateDesc,  child: _sortItem(Icons.calendar_today,  'Date Added',   _sort == SortOption.dateDesc,  colors)),
                      PopupMenuItem(value: SortOption.playerAz,  child: _sortItem(Icons.sort_by_alpha,   'Player A–Z',   _sort == SortOption.playerAz,  colors)),
                      PopupMenuItem(value: SortOption.valueDesc, child: _sortItem(Icons.trending_up,     'Value ↓',      _sort == SortOption.valueDesc, colors)),
                      PopupMenuItem(value: SortOption.plPct,     child: _sortItem(Icons.percent,         'P/L %',        _sort == SortOption.plPct,     colors)),
                      PopupMenuItem(value: SortOption.movingUp,  child: _sortItem(Icons.arrow_upward,    'Moving Up',    _sort == SortOption.movingUp,  colors)),
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
                            itemBuilder: (_, i) => CardStackTile(
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
        backgroundColor: const Color(0xFFF9FAFB),
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
        sortMenuBuilder: (_) => [
          PopupMenuItem(value: SetSortOption.pctDesc, child: _setSortItem(Icons.percent, 'Most Complete', _setSort == SetSortOption.pctDesc, colors)),
          PopupMenuItem(value: SetSortOption.valueDesc, child: _setSortItem(Icons.trending_up, 'Value ↓', _setSort == SetSortOption.valueDesc, colors)),
          PopupMenuItem(value: SetSortOption.name, child: _setSortItem(Icons.sort_by_alpha, 'Name A–Z', _setSort == SetSortOption.name, colors)),
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

  Widget _setSortItem(IconData icon, String label, bool active, ColorScheme colors) {
    return Row(children: [
      Icon(icon, size: 16, color: active ? colors.primary : null),
      const SizedBox(width: 8),
      Text(label),
    ]);
  }

  Widget _tab(String label, bool active, ColorScheme colors, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: active ? colors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: active ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 1))] : null,
          ),
          child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: active ? colors.onSurface : colors.onSurface.withValues(alpha: 0.45)),
          ),
        ),
      ),
    );
  }

  Widget _sortItem(IconData icon, String label, bool active, ColorScheme colors) {
    return Row(children: [
      Icon(icon, size: 16, color: active ? colors.primary : null),
      const SizedBox(width: 8),
      Text(label),
    ]);
  }
}
