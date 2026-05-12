import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/cardhedge_match.dart';
import '../../core/services/cards_service.dart';
import '../../core/services/comps_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/inline_notice_container.dart';
import '../wishlist/wishlist_screen.dart';
import 'widgets/active_state_indicator.dart';
import 'widgets/full_bleed_card_hero.dart';
import 'widgets/market_analysis_section.dart';

/// Bottom scroll padding so the last section clears the floating tab bar
/// (matches `ItemDetailScreen`).
const double _kShellTabBarScrollInset = 100;

/// Args bundle passed via `GoRouter` `extra` when pushing
/// [MasterCardDetailScreen]. Using a typed DTO keeps the route definition in
/// `router.dart` decoupled from the screen's parameter list.
class MasterCardDetailArgs {
  const MasterCardDetailArgs({
    required this.masterCard,
    required this.parallelName,
    this.parallelSerialMax,
    this.parallelIsAuto = false,
    this.releaseName,
    this.setName,
    this.year,
    this.sport,
    this.onAddToCollection,
    this.onAddToWishlist,
  });

  final MasterCard masterCard;
  final String parallelName;
  final int? parallelSerialMax;
  final bool parallelIsAuto;
  final String? releaseName;
  final String? setName;
  final int? year;
  final String? sport;
  final VoidCallback? onAddToCollection;
  final VoidCallback? onAddToWishlist;
}

/// Read-only detail for a `master_card_definitions` entry — the same shell
/// as [ItemDetailScreen] minus the "Value" and "Your copy" sections, plus
/// "Add to Collection" / "Add to Wishlist" CTAs.
///
/// Pushed from `CatalogScreen` after the user reaches the final card +
/// parallel selection (in either browse or search flows).
class MasterCardDetailScreen extends ConsumerStatefulWidget {
  const MasterCardDetailScreen({
    super.key,
    required this.masterCard,
    required this.parallelName,
    this.parallelSerialMax,
    this.parallelIsAuto = false,
    this.releaseName,
    this.setName,
    this.year,
    this.sport,
    this.onAddToCollection,
    this.onAddToWishlist,
  });

  final MasterCard masterCard;
  final String parallelName;
  final int? parallelSerialMax;
  final bool parallelIsAuto;
  final String? releaseName;
  final String? setName;
  final int? year;
  final String? sport;
  final VoidCallback? onAddToCollection;
  final VoidCallback? onAddToWishlist;

  @override
  ConsumerState<MasterCardDetailScreen> createState() =>
      _MasterCardDetailScreenState();
}

class _MasterCardDetailScreenState
    extends ConsumerState<MasterCardDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _heroKey = GlobalKey();

  /// CardHedge `cardhedge-search-cards` — structured search once when this screen
  /// opens (catalog detail only). Filters by card # + parallel on the server.
  bool _cardHedgeLoading = true;
  CardHedgeMatchPayload? _cardHedgeResult;

  /// When CardHedge search returns multiple rows for the same card #, user can
  /// pick the correct parallel (e.g. White Sparkle) here.
  CardHedgeMatchedCard? _cardHedgeRowPick;

  /// Scroll offset (px) at which the hero gradient is fully behind the AppBar.
  /// Re-measured from the rendered hero on every frame.
  double _heroSwitchThreshold = 320;
  bool _scrolledPastHero = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadCardHedgeSearch());
    });
  }

  Future<void> _loadCardHedgeSearch() async {
    final payload = await ref.read(compsServiceProvider).searchCardHedgeCatalog(
          player: widget.masterCard.player,
          year: widget.year,
          releaseName: widget.releaseName,
          setName: widget.setName,
          sport: widget.sport,
          cardNumber: widget.masterCard.cardNumber,
          parallelName: widget.parallelName,
        );

    if (!mounted) return;
    setState(() {
      _cardHedgeLoading = false;
      _cardHedgeResult = payload;
      _cardHedgeRowPick = null;
    });
  }

  CardHedgeMatchedCard? get _effectiveCardHedgeRow {
    final r = _cardHedgeResult;
    if (r == null || !r.matched) return null;
    return _cardHedgeRowPick ?? r.match;
  }

  List<CardHedgeMatchedCard> _cardHedgeRowsToPick() {
    final r = _cardHedgeResult;
    if (r == null || !r.matched || r.match == null) return const [];
    final m = r.match!;
    final alts = r.alternateMatches ?? const [];
    if (alts.isEmpty) return const [];
    final out = <CardHedgeMatchedCard>[m];
    final seen = <String?>{m.cardId};
    for (final a in alts) {
      if (a.cardId != null && !seen.contains(a.cardId)) {
        seen.add(a.cardId);
        out.add(a);
      }
    }
    return out.length > 1 ? out : const [];
  }

  double? _parseCardHedgePrice(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    if (raw is! String) return null;
    final cleaned = raw.replaceAll(RegExp(r'[^0-9.-]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  static const List<String> _cardHedgeGradeKeys = ['Raw', 'PSA 10', 'PSA 9'];

  /// Maps CardHedge `prices[]` into the same three grades as sold-comps pills.
  String? _normalizeCardHedgeGradeKey(String grade) {
    final g = grade.trim();
    if (g.isEmpty) return null;
    final lower = g.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (lower == 'raw' || lower == 'ungraded') return 'Raw';
    if (lower == 'psa 10' || lower == 'psa10') return 'PSA 10';
    if (lower == 'psa 9' || lower == 'psa9') return 'PSA 9';
    if (_cardHedgeGradeKeys.contains(g)) return g;
    return null;
  }

  Map<String, double?> _gradeAveragesFromCard(CardHedgeMatchedCard? match) {
    final out = <String, double?>{for (final k in _cardHedgeGradeKeys) k: null};
    if (match == null) return out;
    final prices = match.prices;
    if (prices == null || prices.isEmpty) return out;
    for (final row in prices) {
      final key = _normalizeCardHedgeGradeKey(row['grade']?.toString() ?? '');
      if (key == null) continue;
      final parsed = _parseCardHedgePrice(row['price']);
      if (parsed == null || parsed <= 0) continue;
      out[key] = parsed;
    }
    return out;
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final past = _scrollController.offset > _heroSwitchThreshold;
    if (past != _scrolledPastHero) {
      setState(() => _scrolledPastHero = past);
    }
  }

  void _maybeMeasureHero() {
    final ctx = _heroKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final topInset = MediaQuery.paddingOf(context).top;
    final next = box.size.height - (topInset + kToolbarHeight) - 8;
    if ((next - _heroSwitchThreshold).abs() > 1) {
      _heroSwitchThreshold = next;
      _onScroll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final padding = MediaQuery.paddingOf(context);
    final bottomPad = padding.bottom;
    final topInset = padding.top;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeMeasureHero();
    });

    final onLight = _scrolledPastHero;
    final iconTint = onLight ? colors.onSurface : Colors.white;

    final masterCard = widget.masterCard;
    final parallel = widget.parallelName;
    final cardHedgeGradeAverages = _gradeAveragesFromCard(
      _cardHedgeResult?.matched == true ? _effectiveCardHedgeRow : null,
    );

    final userCardsAsync = ref.watch(userCardsProvider);
    final copyCount = userCardsAsync.whenData((all) {
      return all.where((c) {
        final masterMatch = c.masterCardId == masterCard.id;
        final cardNumberMatch = (c.cardNumber?.trim() ?? '') ==
            (masterCard.cardNumber?.trim() ?? '');
        final parallelMatch = c.parallel.trim() == parallel.trim();
        return masterMatch && cardNumberMatch && parallelMatch;
      }).length;
    }).value ?? 0;

    final wishlistAsync = ref.watch(wishlistProvider);
    final inWishlist = wishlistAsync.whenData((wl) {
      return wl.any((w) {
        final playerMatch = (w.player?.trim().toLowerCase() ?? '') ==
            masterCard.player.trim().toLowerCase();
        final cardNumberMatch = (w.cardNumber?.trim() ?? '') ==
            (masterCard.cardNumber?.trim() ?? '');
        final parallelMatch =
            (w.parallel?.trim() ?? 'Base') == parallel.trim();
        return playerMatch && cardNumberMatch && parallelMatch;
      });
    }).value ?? false;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        forceMaterialTransparency: true,
        foregroundColor: iconTint,
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        iconTheme: IconThemeData(color: iconTint),
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: GlassCircleIconButton(
              icon: Icons.arrow_back_ios_new,
              onPressed: () => Navigator.of(context).maybePop(),
              tooltip: 'Back',
              iconSize: 17,
              onDarkSurface: !onLight,
            ),
          ),
        ),
      ),
      body: ListView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          FullBleedHero(
            key: _heroKey,
            topInset: topInset,
            details: HeroDetails(
              player: masterCard.player,
              sport: widget.sport ?? '',
              cardNumber: masterCard.cardNumber,
              imageUrl: masterCard.imageUrl,
              parallel: parallel,
              year: widget.year,
              releaseName: widget.releaseName,
              setName: widget.setName,
              serialMax: widget.parallelSerialMax ?? masterCard.serialMax,
              rookie: masterCard.isRookie,
              autograph: masterCard.isAuto || widget.parallelIsAuto,
              memorabilia: masterCard.isPatch,
              ssp: masterCard.isSSP,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              24,
              16,
              _kShellTabBarScrollInset + bottomPad,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: copyCount > 0
                          ? ActiveStateIndicator(
                              icon: Icons.check_circle,
                              label: 'In Collection ($copyCount)',
                            )
                          : AdaptiveButton.child(
                              onPressed: widget.onAddToCollection,
                              style: AdaptiveButtonStyle.filled,
                              color: AppTheme.primary,
                              child: const Text(
                                'Add to Collection',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: inWishlist
                          ? const ActiveStateIndicator(
                              icon: Icons.favorite,
                              label: 'In Wishlist',
                            )
                          : AdaptiveButton.child(
                              onPressed: widget.onAddToWishlist,
                              style: AdaptiveButtonStyle.bordered,
                              color: AppTheme.primary,
                              child: DefaultTextStyle.merge(
                                style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.favorite_border, size: 18, color: AppTheme.primary),
                                    SizedBox(width: 8),
                                    Text('Add to Wishlist'),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (_cardHedgeLoading)
                  InlineNoticeContainer(
                    icon: Icon(
                      Icons.hourglass_top,
                      size: 20,
                      color: colors.primary,
                    ),
                    highlightBorderColor: colors.primary.withValues(alpha: 0.35),
                    child: Text(
                      'Searching CardHedge…',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                else if (_cardHedgeResult != null) ...[
                  InlineNoticeContainer(
                    icon: Icon(
                      _cardHedgeResult!.hasError
                          ? Icons.warning_amber_rounded
                          : (_cardHedgeResult!.matched
                              ? Icons.verified_outlined
                              : Icons.search_off_outlined),
                      size: 20,
                      color: _cardHedgeResult!.hasError
                          ? colors.error
                          : (_cardHedgeResult!.matched
                              ? colors.primary
                              : colors.onSurface.withValues(alpha: 0.55)),
                    ),
                    highlightBorderColor: _cardHedgeResult!.hasError
                        ? colors.error.withValues(alpha: 0.35)
                        : (_cardHedgeResult!.matched
                            ? colors.primary.withValues(alpha: 0.35)
                            : colors.outline.withValues(alpha: 0.5)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _cardHedgeResult!.hasError
                              ? 'CardHedge'
                              : (_cardHedgeResult!.matched
                                  ? 'CardHedge (search)'
                                  : 'CardHedge'),
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 4),
                        if (_cardHedgeResult!.hasError)
                          Text(
                            _cardHedgeResult!.errorMessage ?? 'Unknown error',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: colors.error,
                                ),
                          )
                        else if (_cardHedgeResult!.matched &&
                            _cardHedgeResult!.match != null)
                          Text(
                            () {
                              final r = _cardHedgeResult!;
                              final m = r.match!;
                              final via = r.resolvedVia == 'card_search'
                                  ? ' (via CardHedge search)'
                                  : '';
                              final setLine = (r.searchSet != null && r.searchSet!.isNotEmpty)
                                  ? '\nSet filter: ${r.searchSet}'
                                  : '';
                              return '${((r.confidence ?? 0) * 100).toStringAsFixed(0)}% confidence (min ${(r.minConfidence * 100).round()}%). ${m.description ?? 'Matched'}$via$setLine';
                            }(),
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        else
                          Text(
                            () {
                              final r = _cardHedgeResult!;
                              if (r.reason == 'below_confidence_threshold') {
                                return 'No match at ≥${(r.minConfidence * 100).round()}% confidence${r.confidence != null ? ' (best ${((r.confidence ?? 0) * 100).toStringAsFixed(0)}%)' : ''}. Sold comps below still use the standard refresh.';
                              }
                              if (r.reason == 'variant_mismatch') {
                                final exp = r.expectedParallel ?? parallel;
                                final got = r.gotVariant ?? '—';
                                final confPct = r.confidence != null
                                    ? '${((r.confidence ?? 0) * 100).toStringAsFixed(0)}%'
                                    : 'high';
                                return 'CardHedge reported $confPct confidence, but the parallel does not line up.\n'
                                    'Yours: $exp\n'
                                    'CardHedge variant: $got\n'
                                    'Sold comps below will use the standard refresh.';
                              }
                              if (r.reason == 'search_no_row_after_filter') {
                                final setL = r.searchSet != null && r.searchSet!.isNotEmpty
                                    ? '\nSet filter: ${r.searchSet}'
                                    : '';
                                return 'CardHedge returned search results, but none matched your card # and parallel after filtering.$setL\n'
                                    'Sold comps below will use the standard refresh.';
                              }
                              return 'No CardHedge match for this card. Sold comps below still use the standard refresh.';
                            }(),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: colors.onSurface.withValues(alpha: 0.75),
                                ),
                          ),
                      ],
                    ),
                  ),
                  if (_cardHedgeResult != null &&
                      _cardHedgeResult!.matched &&
                      _cardHedgeRowsToPick().length > 1) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Parallel (from CardHedge search)',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _cardHedgeRowsToPick().map((c) {
                        final selected = _effectiveCardHedgeRow?.cardId == c.cardId;
                        final raw = (c.variant ?? c.description ?? 'Card').trim();
                        final short =
                            raw.length > 44 ? '${raw.substring(0, 44)}…' : raw;
                        return FilterChip(
                          label: Text(short),
                          selected: selected,
                          onSelected: (_) {
                            setState(() => _cardHedgeRowPick = c);
                          },
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
                MarketAnalysisSection(
                  masterCardId: masterCard.id,
                  parallelName: parallel,
                  initialGrade: 'Raw',
                  segmentColor: colors.primary,
                  cardHedgeGradeAverages: cardHedgeGradeAverages,
                  soldCompsSourceLabel: _cardHedgeResult?.matched == true
                      ? 'CardHedge'
                      : null,
                  skipScraperSoldComps:
                      _cardHedgeResult?.matched == true && _effectiveCardHedgeRow != null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

