import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/cards_service.dart';
import '../../core/models/user_card.dart';
import 'widgets/card_stack_tile.dart';

enum SortOption { dateDesc, playerAz, valueDesc, plPct }

class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key});

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  SortOption _sort = SortOption.dateDesc;
  final Set<String> _activeFilters = {};

  List<CardStack> _filter(List<CardStack> stacks) {
    var result = stacks.where((s) {
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        if (!s.player.toLowerCase().contains(q) &&
            !(s.set?.toLowerCase().contains(q) ?? false) &&
            !s.sport.toLowerCase().contains(q)) { return false; }
      }
      if (_activeFilters.contains('rookie') && !s.rookie) return false;
      if (_activeFilters.contains('autograph') && !s.autograph) return false;
      if (_activeFilters.contains('memorabilia') && !s.memorabilia) return false;
      return true;
    }).toList();

    result.sort((a, b) => switch (_sort) {
      SortOption.playerAz  => a.player.compareTo(b.player),
      SortOption.valueDesc => b.totalValue.compareTo(a.totalValue),
      SortOption.plPct     => b.plPct.compareTo(a.plPct),
      SortOption.dateDesc  => 0,
    });
    return result;
  }

  void _toggleFilter(String f) => setState(() {
    _activeFilters.contains(f) ? _activeFilters.remove(f) : _activeFilters.add(f);
  });

  Future<void> _deleteCard(String cardId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Card'),
        content: const Text('Remove this card from your collection?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(cardsServiceProvider).deleteCard(cardId);
      ref.invalidate(userCardsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final stacksAsync = ref.watch(cardStacksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collection'),
        actions: [
          PopupMenuButton<SortOption>(
            icon: const Icon(Icons.sort),
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (_) => const [
              PopupMenuItem(value: SortOption.dateDesc,  child: Text('Date Added')),
              PopupMenuItem(value: SortOption.playerAz,  child: Text('Player A–Z')),
              PopupMenuItem(value: SortOption.valueDesc, child: Text('Value ↓')),
              PopupMenuItem(value: SortOption.plPct,     child: Text('P/L %')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search player, set, sport…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchCtrl.clear(); setState(() => _query = ''); }) : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                for (final f in ['rookie', 'autograph', 'memorabilia'])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(f[0].toUpperCase() + f.substring(1)),
                      selected: _activeFilters.contains(f),
                      onSelected: (_) => _toggleFilter(f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: stacksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (stacks) {
                final filtered = _filter(stacks);
                if (filtered.isEmpty) {
                  return Center(child: Text(_query.isNotEmpty || _activeFilters.isNotEmpty ? 'No cards match your filters.' : 'No cards yet. Tap + to add one!', style: TextStyle(color: colors.onSurface.withValues(alpha: 0.5))));
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(userCardsProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => CardStackTile(stack: filtered[i], onDelete: _deleteCard),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
