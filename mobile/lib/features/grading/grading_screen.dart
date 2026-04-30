import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/user_card.dart';
import '../../core/services/cards_service.dart';
import '../../core/services/grading_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/card_info_section.dart';
import '../../core/widgets/card_thumbnail.dart';
import '../../core/widgets/sticky_sub_header_layout.dart';
import '../../core/widgets/card_fan_loader.dart';
import '../collection/widgets/filter_sort_action_bar.dart';

// ── Per-card result state ────────────────────────────────────────────────────

class _CardState {
  const _CardState({this.result, this.loading = false, this.error = false});
  final GradingResult? result;
  final bool loading;
  final bool error;

  _CardState copyWith({GradingResult? result, bool? loading, bool? error}) =>
      _CardState(
        result:  result  ?? this.result,
        loading: loading ?? this.loading,
        error:   error   ?? this.error,
      );
}

// ── Tier classification ──────────────────────────────────────────────────────

enum _Tier { grade, borderline, skip, pending }

_Tier _tier(UserCard card, _CardState state, double gradingFee) {
  if (state.loading || state.result == null) return _Tier.pending;
  final r = state.result!;
  final double profit;
  if (r.psa9Count > 0) {
    profit = r.psa9Avg - gradingFee - (card.pricePaid ?? 0);
  } else if (r.psa10Count > 0) {
    profit = r.psa10Avg - gradingFee - (card.pricePaid ?? 0);
  } else {
    return _Tier.skip;
  }
  if (profit > 25) return _Tier.grade;
  if (profit >= 0) return _Tier.borderline;
  return _Tier.skip;
}

double _psa9Profit(UserCard card, GradingResult r, double gradingFee) =>
    r.psa9Avg - gradingFee - (card.pricePaid ?? 0);

double _psa10Profit(UserCard card, GradingResult r, double gradingFee) =>
    r.psa10Avg - gradingFee - (card.pricePaid ?? 0);

// ── Screen ───────────────────────────────────────────────────────────────────

class GradingScreen extends ConsumerStatefulWidget {
  const GradingScreen({super.key});

  @override
  ConsumerState<GradingScreen> createState() => _GradingScreenState();
}

class _GradingScreenState extends ConsumerState<GradingScreen> {
  double _gradingFee = 40;
  String _search = '';
  String _tierFilterKey = 'all'; // 'all', 'grade', 'borderline', 'skip', 'pending'
  String _sortBy = 'value-desc';

  final Map<String, _CardState> _cardStates = {};
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  _Tier? _tierFromKey(String key) => switch (key) {
    'grade'      => _Tier.grade,
    'borderline' => _Tier.borderline,
    'skip'       => _Tier.skip,
    'pending'    => _Tier.pending,
    _            => null, // 'all'
  };

  String _tierFilterLabel(String key) => switch (key) {
    'grade'      => 'GRADE IT',
    'borderline' => 'BORDERLINE',
    'skip'       => 'SKIP IT',
    'pending'    => 'NOT ANALYZED',
    _            => 'ALL',
  };

  String _tierKeyFromLabel(String label) => switch (label) {
    'GRADE IT'      => 'grade',
    'BORDERLINE'    => 'borderline',
    'SKIP IT'       => 'skip',
    'NOT ANALYZED'  => 'pending',
    _               => 'all',
  };

  void _setTierFilter(String key) => setState(() => _tierFilterKey = key);

  List<UserCard> _applyFiltersAndSort(List<UserCard> raw) {
    final q = _search.toLowerCase();
    final tierFilter = _tierFromKey(_tierFilterKey);

    var cards = raw.where((c) {
      if (!c.isGraded == false) return false; // only ungraded
      if (q.isNotEmpty &&
          !c.player.toLowerCase().contains(q) &&
          !(c.set ?? '').toLowerCase().contains(q) &&
          !c.sport.toLowerCase().contains(q)) {
        return false;
      }
      if (tierFilter != null) {
        final state = _cardStates[c.id] ?? const _CardState();
        if (_tier(c, state, _gradingFee) != tierFilter) return false;
      }
      return true;
    }).toList();

    cards.sort((a, b) {
      switch (_sortBy) {
        case 'player':
          return a.player.compareTo(b.player);
        case 'profit-desc':
          final sa = _cardStates[a.id];
          final sb = _cardStates[b.id];
          final pa = sa?.result != null ? _psa9Profit(a, sa!.result!, _gradingFee) : double.negativeInfinity;
          final pb = sb?.result != null ? _psa9Profit(b, sb!.result!, _gradingFee) : double.negativeInfinity;
          return pb.compareTo(pa);
        default: // value-desc
          return (b.currentValue ?? 0).compareTo(a.currentValue ?? 0);
      }
    });

    return cards;
  }

  Future<void> _analyze(String cardId) async {
    setState(() => _cardStates[cardId] = const _CardState(loading: true));
    try {
      final result = await ref.read(gradingServiceProvider).analyzeCard(cardId);
      setState(() => _cardStates[cardId] = _CardState(result: result));
    } catch (_) {
      setState(() => _cardStates[cardId] = const _CardState(error: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardsAsync = ref.watch(userCardsProvider);

    return cardsAsync.when(
      loading: () => const Center(child: CardFanLoader()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (allCards) {
        final ungradedCards = allCards.where((c) => !c.isGraded).toList();
        final display = _applyFiltersAndSort(ungradedCards);
        final analyzedCount = _cardStates.values.where((s) => s.result != null).length;

        return StickySubHeaderLayout(
          header: Column(
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Text('Tools', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF9CA3AF))),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.chevron_right, size: 14, color: Color(0xFFD1D5DB)),
                  ),
                  const Text('Grading', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                ],
              ),
              const SizedBox(height: 12),
              _buildFeeCard(),
              const SizedBox(height: 12),
            ],
          ),
          subHeader: FilterSortActionBar<String>(
            searchText: _search,
            onSearchChanged: (v) => setState(() => _search = v),
            onSearchClear: () {
              _searchController.clear();
              setState(() => _search = '');
            },
            searchHint: 'Search player, set, sport…',
            filters: const ['ALL', 'GRADE IT', 'BORDERLINE', 'SKIP IT', 'NOT ANALYZED'],
            activeFilters: {_tierFilterLabel(_tierFilterKey)},
            onFilterToggle: (f) => _setTierFilter(_tierKeyFromLabel(f)),
            sortMenuBuilder: (_) => [
              PopupMenuItem(value: 'value-desc',   child: _sortItem(Icons.trending_up,   'Value ↓',      _sortBy == 'value-desc')),
              PopupMenuItem(value: 'player',        child: _sortItem(Icons.sort_by_alpha, 'Player A–Z',   _sortBy == 'player')),
              PopupMenuItem(value: 'profit-desc',   child: _sortItem(Icons.percent,       'PSA 9 Profit', _sortBy == 'profit-desc')),
            ],
            onSortSelected: (s) => setState(() => _sortBy = s),
            actionButton: const SizedBox.shrink(),
          ),
          label: ungradedCards.isNotEmpty
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${display.length} card${display.length == 1 ? '' : 's'} · $analyzedCount analyzed',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                  ),
                )
              : null,
          body: ungradedCards.isEmpty
              ? _buildEmpty()
              : display.isEmpty
                  ? const Center(
                      child: Text('No cards match your filters.',
                          style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                      itemCount: display.length,
                      itemBuilder: (_, i) {
                        final c = display[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _CardRow(
                            card: c,
                            state: _cardStates[c.id] ?? const _CardState(),
                            gradingFee: _gradingFee,
                            onAnalyze: () => _analyze(c.id),
                          ),
                        );
                      },
                    ),
        );
      },
    );
  }

  Widget _buildFeeCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF3F4F6)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Grading Fee', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1F2937))),
                SizedBox(height: 2),
                Text('Deducted from profit calculation', style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
              ],
            ),
          ),
          Row(
            children: [
              const Text('\$', style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
              SizedBox(
                width: 56,
                child: TextFormField(
                  initialValue: _gradingFee.toStringAsFixed(0),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppTheme.primary, width: 1.5),
                    ),
                  ),
                  onChanged: (v) {
                    final parsed = double.tryParse(v);
                    if (parsed != null) setState(() => _gradingFee = parsed);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  Widget _sortItem(IconData icon, String label, bool active) {
    return Row(children: [
      Icon(icon, size: 16, color: active ? AppTheme.primary : null),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
    ]);
  }


  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: const [
          Icon(Icons.grade_outlined, size: 40, color: Color(0xFFE5E7EB)),
          SizedBox(height: 12),
          Text('No raw cards in your collection.', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
        ],
      ),
    );
  }
}

// ── Card row ─────────────────────────────────────────────────────────────────

class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.card,
    required this.state,
    required this.gradingFee,
    required this.onAnalyze,
  });

  final UserCard card;
  final _CardState state;
  final double gradingFee;
  final VoidCallback onAnalyze;

  @override
  Widget build(BuildContext context) {
    final tier = _tier(card, state, gradingFee);

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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardThumbnail(imageUrl: card.imageUrl, sport: card.sport, width: 60),
            Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 6, 12), child: _buildInfo(tier))),
            Padding(padding: const EdgeInsets.all(12), child: _buildRightSide(tier)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfo(_Tier tier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Player + card number + tier badge
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardInfoSection(
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
              isGraded: false,
            ),
            if (tier != _Tier.pending) ...[
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child:
              _TierBadge(tier: tier),
              )
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '\$${(card.pricePaid ?? 0).toStringAsFixed(2)} paid · \$${(card.currentValue ?? 0).toStringAsFixed(2)} raw',
          style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
        ),
      ],
    );
  }

  Widget _buildRightSide(_Tier tier) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (state.loading) ...[
          const _ShimmerBox(width: 88, height: 30),
          const SizedBox(height: 4),
          const _ShimmerBox(width: 88, height: 30),
        ] else if (state.error)
          GestureDetector(
            onTap: onAnalyze,
            child: const Text('Retry', style: TextStyle(fontSize: 11, color: Color(0xFFEF4444), decoration: TextDecoration.underline)),
          )
        else if (state.result != null)
          ..._buildResultBoxes(state.result!)
        else
          GestureDetector(
            onTap: onAnalyze,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.primary),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Analyze', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary)),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildResultBoxes(GradingResult result) {
    final p10 = _psa10Profit(card, result, gradingFee);
    final p9  = _psa9Profit(card, result, gradingFee);

    return [
      _GradeBox(
        label: 'PSA 10',
        avg: result.psa10Count > 0 ? result.psa10Avg : null,
        profit: result.psa10Count > 0 ? p10 : null,
      ),
      const SizedBox(height: 4),
      _GradeBox(
        label: 'PSA 9',
        avg: result.psa9Count > 0 ? result.psa9Avg : null,
        profit: result.psa9Count > 0 ? p9 : null,
      ),
    ];
  }

}

// ── Helpers ──────────────────────────────────────────────────────────────────

class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox({required this.width, required this.height});
  final double width;
  final double height;

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.2, end: 1.0).animate(_opacity),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: const Color(0xFFE5E7EB),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class _TierBadge extends StatelessWidget {
  const _TierBadge({required this.tier});
  final _Tier tier;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (tier) {
      _Tier.grade      => (const Color(0xFFD1FAE5), const Color(0xFF065F46), 'Grade It'),
      _Tier.borderline => (const Color(0xFFFEF3C7), const Color(0xFF92400E), 'Borderline'),
      _Tier.skip       => (const Color(0xFFFEE2E2), const Color(0xFFB91C1C), 'Skip It'),
      _Tier.pending    => (Colors.transparent, Colors.transparent, ''),
    };
    if (tier == _Tier.pending) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: fg, letterSpacing: 0.4)),
    );
  }
}

class _GradeBox extends StatelessWidget {
  const _GradeBox({required this.label, required this.avg, required this.profit});
  final String label;
  final double? avg;
  final double? profit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFF9CA3AF), letterSpacing: 0.6)),
          const SizedBox(height: 2),
          if (avg == null)
            const Text('No data', style: TextStyle(fontSize: 9, color: Color(0xFFD1D5DB)))
          else ...[
            Text('\$${avg!.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF111827)), overflow: TextOverflow.ellipsis),
            Text(_formatProfit(profit!), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: _profitColor(profit!)), overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }

  String _formatProfit(double v) {
    final abs = v.abs();
    return '${v >= 0 ? '+' : '-'}\$${abs.toStringAsFixed(2)}';
  }

  Color _profitColor(double v) {
    if (v > 25) return const Color(0xFF059669);
    if (v >= 0) return const Color(0xFFD97706);
    return const Color(0xFFEF4444);
  }
}

