import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/user_card.dart';
import '../../core/services/cards_service.dart';
import '../../core/theme/chrome_metrics.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/fonts.dart';
import '../../core/widgets/card_info_section.dart';
import '../../core/utils/currency_format.dart';
import '../../core/utils/guide_grade_prices.dart';
import '../../core/utils/usd_field.dart';
import '../../core/widgets/card_thumbnail.dart';
import '../../core/widgets/adaptive_list_card.dart';
import '../../core/widgets/card_fan_loader.dart';
import '../../core/widgets/app_bar_action_capsule.dart';
import '../../core/widgets/app_bar_shell_trailing_actions.dart';
import '../../core/widgets/frosted_chrome_layer.dart';
import '../../core/widgets/glass_nav_bar.dart';
import '../../core/widgets/sliver_frosted_header.dart';
import '../collection/widgets/filter_sort_action_bar.dart';

// ── Tier classification ──────────────────────────────────────────────────────

enum _Tier { grade, borderline, skip, unavailable }

_Tier _tierForCard(UserCard card, double gradingFee) {
  final snapshot = gradingGuideSnapshotFromGradeMap(card.embeddedGuideGradePrices);
  if (snapshot == null) return _Tier.unavailable;
  return switch (gradingRecommendationTierFromSnapshot(
    snapshot: snapshot,
    gradingFee: gradingFee,
    pricePaid: card.pricePaid,
  )) {
    GradingRecommendationTier.grade => _Tier.grade,
    GradingRecommendationTier.borderline => _Tier.borderline,
    GradingRecommendationTier.skip => _Tier.skip,
  };
}

// ── Screen ───────────────────────────────────────────────────────────────────

class GradingScreen extends ConsumerStatefulWidget {
  const GradingScreen({super.key});

  @override
  ConsumerState<GradingScreen> createState() => _GradingScreenState();
}

class _GradingScreenState extends ConsumerState<GradingScreen> {
  double _gradingFee = 40;
  String _search = '';
  String _tierFilterKey = 'all';
  String _sortBy = 'value-desc';

  final _searchController = TextEditingController();
  final _gradingFeeUsdFmt = createUsdCurrencyInputFormatter();
  late final TextEditingController _gradingFeeCtrl;

  @override
  void initState() {
    super.initState();
    _gradingFeeCtrl = TextEditingController(text: _gradingFeeUsdFmt.formatDouble(_gradingFee));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(userCardsProvider);
    });
  }

  @override
  void dispose() {
    _gradingFeeCtrl.dispose();
    _searchController.dispose();
    super.dispose();
  }

  _Tier? _tierFromKey(String key) => switch (key) {
    'grade' => _Tier.grade,
    'borderline' => _Tier.borderline,
    'skip' => _Tier.skip,
    'unavailable' => _Tier.unavailable,
    _ => null,
  };

  List<UserCard> _applyFiltersAndSort(List<UserCard> raw) {
    final q = _search.toLowerCase();
    final tierFilter = _tierFromKey(_tierFilterKey);

    var cards = raw.where((c) {
      if (c.isGraded) return false;
      if (q.isNotEmpty &&
          !c.player.toLowerCase().contains(q) &&
          !(c.set ?? '').toLowerCase().contains(q) &&
          !c.sport.toLowerCase().contains(q)) {
        return false;
      }
      if (tierFilter != null && _tierForCard(c, _gradingFee) != tierFilter) return false;
      return true;
    }).toList();

    cards.sort((a, b) {
      switch (_sortBy) {
        case 'player':
          return a.player.compareTo(b.player);
        case 'profit-desc':
          final sa = gradingGuideSnapshotFromGradeMap(a.embeddedGuideGradePrices);
          final sb = gradingGuideSnapshotFromGradeMap(b.embeddedGuideGradePrices);
          final pa = sa?.primaryGuidePrice != null
              ? gradingProfitAfterFee(
                  guidePrice: sa!.primaryGuidePrice!,
                  gradingFee: _gradingFee,
                  pricePaid: a.pricePaid,
                )
              : double.negativeInfinity;
          final pb = sb?.primaryGuidePrice != null
              ? gradingProfitAfterFee(
                  guidePrice: sb!.primaryGuidePrice!,
                  gradingFee: _gradingFee,
                  pricePaid: b.pricePaid,
                )
              : double.negativeInfinity;
          return pb.compareTo(pa);
        default:
          return (b.displayValue ?? 0).compareTo(a.displayValue ?? 0);
      }
    });

    return cards;
  }

  @override
  Widget build(BuildContext context) {
    final cardsAsync = ref.watch(userCardsProvider);
    final colors = Theme.of(context).colorScheme;
    final hasActiveFilter = _tierFilterKey != 'all';
    final hasActiveSort = _sortBy != 'value-desc';
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: buildGlassNavBar(
        context,
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: Text(
          'Grading',
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
                items: const [
                  AdaptivePopupMenuItem(label: 'All', icon: 'circle', value: 'all'),
                  AdaptivePopupMenuItem(label: 'Grade It', icon: 'checkmark.seal', value: 'grade'),
                  AdaptivePopupMenuItem(label: 'Borderline', icon: 'questionmark.circle', value: 'borderline'),
                  AdaptivePopupMenuItem(label: 'Skip It', icon: 'xmark.circle', value: 'skip'),
                  AdaptivePopupMenuItem(label: 'No analysis', icon: 'minus.circle', value: 'unavailable'),
                ],
                onSelected: (_, entry) => setState(() => _tierFilterKey = entry.value ?? 'all'),
              ),
              AdaptivePopupMenuButton.icon<String>(
                icon: hasActiveSort ? 'arrow.up.arrow.down.circle.fill' : 'arrow.up.arrow.down.circle',
                tint: hasActiveSort ? colors.primary : colors.onSurface,
                buttonStyle: PopupButtonStyle.plain,
                items: [
                  AdaptivePopupMenuItem(
                    value: 'value-desc',
                    label: _sortBy == 'value-desc' ? '✓ Value ↓' : 'Value ↓',
                    icon: 'chart.line.uptrend.xyaxis',
                  ),
                  AdaptivePopupMenuItem(
                    value: 'player',
                    label: _sortBy == 'player' ? '✓ Player A-Z' : 'Player A-Z',
                    icon: 'textformat.abc',
                  ),
                  AdaptivePopupMenuItem(
                    value: 'profit-desc',
                    label: _sortBy == 'profit-desc' ? '✓ PSA 9 Profit' : 'PSA 9 Profit',
                    icon: 'percent',
                  ),
                ],
                onSelected: (_, entry) {
                  final next = entry.value;
                  if (next == null) return;
                  setState(() => _sortBy = next);
                },
              ),
            ],
          ),
          const SizedBox(width: 6),
          ...appBarShellTrailingActions(context),
        ],
      ),
      body: cardsAsync.when(
        loading: () => const Center(child: CardFanLoader()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (allCards) {
          final ungradedCards = allCards.where((c) => !c.isGraded).toList();
          final display = _applyFiltersAndSort(ungradedCards);
          final analyzedCount = ungradedCards
              .where((c) => gradingGuideSnapshotFromGradeMap(c.embeddedGuideGradePrices) != null)
              .length;
          final navOffset = MediaQuery.of(context).padding.top + kToolbarHeight;

          return CustomScrollView(
            slivers: [
              SliverFrostedHeader(
                height: navOffset + ChromeMetrics.gradingHeaderExtent,
                child: FrostedChromeLayer(
                  child: Padding(
                    padding: ChromeMetrics.gradingHeaderPadding(navOffset),
                    child: Column(
                      children: [
                        _buildFeeCard(),
                        const SizedBox(height: ChromeMetrics.segmentToSearchGap),
                        FilterSortActionBar<String>(
                          searchController: _searchController,
                          searchText: _search,
                          onSearchChanged: (v) => setState(() => _search = v),
                          onSearchClear: () {
                            _searchController.clear();
                            setState(() => _search = '');
                          },
                          searchHint: 'Search player, set, sport…',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SliverChromeGap(height: ChromeMetrics.contentTopGapTight),
              if (ungradedCards.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: ChromeMetrics.listCountPadding(),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${display.length} card${display.length == 1 ? '' : 's'} • $analyzedCount analyzed',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                      ),
                    ),
                  ),
                ),
              if (ungradedCards.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: _buildEmpty())
              else if (display.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'No cards match your filters.',
                      style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    ChromeMetrics.listTopInsetAfterCountRoomy,
                    16,
                    40,
                  ),
                  sliver: SliverList.builder(
                    itemCount: display.length,
                    itemBuilder: (_, i) {
                      final c = display[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _CardRow(
                          card: c,
                          gradingFee: _gradingFee,
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFeeCard() {
    return AdaptiveListCard(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Grading Fee',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1F2937)),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Deducted from profit calculation',
                    style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 112,
              child: TextFormField(
                controller: _gradingFeeCtrl,
                inputFormatters: [_gradingFeeUsdFmt],
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
                  final parsed = parseUsdInput(v);
                  if (parsed != null) setState(() => _gradingFee = parsed);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(Icons.grade_outlined, size: 40, color: Color(0xFFE5E7EB)),
          SizedBox(height: 12),
          Text('No raw cards in your collection.', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
        ],
      ),
    );
  }
}

// ── Card row ─────────────────────────────────────────────────────────────────

/// Caps grade column width on large phones; content-sized below that.
double _gradeColumnMaxWidth(BuildContext context) {
  final screenW = MediaQuery.sizeOf(context).width;
  return (screenW * 0.28).clamp(60.0, 96.0);
}

class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.card,
    required this.gradingFee,
  });

  final UserCard card;
  final double gradingFee;

  @override
  Widget build(BuildContext context) {
    final snapshot = gradingGuideSnapshotFromGradeMap(card.embeddedGuideGradePrices);
    final tier = _tierForCard(card, gradingFee);

    return AdaptiveListCard(
      margin: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardThumbnail(imageUrl: card.imageUrl, sport: card.sport),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 12),
                child: _buildInfo(tier),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 10, 12),
              child: _buildRightSide(context, snapshot),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfo(_Tier tier) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: CardInfoSection.fromUserCard(card, isGraded: false),
        ),
        if (tier != _Tier.unavailable) ...[
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _TierBadge(tier: tier),
          ),
        ],
      ],
    );
  }

  Widget _buildRightSide(BuildContext context, GradingGuideSnapshot? snapshot) {
    final maxW = _gradeColumnMaxWidth(context);

    if (snapshot == null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: const Text(
          'No analysis available',
          textAlign: TextAlign.end,
          style: TextStyle(fontSize: 10, color: Color(0xFF9CA3AF), height: 1.3),
        ),
      );
    }

    final boxes = <Widget>[];
    if (snapshot.psa10Price != null) {
      boxes.add(_GradeBox(
        label: 'PSA 10',
        avg: snapshot.psa10Price!,
        profit: gradingProfitAfterFee(
          guidePrice: snapshot.psa10Price!,
          gradingFee: gradingFee,
          pricePaid: card.pricePaid,
        ),
      ));
    }
    if (snapshot.psa9Price != null) {
      if (boxes.isNotEmpty) boxes.add(const SizedBox(height: 4));
      boxes.add(_GradeBox(
        label: 'PSA 9',
        avg: snapshot.psa9Price!,
        profit: gradingProfitAfterFee(
          guidePrice: snapshot.psa9Price!,
          gradingFee: gradingFee,
          pricePaid: card.pricePaid,
        ),
      ));
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW),
      child: IntrinsicWidth(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: boxes,
        ),
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

class _TierBadge extends StatelessWidget {
  const _TierBadge({required this.tier});
  final _Tier tier;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (tier) {
      _Tier.grade => (const Color(0xFFD1FAE5), const Color(0xFF065F46), 'Grade It'),
      _Tier.borderline => (const Color(0xFFFEF3C7), const Color(0xFF92400E), 'Borderline'),
      _Tier.skip => (const Color(0xFFFEE2E2), const Color(0xFFB91C1C), 'Skip It'),
      _Tier.unavailable => (Colors.transparent, Colors.transparent, ''),
    };
    if (tier == _Tier.unavailable) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(
        label,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: fg, letterSpacing: 0.4),
      ),
    );
  }
}

class _GradeBox extends StatelessWidget {
  const _GradeBox({required this.label, required this.avg, required this.profit});
  final String label;
  final double avg;
  final double profit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              color: Color(0xFF9CA3AF),
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            formatUsd(avg),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
          ),
          Text(
            _formatProfit(profit),
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: _profitColor(profit)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
          ),
        ],
      ),
    );
  }

  String _formatProfit(double v) {
    final core = formatUsd(v.abs());
    return '${v >= 0 ? '+' : '-'}$core';
  }

  Color _profitColor(double v) {
    if (v > 25) return const Color(0xFF059669);
    if (v >= 0) return const Color(0xFFD97706);
    return const Color(0xFFEF4444);
  }
}
