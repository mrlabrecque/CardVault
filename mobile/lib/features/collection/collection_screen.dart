import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/cards_service.dart';
import '../../core/services/comps_service.dart';
import '../../core/models/user_card.dart';
import '../../core/theme/app_theme.dart';
import 'widgets/card_stack_tile.dart';
import 'widgets/set_row_tile.dart';

enum SortOption { dateDesc, playerAz, valueDesc, plPct, movingUp }
enum SetSortOption { pctDesc, valueDesc, name }

class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key});

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  SortOption _sort = SortOption.dateDesc;
  SetSortOption _setSort = SetSortOption.pctDesc;
  final Set<String> _activeFilters = {};
  final Set<String> _refreshingStacks = {};
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
          // ── Controls (tabs + search + filters) ───────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(
              children: [
                // Tab toggle
                Container(
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

                // Cards view controls
                if (!_showSets) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                      hintText: 'Search player, set, sport…',
                      hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                      prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF9CA3AF)),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchCtrl.clear(); setState(() => _query = ''); })
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primary.withValues(alpha: 0.4))),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final f in ['RC', 'AUTO', 'PATCH'])
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: FilterChip(
                                      label: Text(f),
                                      selected: _activeFilters.contains(f),
                                      onSelected: (_) => _toggleFilter(f),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        PopupMenuButton<SortOption>(
                          icon: const Icon(Icons.sort),
                          onSelected: (s) => setState(() => _sort = s),
                          itemBuilder: (_) => [
                            PopupMenuItem(value: SortOption.dateDesc,  child: _sortItem(Icons.calendar_today,  'Date Added',   _sort == SortOption.dateDesc,  colors)),
                            PopupMenuItem(value: SortOption.playerAz,  child: _sortItem(Icons.sort_by_alpha,   'Player A–Z',   _sort == SortOption.playerAz,  colors)),
                            PopupMenuItem(value: SortOption.valueDesc, child: _sortItem(Icons.trending_up,     'Value ↓',      _sort == SortOption.valueDesc, colors)),
                            PopupMenuItem(value: SortOption.plPct,     child: _sortItem(Icons.percent,         'P/L %',        _sort == SortOption.plPct,     colors)),
                            PopupMenuItem(value: SortOption.movingUp,  child: _sortItem(Icons.arrow_upward,    'Moving Up',    _sort == SortOption.movingUp,  colors)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                // Sets view sort
                if (_showSets)
                  Align(
                    alignment: Alignment.centerRight,
                    child: PopupMenuButton<SetSortOption>(
                      icon: const Icon(Icons.sort),
                      onSelected: (s) => setState(() => _setSort = s),
                      itemBuilder: (_) => [
                        PopupMenuItem(value: SetSortOption.pctDesc,   child: _sortItem(Icons.percent,      'Most Complete', _setSort == SetSortOption.pctDesc,   colors)),
                        PopupMenuItem(value: SetSortOption.valueDesc, child: _sortItem(Icons.trending_up,  'Value ↓',       _setSort == SetSortOption.valueDesc, colors)),
                        PopupMenuItem(value: SetSortOption.name,      child: _sortItem(Icons.sort_by_alpha,'Name A–Z',      _setSort == SetSortOption.name,      colors)),
                      ],
                    ),
                  ),
              ],
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
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(userCardsProvider),
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                          child: Row(
                            children: [
                              Text(
                                '${allCards.length} ${allCards.length == 1 ? 'card' : 'cards'}'
                                '${filtered.length != stacks.length ? ' · ${filtered.length} shown' : ''}',
                                style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.5)),
                              ),
                              const Spacer(),
                              OutlinedButton.icon(
                                onPressed: () => context.push('/bulk-add'),
                                icon: const Icon(Icons.list, size: 14),
                                label: const Text('Bulk'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                onPressed: () => context.push('/add-card'),
                                icon: const Icon(Icons.add, size: 14),
                                label: const Text('Add Card'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (filtered.isEmpty)
                        SliverFillRemaining(
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
                            itemBuilder: (_, i) => CardStackTile(
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

  Widget _buildSetsView(List<UserCard> cards, ColorScheme colors) {
    final rows = SetRow.fromCards(cards, sortBy: _setSortKey);
    if (rows.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('📦', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          const Text('No sets yet', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Add cards from an imported release to track set completion.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colors.onSurface.withValues(alpha: 0.5))),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(userCardsProvider),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: rows.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('${rows.length} ${rows.length == 1 ? 'set' : 'sets'}',
                  style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.5))),
            );
          }
          return SetRowTile(row: rows[i - 1]);
        },
      ),
    );
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
