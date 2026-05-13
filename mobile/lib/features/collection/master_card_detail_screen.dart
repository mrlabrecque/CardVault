import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/guide_catalog_match.dart';
import '../../core/services/cards_service.dart';
import '../../core/services/comps_service.dart';
import '../../core/utils/guide_grade_prices.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/chrome_metrics.dart';
import '../../core/widgets/card_fan_loader.dart';
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

  /// Loads linked `current_prices` from DB, or runs catalog search when the variant
  /// has no linked guide-price id or prices are not yet materialized.
  bool _guidePricesLoading = true;
  GuideCatalogMatchPayload? _guideMatchResult;

  /// Grade prices from `current_prices` when the variant is already linked (no search).
  Map<String, double?>? _linkedGradePricesFromDb;

  /// When catalog search returns multiple rows for the same card #, user can
  /// pick the correct parallel (e.g. White Sparkle) here.
  GuideCatalogMatchedRow? _guideMatchRowPick;

  /// Scroll offset (px) at which the hero gradient is fully behind the AppBar.
  /// Re-measured from the rendered hero on every frame.
  double _heroSwitchThreshold = 320;
  bool _scrolledPastHero = false;

  /// When persist writes `image_url`, refetch so the hero updates.
  MasterCard? _refreshedMaster;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_syncGuidePricesForMaster());
    });
  }

  @override
  void didUpdateWidget(covariant MasterCardDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.masterCard.id != widget.masterCard.id ||
        oldWidget.parallelName != widget.parallelName ||
        oldWidget.parallelSerialMax != widget.parallelSerialMax ||
        oldWidget.parallelIsAuto != widget.parallelIsAuto ||
        oldWidget.releaseName != widget.releaseName ||
        oldWidget.setName != widget.setName ||
        oldWidget.year != widget.year ||
        oldWidget.sport != widget.sport) {
      setState(() {
        _guidePricesLoading = true;
        _guideMatchResult = null;
        _linkedGradePricesFromDb = null;
        _guideMatchRowPick = null;
        _refreshedMaster = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_syncGuidePricesForMaster());
      });
    }
  }

  Future<void> _syncGuidePricesForMaster() async {
    final baseId = widget.masterCard.id;
    final working = _refreshedMaster ?? widget.masterCard;
    final linkedGuideId = working.guidePriceCardId?.trim();

    if (linkedGuideId != null && linkedGuideId.isNotEmpty) {
      final dbPrices = await ref.read(compsServiceProvider).getMasterCardCurrentPrices(baseId);
      if (!mounted) return;
      final hasPrices = dbPrices.values.any((v) => v != null && v > 0);
      if (hasPrices) {
        setState(() {
          _guidePricesLoading = false;
          _linkedGradePricesFromDb = dbPrices;
          _guideMatchResult = null;
          _guideMatchRowPick = null;
        });
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _guidePricesLoading = true;
      _linkedGradePricesFromDb = null;
    });

    final payload = await ref.read(compsServiceProvider).searchGuidePriceCatalog(
          player: widget.masterCard.player,
          year: widget.year,
          releaseName: widget.releaseName,
          setName: widget.setName,
          sport: widget.sport,
          cardNumber: widget.masterCard.cardNumber,
          parallelName: widget.parallelName,
          persistMasterVariantId: baseId,
        );

    if (!mounted) return;

    MasterCard? refreshed;
    final pm = payload.persistedMaster;
    if (pm != null) {
      refreshed = MasterCard.fromJson(pm);
    }

    if (!mounted) return;
    setState(() {
      _guidePricesLoading = false;
      _linkedGradePricesFromDb = null;
      _guideMatchResult = payload;
      _guideMatchRowPick = null;
      if (refreshed != null) _refreshedMaster = refreshed;
    });
  }

  Future<void> _persistGuideCatalogRow(GuideCatalogMatchedRow m) async {
    final fresh = await ref.read(compsServiceProvider).persistGuidePriceCatalogMatch(
          masterVariantId: widget.masterCard.id,
          guidePriceCardId: m.cardId,
          imageUrl: m.image,
          prices: m.prices,
          sales7d: m.sales7d,
          sales30d: m.sales30d,
          gain: m.gain,
        );
    if (!mounted || fresh == null) return;
    final dbPrices = await ref.read(compsServiceProvider).getMasterCardCurrentPrices(fresh.id);
    if (!mounted) return;
    setState(() {
      _refreshedMaster = fresh;
      _linkedGradePricesFromDb = dbPrices;
    });
  }

  GuideCatalogMatchedRow? get _effectiveGuideMatchRow {
    final r = _guideMatchResult;
    if (r == null || !r.matched) return null;
    return _guideMatchRowPick ?? r.match;
  }

  List<GuideCatalogMatchedRow> _guideMatchRowsToPick() {
    final r = _guideMatchResult;
    if (r == null || !r.matched || r.match == null) return const [];
    final m = r.match!;
    final alts = r.alternateMatches ?? const [];
    if (alts.isEmpty) return const [];
    final out = <GuideCatalogMatchedRow>[m];
    final seen = <String?>{m.cardId};
    for (final a in alts) {
      if (a.cardId != null && !seen.contains(a.cardId)) {
        seen.add(a.cardId);
        out.add(a);
      }
    }
    return out.length > 1 ? out : const [];
  }

  double? _parseGuidePrice(dynamic raw) => parseGuidePriceField(raw);

  Map<String, double?> _gradeAveragesFromCard(GuideCatalogMatchedRow? match) {
    final out = emptyGuideGradePriceMap();
    if (match == null) return out;
    final prices = match.prices;
    if (prices == null || prices.isEmpty) return out;
    for (final row in prices) {
      final gradeRaw = (row['grade'] ?? row['Grade'] ?? row['label'] ?? row['Label'] ?? row['name'] ?? row['Name'])
              ?.toString() ??
          '';
      final key = normalizeGuideDisplayGrade(gradeRaw);
      if (key == null) continue;
      final parsed = _parseGuidePrice(
        row['price'] ?? row['Price'] ?? row['value'] ?? row['Value'] ?? row['avg'] ?? row['Avg'],
      );
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

    final masterCard = _refreshedMaster ?? widget.masterCard;
    final parallel = widget.parallelName;
    final guideMatchRow = _guideMatchResult?.matched == true ? _effectiveGuideMatchRow : null;
    // Hero uses DB/Storage URLs only — third-party CDN URLs were causing an extra
    // swap (CDN → Storage) after persist.
    final heroTrimmed = masterCard.imageUrl?.trim();
    final heroImageUrl =
        (heroTrimmed != null && heroTrimmed.isNotEmpty) ? heroTrimmed : null;

    final guideGradePriceAverages = _linkedGradePricesFromDb ?? _gradeAveragesFromCard(guideMatchRow);

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

    final overlayLoading =
        _guidePricesLoading || userCardsAsync.isLoading || wishlistAsync.isLoading;

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
      body: Stack(
        fit: StackFit.expand,
        children: [
          ListView(
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
                  imageUrl: heroImageUrl,
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
                                  padding: ChromeMetrics.adaptiveBorderedButtonPadding,
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
                    if (!_guidePricesLoading &&
                        _guideMatchResult != null &&
                        _guideMatchResult!.matched &&
                        _guideMatchRowsToPick().length > 1) ...[
                      Text(
                        'Parallel (from catalog match)',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _guideMatchRowsToPick().map((c) {
                          final selected = _effectiveGuideMatchRow?.cardId == c.cardId;
                          final raw = (c.variant ?? c.description ?? 'Card').trim();
                          final short =
                              raw.length > 44 ? '${raw.substring(0, 44)}…' : raw;
                          return FilterChip(
                            label: Text(short),
                            selected: selected,
                            onSelected: (_) {
                              setState(() => _guideMatchRowPick = c);
                              _persistGuideCatalogRow(c);
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    MarketAnalysisSection(
                      masterCardId: masterCard.id,
                      initialGrade: 'Raw',
                      segmentColor: colors.primary,
                      guidePriceCardId: masterCard.guidePriceCardId ?? _effectiveGuideMatchRow?.cardId,
                      guideGradePriceAverages: guideGradePriceAverages,
                      skipScraperSoldComps: true,
                      showDbSoldCompsWhenAvailable: true,
                      titleGain: masterCard.gain,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (overlayLoading)
            Positioned.fill(
              child: AbsorbPointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                  ),
                  child: const Center(
                    child: CardFanLoader(size: 72),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
