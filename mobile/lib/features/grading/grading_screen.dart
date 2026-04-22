import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/user_card.dart';
import '../../core/services/cards_service.dart';
import '../../core/services/grading_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/attr_tag.dart';

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
  final Set<String> _activeFilters = {};
  String _sortBy = 'value-desc';
  _Tier? _tierFilter; // null = all

  final Map<String, _CardState> _cardStates = {};
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<UserCard> _applyFiltersAndSort(List<UserCard> raw) {
    final q = _search.toLowerCase();

    var cards = raw.where((c) {
      if (!c.isGraded == false) return false; // only ungraded
      if (q.isNotEmpty &&
          !c.player.toLowerCase().contains(q) &&
          !(c.set ?? '').toLowerCase().contains(q) &&
          !c.sport.toLowerCase().contains(q)) {
        return false;
      }
      if (_activeFilters.contains('rookie') && !c.rookie) return false;
      if (_activeFilters.contains('autograph') && !c.autograph) return false;
      if (_activeFilters.contains('memorabilia') && !c.memorabilia) return false;
      if (_tierFilter != null) {
        final state = _cardStates[c.id] ?? const _CardState();
        if (_tier(c, state, _gradingFee) != _tierFilter) return false;
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

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: cardsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (allCards) {
          final ungradedCards = allCards.where((c) => !c.isGraded).toList();
          final display = _applyFiltersAndSort(ungradedCards);
          final analyzedCount = _cardStates.values.where((s) => s.result != null).length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              _buildFeeCard(),
              const SizedBox(height: 12),
              _buildSearch(),
              const SizedBox(height: 10),
              _buildAttributeFilters(),
              const SizedBox(height: 10),
              _buildSortRow(),
              const SizedBox(height: 10),
              _buildTierFilterRow(),
              if (ungradedCards.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    '${display.length} card${display.length == 1 ? '' : 's'} · $analyzedCount analyzed',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (ungradedCards.isEmpty)
                _buildEmpty()
              else
                ...display.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _CardRow(
                    card: c,
                    state: _cardStates[c.id] ?? const _CardState(),
                    gradingFee: _gradingFee,
                    onAnalyze: () => _analyze(c.id),
                  ),
                )),
            ],
          );
        },
      ),
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

  Widget _buildSearch() {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() => _search = v),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: 'Search player, set, sport…',
        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
        prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF9CA3AF)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
      ),
    );
  }

  Widget _buildAttributeFilters() {
    final filters = [
      ('rookie', 'RC'),
      ('autograph', 'AUTO'),
      ('memorabilia', 'PATCH'),
    ];
    return Row(
      children: filters.map((f) {
        final active = _activeFilters.contains(f.$1);
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => setState(() => active ? _activeFilters.remove(f.$1) : _activeFilters.add(f.$1)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: active ? AppTheme.primary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: active ? AppTheme.primary : const Color(0xFFE5E7EB)),
              ),
              child: Text(f.$2, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: active ? Colors.white : const Color(0xFF6B7280))),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSortRow() {
    final opts = [('value-desc', 'Value'), ('player', 'Player A–Z'), ('profit-desc', 'PSA 9 Profit')];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          const Text('SORT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFD1D5DB), letterSpacing: 1)),
          const SizedBox(width: 8),
          ...opts.map((o) {
            final active = _sortBy == o.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() => _sortBy = o.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: active ? AppTheme.primary : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: active ? AppTheme.primary : const Color(0xFFE5E7EB)),
                  ),
                  child: Text(o.$2, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: active ? Colors.white : const Color(0xFF6B7280))),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTierFilterRow() {
    final opts = <(_Tier?, String)>[
      (null, 'All'),
      (_Tier.grade, 'Grade It'),
      (_Tier.borderline, 'Borderline'),
      (_Tier.skip, 'Skip It'),
      (_Tier.pending, 'Not Analyzed'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          const Text('SHOW', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFD1D5DB), letterSpacing: 1)),
          const SizedBox(width: 8),
          ...opts.map((o) {
            final active = _tierFilter == o.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() => _tierFilter = o.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: active ? AppTheme.primary : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: active ? AppTheme.primary : const Color(0xFFE5E7EB)),
                  ),
                  child: Text(o.$2, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: active ? Colors.white : const Color(0xFF6B7280))),
                ),
              ),
            );
          }),
        ],
      ),
    );
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

  String get _sportEmoji => switch (card.sport.toLowerCase()) {
    'basketball' => '🏀',
    'baseball'   => '⚾',
    'football'   => '🏈',
    'hockey'     => '🏒',
    'soccer'     => '⚽',
    _            => '🃏',
  };

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
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildImage(),
            const SizedBox(width: 12),
            Expanded(child: _buildInfo(tier)),
            const SizedBox(width: 8),
            _buildRightSide(tier),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (card.imageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: card.imageUrl!,
          width: 44,
          height: 60,
          fit: BoxFit.cover,
          placeholder: (_, _) => _imagePlaceholder(),
          errorWidget: (_, _, _) => _imagePlaceholder(),
        ),
      );
    }
    return _imagePlaceholder();
  }

  Widget _imagePlaceholder() => Container(
    width: 44,
    height: 60,
    decoration: BoxDecoration(
      color: Colors.grey.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Center(child: Text(_sportEmoji, style: const TextStyle(fontSize: 20))),
  );

  Widget _buildInfo(_Tier tier) {
    final setLine = [
      if (card.year != null) '${card.year}',
      if (card.set != null) card.set!,
      if (card.checklist != null) card.checklist!,
    ].join(' · ');

    final hasAttrs = card.rookie || card.autograph || card.memorabilia;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Player + card number + tier badge
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: card.player,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  if (card.cardNumber != null)
                    TextSpan(
                      text: '  #${card.cardNumber}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: Color(0xFF9CA3AF)),
                    ),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (tier != _Tier.pending) ...[
              const SizedBox(width: 6),
              _TierBadge(tier: tier),
            ],
          ],
        ),
        if (setLine.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(setLine, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
        if (card.parallel != 'Base') ...[
          const SizedBox(height: 1),
          Text(card.parallel, style: TextStyle(fontSize: 12, color: AppTheme.primary)),
        ],
        const SizedBox(height: 4),
        if (hasAttrs)
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              if (card.rookie)      AttrTag('RC',    color: const Color(0xFF16A34A)),
              if (card.autograph)   AttrTag('AUTO',  color: const Color(0xFF7C3AED)),
              if (card.memorabilia) AttrTag('PATCH', color: const Color(0xFF0369A1)),
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
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_opacity),
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

