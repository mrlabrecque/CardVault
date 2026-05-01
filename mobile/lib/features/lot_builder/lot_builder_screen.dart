import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/user_card.dart';
import '../../core/services/cards_service.dart';
import '../../core/services/lot_service.dart';
import '../../core/widgets/card_info_section.dart';
import '../../core/widgets/card_thumbnail.dart';
import '../../core/widgets/sticky_sub_header_layout.dart';
import '../../core/widgets/card_fan_loader.dart';
import '../../core/widgets/app_breadcrumb.dart';
import '../../core/theme/app_theme.dart';
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
    var result = all;
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
      _SortOption.valueDesc => (b.currentValue ?? 0).compareTo(a.currentValue ?? 0),
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

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          AppBreadcrumb(
            parent: 'Tools',
            current: 'Lot Builder',
            onBack: () => Navigator.of(context).pop(),
          ),
          _Header(
            showBasket: _showBasket,
            basketCount: lot.items.length,
            onToggle: (v) => setState(() => _showBasket = v),
          ),
          Expanded(
            child: _showBasket
                ? _BasketView(lot: lot, notifier: notifier)
                : _BrowseView(
                    searchCtrl: _searchCtrl,
                    query: _query,
                    sort: _sort,
                    onSortChanged: (s) => setState(() => _sort = s),
                    filters: _filters,
                    lot: lot,
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

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.showBasket, required this.basketCount, required this.onToggle});
  final bool showBasket;
  final int basketCount;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Builder(builder: (context) {
            return Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _TabBtn(label: 'Browse', active: !showBasket, onTap: () => onToggle(false)),
                  _TabBtn(
                    label: 'Basket',
                    active: showBasket,
                    badge: basketCount > 0 ? basketCount : null,
                    onTap: () => onToggle(true),
                  ),
                ],
              ),
            );
          }),
    );
  }
}

class _TabBtn extends StatelessWidget {
  const _TabBtn({required this.label, required this.active, required this.onTap, this.badge});
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: active ? colors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: active
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 1))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? colors.onSurface : colors.onSurface.withValues(alpha: 0.45),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text('$badge', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Browse view ───────────────────────────────────────────────────────────────

class _BrowseView extends ConsumerWidget {
  const _BrowseView({
    required this.searchCtrl,
    required this.query,
    required this.sort,
    required this.onSortChanged,
    required this.filters,
    required this.lot,
    required this.notifier,
    required this.onQueryChanged,
    required this.onFilterToggle,
    required this.filteredCards,
  });

  final TextEditingController searchCtrl;
  final String query;
  final _SortOption sort;
  final ValueChanged<_SortOption> onSortChanged;
  final Set<String> filters;
  final LotState lot;
  final LotNotifier notifier;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onFilterToggle;
  final List<UserCard> Function(List<UserCard>) filteredCards;

  Widget _sortItem(IconData icon, String label, bool active, ColorScheme colors) {
    return Row(children: [
      Icon(icon, size: 16, color: active ? colors.primary : null),
      const SizedBox(width: 8),
      Text(label),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(userCardsProvider);
    final colors = Theme.of(context).colorScheme;

    return cardsAsync.when(
      loading: () => const Center(child: CardFanLoader()),
      error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Color(0xFFDC2626)))),
      data: (allCards) {
        final cards = filteredCards(allCards);
        return StickySubHeaderLayout(
          header: const SizedBox.shrink(),
          subHeader: FilterSortActionBar<_SortOption>(
            searchText: query,
            onSearchChanged: onQueryChanged,
            onSearchClear: () {
              searchCtrl.clear();
              onQueryChanged('');
            },
            searchHint: 'Search player, set, sport…',
            filters: const ['RC', 'AUTO', 'PATCH'],
            activeFilters: filters,
            onFilterToggle: onFilterToggle,
            sortMenuBuilder: (_) => [
              PopupMenuItem(value: _SortOption.dateDesc,  child: _sortItem(Icons.calendar_today,  'Date Added', sort == _SortOption.dateDesc, colors)),
              PopupMenuItem(value: _SortOption.playerAz,  child: _sortItem(Icons.sort_by_alpha,  'Player A–Z', sort == _SortOption.playerAz, colors)),
              PopupMenuItem(value: _SortOption.valueDesc, child: _sortItem(Icons.trending_up,    'Value ↓',   sort == _SortOption.valueDesc, colors)),
            ],
            onSortSelected: onSortChanged,
            actionButton: const SizedBox.shrink(),
          ),
          label: Align(
            alignment: Alignment.centerLeft,
            child: Text('${cards.length} cards', style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
          ),
          body: allCards.isEmpty
              ? const Center(child: Text('No cards in your collection yet.', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)))
              : cards.isEmpty
                  ? const Center(child: Text('No cards match your search.', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: inLot ? const Color(0xFFF0FDF4) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: inLot ? const Color(0xFF86EFAC) : const Color(0xFFF3F4F6)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(0),
          child:IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardThumbnail(imageUrl: card.imageUrl, sport: card.sport, width: 70),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 6, 12),                
                        child: CardInfoSection(
                  player: card.player,
                  cardNumber: card.cardNumber,
                  year: card.year,
                  set: card.set,
                  parallel: card.parallel,
                  serialMax: card.serialMax,
                  sport: card.sport,
                  rookie: card.rookie,
                  autograph: card.autograph,
                  memorabilia: card.memorabilia,
                  ssp: card.ssp,
                  isGraded: card.isGraded && card.grade != null,
                  gradeLabel: card.grade != null ? '${card.grader ?? ''} ${card.grade!}'.trim() : null,
                ),
              ),
              ),
                  Padding(padding: EdgeInsets.all(12),
                    child:
                    Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$${(card.currentValue ?? 0).toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                  ),
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
      return Center(
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
            const SizedBox(height: 4),
            const Text('Switch to Browse and tap cards to add them.', style: TextStyle(fontSize: 12, color: Color(0xFFD1D5DB))),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
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
              const SizedBox(height: 4),
              Text(
                '\$${lot.askingPrice.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 2),
              Text(
                '${lot.pct}% of \$${lot.totalValue.toStringAsFixed(2)}',
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
            const SizedBox(height: 4),
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
        const Divider(color: Color(0xFFF3F4F6), height: 1),
        const SizedBox(height: 16),
        // Summary header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${lot.items.length} ${lot.items.length == 1 ? 'card' : 'cards'}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Market total: \$${lot.totalValue.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                  ),
                ],
              ),
              const Spacer(),
              GestureDetector(
                onTap: notifier.clear,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Clear', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Card rows
        ...lot.items.map((card) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _BasketCardRow(card: card, onRemove: () => notifier.remove(card.id)),
        )),
      ],
    );
  }
}

class _BasketCardRow extends StatelessWidget {
  const _BasketCardRow({required this.card, required this.onRemove});
  final UserCard card;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF3F4F6)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(0),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardThumbnail(imageUrl: card.imageUrl, sport: card.sport, width: 70),
             Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 6, 12),                
                        child: CardInfoSection(
                player: card.player,
                cardNumber: card.cardNumber,
                year: card.year,
                set: card.set,
                parallel: card.parallel,
                serialMax: card.serialMax,
                sport: card.sport,
                rookie: card.rookie,
                autograph: card.autograph,
                memorabilia: card.memorabilia,
                ssp: card.ssp,
                isGraded: card.isGraded && card.grade != null,
                gradeLabel: card.grade != null ? '${card.grader ?? ''} ${card.grade!}'.trim() : null,
              ),
                      ),

            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${(card.currentValue ?? 0).toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFFECACA)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.close, size: 14, color: Color(0xFFF87171)),
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

