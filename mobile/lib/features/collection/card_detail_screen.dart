import 'dart:async';
import 'dart:convert';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide showAdaptiveDialog;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/guide_catalog_match.dart';
import '../../core/models/user_card.dart';
import '../../core/services/cards_service.dart';
import '../../core/services/comps_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/chrome_metrics.dart';
import '../../core/utils/adaptive_ui.dart';
import '../../core/utils/currency_format.dart';
import '../../core/ui/price_guide_copy.dart';
import '../../core/utils/guide_catalog_match_query.dart';
import '../../core/utils/guide_grade_prices.dart';
import '../../core/utils/usd_field.dart';
import '../../core/widgets/adaptive_dropdown.dart';
import '../../core/widgets/adaptive_list_card.dart';
import '../../core/widgets/card_attributes_wrap.dart';
import '../../core/widgets/card_fan_loader.dart';
import '../../core/widgets/inline_notice_container.dart';
import '../../core/widgets/modal_sheet_scaffold.dart';
import '../wishlist/card_sheet.dart';
import '../wishlist/wishlist_screen.dart';
import 'widgets/active_state_indicator.dart';
import 'widgets/detail_property_tile.dart';
import 'widgets/full_bleed_card_hero.dart';
import 'widgets/market_analysis_section.dart';

// Bottom scroll padding when this route is shown inside [AppShell] so the last
// section clears the floating tab bar (matches collection / wishlist lists).
const double _kShellTabBarScrollInset = ChromeMetrics.shellTabBarReserveHeight + 24;

bool _parallelLabelImpliesDefaultBase(String parallelName) {
  final n = parallelName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return n.isEmpty ||
      n == 'base' ||
      n == 'base set' ||
      n == 'base parallel' ||
      n == 'base card' ||
      n == 'baseset' ||
      n == 'baseparallel';
}

/// Args for [CardDetailScreen.catalog] (catalog browse / scan flows).
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
    this.setId,
    this.parallelId,
    this.releaseId,
    this.openedFromScanResults,
    this.openedFromScanSingleRoute,
    this.resyncGuidePricesFromCatalog,
  });

  final MasterCard masterCard;
  final String parallelName;
  final int? parallelSerialMax;
  final bool parallelIsAuto;
  final String? releaseName;
  final String? setName;
  final int? year;
  final String? sport;
  /// Catalog set id — used to resolve [parallelId] and add-card form.
  final String? setId;
  final String? parallelId;
  final String? releaseId;
  final VoidCallback? onAddToCollection;
  final VoidCallback? onAddToWishlist;
  final bool? openedFromScanResults;
  final bool? openedFromScanSingleRoute;
  final bool? resyncGuidePricesFromCatalog;
}

// ── HIG-oriented helpers (semantic color + scalable type) ───────────────────

Color _detailProfitColor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF4ADE80)
      : const Color(0xFF15803D);
}

TextStyle? _detailMetaLabelStyle(BuildContext context) {
  final t = Theme.of(context).textTheme;
  final c = Theme.of(context).colorScheme;
  return t.labelMedium?.copyWith(
    color: c.onSurface.withValues(alpha: 0.60),
    letterSpacing: 0.5,
    fontWeight: FontWeight.w500,
  );
}

TextStyle? _detailValueEmphasisStyle(BuildContext context) {
  final t = Theme.of(context).textTheme;
  final c = Theme.of(context).colorScheme;
  return t.titleLarge?.copyWith(
    fontWeight: FontWeight.w700,
    color: c.onSurface,
    height: 1.2,
  );
}

/// Unified card detail for collection copies and catalog browse.
class CardDetailScreen extends ConsumerStatefulWidget {
  const CardDetailScreen.owned({super.key, required UserCard card})
      : card = card,
        catalog = null;

  const CardDetailScreen.catalog({super.key, required MasterCardDetailArgs catalog})
      : card = null,
        catalog = catalog;

  final UserCard? card;
  final MasterCardDetailArgs? catalog;

  bool get isOwned => card != null;
  bool get isCatalog => catalog != null;

  @override
  ConsumerState<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends ConsumerState<CardDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _heroKey = GlobalKey();

  bool get _isCatalog => widget.isCatalog;
  MasterCardDetailArgs get _catalog => widget.catalog!;

  // ── Guide sync / blocking loader (catalog + owned item detail) ─────────────
  bool _guidePricesLoading = false;
  GuideCatalogMatchPayload? _guideMatchResult;
  Map<String, double?>? _linkedGradePricesFromDb;
  /// Stable instance for [MarketAnalysisSection] — scroll rebuilds must not allocate a new map.
  Map<String, double?>? _stableGuideRecentPrices;
  GuideCatalogMatchedRow? _guideMatchRowPick;
  MasterCard? _refreshedMaster;
  /// Debug builds: lookup request JSON when CardHedge match did not link.
  String? _guideSyncDebugJson;

  bool get _openedFromScanResults => _catalog.openedFromScanResults ?? false;
  bool get _openedFromScanSingleRoute => _catalog.openedFromScanSingleRoute ?? false;
  bool get _needsDoublePopFromScan =>
      _openedFromScanResults && !_openedFromScanSingleRoute;

  /// When true, run a full CardHedge catalog search (slow). Base parallel only
  /// forces search when the variant is not linked yet — not on every open.
  MasterCard get _effectiveCatalogMaster =>
      _refreshedMaster ?? _catalog.masterCard;

  bool get _resyncGuidePricesFromCatalog {
    final o = _catalog.resyncGuidePricesFromCatalog;
    if (o != null) return o;
    if (_catalog.openedFromScanResults ?? false) return true;
    if (_parallelLabelImpliesDefaultBase(_catalog.parallelName)) {
      final id = _effectiveCatalogMaster.guidePriceCardId?.trim() ?? '';
      return id.isEmpty;
    }
    return false;
  }

  /// Full-screen loader only for cold link / explicit resync — not when we
  /// already have a CardHedge id and can hydrate from DB in the background.
  bool get _catalogNeedsBlockingGuideOverlay {
    if (_resyncGuidePricesFromCatalog) return true;
    final id = _effectiveCatalogMaster.guidePriceCardId?.trim() ?? '';
    return id.isEmpty;
  }

  /// Resolved per-parallel `master_card_definitions` id (after [_resolveCatalogVariantMaster]).
  String get _catalogVariantId => _effectiveCatalogMaster.id;

  Map<String, double?>? _resolvedGuideRecentPrices(Map<String, double?> raw) {
    final next = withCanonicalGuidePricePlaceholders(raw);
    if (guideGradePriceMapsEqual(_stableGuideRecentPrices, next)) {
      return _stableGuideRecentPrices;
    }
    _stableGuideRecentPrices = next;
    return next;
  }

  /// Scroll offset (px) at which the hero gradient is fully behind the AppBar.
  /// Re-measured from the rendered hero on every frame.
  double _heroSwitchThreshold = 320;
  bool _scrolledPastHero = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (_isCatalog) {
      _guidePricesLoading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_bootstrapCatalogDetail());
      });
    } else {
      final c = widget.card!;
      final masterId = c.masterCardId?.trim();
      if (masterId != null && masterId.isNotEmpty && (c.displayValue ?? 0) <= 0) {
        _guidePricesLoading = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_bootstrapOwnedDetail());
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant CardDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isCatalog) return;
    final o = oldWidget.catalog!;
    final n = _catalog;
    if (o.masterCard.id != n.masterCard.id ||
        o.parallelName != n.parallelName ||
        o.parallelSerialMax != n.parallelSerialMax ||
        o.parallelIsAuto != n.parallelIsAuto ||
        o.releaseName != n.releaseName ||
        o.setName != n.setName ||
        o.year != n.year ||
        o.sport != n.sport ||
        (o.openedFromScanResults ?? false) != (n.openedFromScanResults ?? false) ||
        (o.openedFromScanSingleRoute ?? false) != (n.openedFromScanSingleRoute ?? false) ||
        o.resyncGuidePricesFromCatalog != n.resyncGuidePricesFromCatalog ||
        o.setId != n.setId ||
        o.parallelId != n.parallelId ||
        o.releaseId != n.releaseId) {
      setState(() {
        _guidePricesLoading = true;
        _guideMatchResult = null;
        _linkedGradePricesFromDb = null;
        _guideMatchRowPick = null;
        _refreshedMaster = null;
        _guideSyncDebugJson = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_bootstrapCatalogDetail());
      });
    }
  }

  Future<void> _bootstrapCatalogDetail() async {
    await _resolveCatalogVariantMaster();
    if (!mounted) return;
    await _syncGuidePricesForMaster();
  }

  Future<void> _bootstrapOwnedDetail() async {
    final masterId = widget.card!.masterCardId?.trim();
    if (masterId == null || masterId.isEmpty) {
      if (mounted) setState(() => _guidePricesLoading = false);
      return;
    }
    try {
      await ref.read(compsServiceProvider).syncMasterCatalogPricingForVariant(masterId);
      ref.invalidate(userCardsProvider);
      await ref.read(userCardsProvider.future);
    } finally {
      if (mounted) setState(() => _guidePricesLoading = false);
    }
  }

  Future<void> _resolveCatalogVariantMaster() async {
    final cards = ref.read(cardsServiceProvider);
    final parallel = await _lookupCatalogParallel();
    if (!mounted) return;
    try {
      final variantId = await cards.ensureCatalogVariant(
        catalogVariantId: _catalog.masterCard.id,
        parallelId: parallel?.id ?? _catalog.parallelId,
      );
      if (!mounted) return;
      final fetched = await cards.fetchMasterCardById(variantId);
      if (!mounted) return;
      if (fetched != null) _refreshedMaster = fetched;
    } catch (e, st) {
      debugPrint('Catalog variant resolve: $e\n$st');
    }
  }

  Future<SetParallel?> _lookupCatalogParallel() async {
    final setId = _catalog.setId?.trim();
    if (setId == null || setId.isEmpty) return null;
    try {
      final parallels = await ref.read(cardsServiceProvider).getParallels(setId);
      return resolveSetParallelForCatalog(parallels, _catalog.parallelName);
    } catch (e, st) {
      debugPrint('lookupCatalogParallel: $e\n$st');
    }
    return null;
  }

  Future<void> _openCatalogAddToCollectionSheet() async {
    final master = _refreshedMaster ?? _catalog.masterCard;
    final parallel = await _lookupCatalogParallel();
    if (!mounted) return;
    final parallelLabel = (parallel?.name.trim().isNotEmpty ?? false)
        ? parallel!.name.trim()
        : _catalog.parallelName.trim();
    final pricePaidCtrl = TextEditingController();
    final serialNumberCtrl = TextEditingController();
    final gradeValueCtrl = TextEditingController();
    var isGraded = false;
    var grader = 'PSA';

    if (!mounted) return;
    await showAdaptiveSheet(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return CardSheet(
        title: 'Add to Your Collection',
        card: master,
        setName: _catalog.setName,
        releaseName: _catalog.releaseName,
        year: _catalog.year,
        previewParallelName: parallelLabel,
        previewParallelSerialMax: parallel?.serialMax ?? _catalog.parallelSerialMax,
        previewParallelIsAuto: parallel?.isAuto ?? _catalog.parallelIsAuto,
        showPricePaid: true,
        pricePaidCtrl: pricePaidCtrl,
        showSerialNumber: (parallel?.serialMax ?? _catalog.parallelSerialMax) != null,
        serialNumberCtrl: serialNumberCtrl,
        showGraded: true,
        isGraded: isGraded,
        grader: grader,
        gradeValueCtrl: gradeValueCtrl,
        onGradedChanged: (v) => setSheetState(() => isGraded = v),
        onGraderChanged: (g) => setSheetState(() => grader = g ?? 'PSA'),
        onSave: (_) async {
          try {
            final variantId = await ref.read(cardsServiceProvider).ensureCatalogVariant(
                  catalogVariantId: master.id,
                  parallelId: parallel?.id ?? _catalog.parallelId,
                );
            final form = AddCardFormData(
              masterCardId: variantId,
              setId: _catalog.setId,
              player: master.player,
              cardNumber: master.cardNumber,
              serialMax: master.serialMax,
              isRookie: master.isRookie,
              isAuto: master.isAuto,
              isPatch: master.isPatch,
              isSSP: master.isSSP,
              parallelId: parallel?.id ?? _catalog.parallelId,
              parallelName: parallelLabel,
              pricePaid: parseUsdInput(pricePaidCtrl.text),
              serialNumber: serialNumberCtrl.text.trim().isEmpty
                  ? null
                  : serialNumberCtrl.text.trim(),
              isGraded: isGraded,
              grader: isGraded ? grader : 'PSA',
              gradeValue: isGraded && gradeValueCtrl.text.trim().isNotEmpty
                  ? gradeValueCtrl.text.trim()
                  : null,
            );
            final created = await ref.read(cardsServiceProvider).addCard(form);
            await ref
                .read(compsServiceProvider)
                .syncMasterCatalogPricingForVariant(created.masterCardId);
            ref.invalidate(userCardsProvider);
            await ref.read(userCardsProvider.future);
            unawaited(
              ref.read(compsServiceProvider).fetchCardImage(created.masterCardId),
            );
            if (mounted) {
              AdaptiveSnackBar.show(
                context,
                message: 'Card added!',
                type: AdaptiveSnackBarType.success,
                duration: const Duration(seconds: 2),
              );
            }
            return null;
          } catch (e) {
            return e.toString();
          }
        },
            );
          },
        );
      },
    );

    pricePaidCtrl.dispose();
    serialNumberCtrl.dispose();
    gradeValueCtrl.dispose();
  }

  Future<void> _openCatalogAddToWishlistSheet() async {
    final master = _refreshedMaster ?? _catalog.masterCard;
    final parallel = await _lookupCatalogParallel();
    if (!mounted) return;
    final parallelLabel = (parallel?.name.trim().isNotEmpty ?? false)
        ? parallel!.name.trim()
        : _catalog.parallelName.trim();
    final targetPriceCtrl = TextEditingController();

    if (!mounted) return;
    await showAdaptiveSheet(
      context: context,
      builder: (_) => CardSheet(
        title: 'Add to Wishlist',
        card: master,
        setName: _catalog.setName,
        releaseName: _catalog.releaseName,
        year: _catalog.year,
        previewParallelName: parallelLabel,
        previewParallelSerialMax: parallel?.serialMax ?? _catalog.parallelSerialMax,
        previewParallelIsAuto: parallel?.isAuto ?? _catalog.parallelIsAuto,
        showTargetPrice: true,
        targetPriceCtrl: targetPriceCtrl,
        showGraded: false,
        onSave: (_) async {
          try {
            final variantId = await ref.read(cardsServiceProvider).ensureCatalogVariant(
                  catalogVariantId: master.id,
                  parallelId: parallel?.id ?? _catalog.parallelId,
                );
            await ref.read(wishlistProvider.notifier).add({
              'player': master.player.trim(),
              'year': _catalog.year,
              'set_name': _catalog.releaseName,
              'card_number': (master.cardNumber ?? '').trim(),
              'parallel': parallelLabel,
              'is_rookie': master.isRookie,
              'is_auto': master.isAuto,
              'is_patch': master.isPatch,
              'serial_max': master.serialMax,
              'grade': null,
              'ebay_query': null,
              'exclude_terms': <String>[],
              'target_price': parseUsdInput(targetPriceCtrl.text),
              'master_card_id': variantId,
              'release_id': _catalog.releaseId,
              'set_id': _catalog.setId,
              'sport': _catalog.sport,
            });
            ref.invalidate(wishlistProvider);
            if (mounted) {
              AdaptiveSnackBar.show(
                context,
                message: 'Added to wishlist!',
                type: AdaptiveSnackBarType.success,
                duration: const Duration(seconds: 2),
              );
            }
            return null;
          } catch (e) {
            return e.toString();
          }
        },
      ),
    );

    targetPriceCtrl.dispose();
  }

  VoidCallback get _onAddToCollection =>
      _catalog.onAddToCollection ??
      () => unawaited(_openCatalogAddToCollectionSheet());

  VoidCallback get _onAddToWishlist =>
      _catalog.onAddToWishlist ?? () => unawaited(_openCatalogAddToWishlistSheet());

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

  UserCard _resolvedCard() {
    final seed = widget.card!;
    final async = ref.watch(userCardsProvider);
    final list = async.asData?.value;
    if (list != null) {
      for (final c in list) {
        if (c.id == seed.id) return c;
      }
    }
    return seed;
  }

  GuideCatalogMatchedRow? _bestRowFromPayload(GuideCatalogMatchPayload? payload) {
    if (payload == null) return null;
    final candidates = guideCatalogMatchCandidates(payload);
    if (candidates.isEmpty) return payload.match;
    if (guideCatalogParallelImpliesBase(_catalog.parallelName)) {
      return pickBestGuideCatalogMatchForBase(candidates, setName: _catalog.setName);
    }
    return pickBestAmongExactGuideCatalogMatches(candidates);
  }

  String _resolvedCardhedgeId({MasterCard? master, GuideCatalogMatchPayload? payload}) {
    final fromMaster =
        (master ?? _refreshedMaster ?? _catalog.masterCard).guidePriceCardId?.trim();
    if (fromMaster != null && fromMaster.isNotEmpty) return fromMaster;
    final fromPick = _guideMatchRowPick?.cardId?.trim();
    if (fromPick != null && fromPick.isNotEmpty) return fromPick;
    final fromMatch = payload?.match?.cardId?.trim();
    if (fromMatch != null && fromMatch.isNotEmpty) return fromMatch;
    final fromBest = _bestRowFromPayload(payload)?.cardId?.trim();
    if (fromBest != null && fromBest.isNotEmpty) return fromBest;
    return '';
  }

  String? _guideLookupDebugJson({
    GuideCatalogMatchPayload? payload,
    MasterCard? master,
  }) {
    if (!kDebugMode) return null;
    final hasLink = _resolvedCardhedgeId(master: master, payload: payload).isNotEmpty;
    if (hasLink) return null;

    final map = <String, dynamic>{};
    if (payload != null) {
      if (payload.reason != null && payload.reason!.isNotEmpty) {
        map['match_reason'] = payload.reason;
      }
      if (payload.searchSet != null && payload.searchSet!.isNotEmpty) {
        map['search_set'] = payload.searchSet;
      }
      if (payload.searchMeta != null && payload.searchMeta!.isNotEmpty) {
        map['search_meta'] = payload.searchMeta;
      }
      if (payload.expectedParallel != null && payload.expectedParallel!.isNotEmpty) {
        map['expected_parallel'] = payload.expectedParallel;
      }
    }
    if (payload?.vaultRequestToEdge != null) {
      map['vault_to_edge'] = payload!.vaultRequestToEdge;
    }
    if (payload?.cardhedgeRequest != null) {
      map['cardhedge_request'] = payload!.cardhedgeRequest;
    }
    if (payload != null && map.isEmpty) {
      map['match_response'] = payload.toJson();
    }
    if (map.isEmpty) {
      return const JsonEncoder.withIndent('  ').convert({
        'error': PriceGuideCopy.debugNoResponse,
      });
    }
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  void _applyCardhedgeSearchResult(GuideCatalogMatchPayload payload, {MasterCard? master}) {
    if (master != null) _refreshedMaster = master;
    setState(() {
      _guideMatchResult = payload;
      _guideSyncDebugJson = _guideLookupDebugJson(payload: payload, master: master);
    });
  }

  void _finishGuideSync({
    MasterCard? master,
    Map<String, double?>? linkedPrices,
    GuideCatalogMatchPayload? matchResult,
  }) {
    if (master != null) _refreshedMaster = master;
    setState(() {
      _linkedGradePricesFromDb = linkedPrices;
      if (matchResult != null) _guideMatchResult = matchResult;
      if (matchResult == null) _guideMatchRowPick = null;
      _guidePricesLoading = false;
      _guideSyncDebugJson = _guideLookupDebugJson(payload: matchResult, master: master);
    });
  }

  Future<void> _syncGuidePricesForMaster() async {
    final variantId = _catalogVariantId;
    final comps = ref.read(compsServiceProvider);
    final cards = ref.read(cardsServiceProvider);

    final fetched = await cards.fetchMasterCardById(variantId);
    if (!mounted) return;

    var working = fetched ?? _refreshedMaster ?? _catalog.masterCard;
    final linkedGuideId = working.guidePriceCardId?.trim() ?? '';

    // ── Linked (`cardhedge_id`): read `current_prices` if newest row < 24h; else hydrate
    // via `cardhedge-persist-variant` / CardHedge card-details only. Never fall through to
    // text `cardhedge-search-cards` — that can replace the link or persist empty prices.
    if (linkedGuideId.isNotEmpty) {
      var snap = await comps.loadMasterCardCurrentPricesSnapshot(variantId);
      if (!mounted) return;

      if (snap.hasAnyPrice && !snap.isStale) {
        _finishGuideSync(master: working, linkedPrices: snap.prices);
        return;
      }

      final hydrated = await comps.refreshStaleLinkedGuidePrices(
        masterVariantId: variantId,
        guidePriceCardId: linkedGuideId,
      );
      if (!mounted) return;
      if (hydrated != null) {
        working = hydrated;
      }
      snap = await comps.loadMasterCardCurrentPricesSnapshot(working.id);
      if (!mounted) return;

      final dbPrices = guideGradeMapHasAnyPrice(snap.prices) ? snap.prices : null;
      _finishGuideSync(
        master: working,
        linkedPrices: dbPrices,
        matchResult: null,
      );
      return;
    }

    if (!mounted) return;
    if (_catalogNeedsBlockingGuideOverlay) {
      setState(() {
        _guidePricesLoading = true;
        _linkedGradePricesFromDb = null;
      });
    }

    final payload = await comps.searchGuidePriceCatalog(
      player: _catalog.masterCard.player,
      year: _catalog.year,
      releaseName: _catalog.releaseName,
      setName: _catalog.setName,
      sport: _catalog.sport,
      cardNumber: _catalog.masterCard.cardNumber,
      parallelName: _catalog.parallelName,
      persistMasterVariantId: variantId,
    );
    if (!mounted) return;

    _applyCardhedgeSearchResult(payload, master: working);

    MasterCard? refreshed;
    final pm = payload.persistedMaster;
    if (pm != null) {
      refreshed = MasterCard.fromJson(pm);
    } else if (payload.matched) {
      GuideCatalogMatchedRow? rowToPersist;
      final candidates = guideCatalogMatchCandidates(payload);
      if (candidates.isNotEmpty) {
        if (guideCatalogParallelImpliesBase(_catalog.parallelName)) {
          rowToPersist = pickBestGuideCatalogMatchForBase(
            candidates,
            setName: _catalog.setName,
          );
        } else {
          rowToPersist = pickBestAmongExactGuideCatalogMatches(candidates);
        }
      }
      if (rowToPersist?.cardId?.trim().isNotEmpty == true) {
        final m = rowToPersist!;
        refreshed = await comps.persistGuidePriceCatalogMatch(
          masterVariantId: variantId,
          guidePriceCardId: m.cardId,
          imageUrl: m.image,
          prices: m.prices,
          sales7d: m.sales7d,
          sales30d: m.sales30d,
          gain: m.gain,
        );
      }
    }

    if (refreshed == null && payload.matched) {
      final fallbackId = _resolvedCardhedgeId(payload: payload);
      if (fallbackId.isNotEmpty) {
        refreshed = await comps.persistCardHedgeHydratedFromCardId(
          masterVariantId: variantId,
          guidePriceCardId: fallbackId,
        );
      }
    }

    if (refreshed == null) {
      final refetched = await cards.fetchMasterCardById(variantId);
      if (refetched?.guidePriceCardId?.trim().isNotEmpty == true) {
        refreshed = refetched;
      }
    } else {
      working = refreshed;
    }

    Map<String, double?>? dbPrices;
    if (_resolvedCardhedgeId(master: refreshed ?? working, payload: payload).isNotEmpty) {
      final loaded = await comps.getMasterCardCurrentPrices(variantId);
      if (guideGradeMapHasAnyPrice(loaded)) {
        dbPrices = loaded;
      }
    }

    _finishGuideSync(
      master: refreshed ?? working,
      linkedPrices: dbPrices,
      matchResult: payload,
    );
  }

  Future<void> _persistGuideCatalogRow(GuideCatalogMatchedRow m) async {
    final fresh = await ref.read(compsServiceProvider).persistGuidePriceCatalogMatch(
          masterVariantId: _catalogVariantId,
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
    _finishGuideSync(master: fresh, linkedPrices: dbPrices);
  }

  GuideCatalogMatchedRow? get _effectiveGuideMatchRow =>
      _guideMatchRowPick ?? _bestRowFromPayload(_guideMatchResult);

  List<GuideCatalogMatchedRow> _guideMatchRowsToPick() {
    final r = _guideMatchResult;
    if (r == null || r.match == null) return const [];
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

  Map<String, double?> _gradeAveragesFromCard(GuideCatalogMatchedRow? match) {
    final out = <String, double?>{};
    if (match == null) return out;
    final prices = match.prices;
    if (prices == null || prices.isEmpty) return out;
    for (final row in prices) {
      final gradeRaw = (row['grade'] ?? row['Grade'] ?? row['label'] ?? row['Label'] ?? row['name'] ?? row['Name'])
              ?.toString()
              .trim() ??
          '';
      if (gradeRaw.isEmpty) continue;
      final parsed = parseGuidePriceField(
        row['price'] ?? row['Price'] ?? row['value'] ?? row['Value'] ?? row['avg'] ?? row['Avg'],
      );
      if (parsed == null || parsed <= 0) continue;
      String? existingKey;
      for (final k in out.keys) {
        if (currentPricesGradeLooselyEqual(k, gradeRaw)) {
          existingKey = k;
          break;
        }
      }
      out[existingKey ?? gradeRaw] = parsed;
    }
    return withCanonicalGuidePricePlaceholders(out);
  }

  void _maybeMeasureHero() {
    if (!_isCatalog) return;
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

  void _handleBack() {
    if (_isCatalog && _needsDoublePopFromScan) {
      final router = GoRouter.of(context);
      router.pop();
      router.pop();
      return;
    }
    _close(context);
  }

  String _missingCatalogValueNotice(UserCard card) {
    if (card.masterCardId == null) {
      return PriceGuideCopy.catalogNotLinkedValue;
    }
    final hasCh = card.embeddedMasterGuideCardId != null && card.embeddedMasterGuideCardId!.trim().isNotEmpty;
    if (!hasCh) {
      return PriceGuideCopy.variantNotMatchedValue;
    }
    return 'No recent prices.';
  }

  void _close(BuildContext context) {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    GoRouter.maybeOf(context)?.go('/collection');
  }

  String _resolveDefaultGrade(UserCard card) {
    if (!card.isGraded) return 'Raw';
    final grade = card.grade ?? '';
    if (grade == '10' || grade == '10.0') return 'PSA 10';
    if (grade == '9' || grade == '9.0') return 'PSA 9';
    return 'Raw';
  }

  String _relativeRefreshed(DateTime t) {
    final now = DateTime.now();
    final d = now.difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${t.month}/${t.day}/${t.year}';
  }

  static const _graders = ['PSA', 'BGS', 'SGC', 'CGC', 'CSG'];

  Future<void> _openEditSheet(UserCard card) async {
    final usdPaidFmt = createUsdCurrencyInputFormatter();
    final pricePaidCtrl = TextEditingController(
      text: card.pricePaid != null ? usdPaidFmt.formatDouble(card.pricePaid!) : '',
    );
    final serialCtrl = TextEditingController(text: card.serialNumber ?? '');
    final graderCtrl = TextEditingController(text: card.grader ?? 'PSA');
    final gradeCtrl = TextEditingController(text: card.grade ?? '');
    final otherParallelCtrl = TextEditingController();
    var isGraded = card.isGraded;
    var selectedParallelId = card.parallelId;
    var saving = false;

    List<SetParallel> parallels = const [];
    if (card.setId != null) {
      try {
        parallels = await ref.read(cardsServiceProvider).getParallels(card.setId!);
      } catch (e, st) {
        debugPrint('ItemDetail getParallels: $e\n$st');
        parallels = const [];
      }
    }
    if (!mounted) return;

    await showAdaptiveSheet(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final colors = Theme.of(sheetContext).colorScheme;
            final isOtherParallel = selectedParallelId == '__other__';

            Future<void> saveFromSheet() async {
              setSheetState(() => saving = true);
              try {
                final selectedParallelName = selectedParallelId == null
                    ? null
                    : parallels
                        .where((p) => p.id == selectedParallelId)
                        .map((p) => p.name.trim())
                        .where((name) => name.isNotEmpty)
                        .firstOrNull;
                final parallelName = isOtherParallel
                    ? (otherParallelCtrl.text.trim().isEmpty ? 'Base' : otherParallelCtrl.text.trim())
                    : (selectedParallelId == null ? 'Base' : (selectedParallelName ?? card.parallel));
                await ref.read(cardsServiceProvider).updateCard(card.id, {
                  'price_paid': parseUsdInput(pricePaidCtrl.text),
                  'serial_number': serialCtrl.text.isEmpty ? null : serialCtrl.text,
                  'is_graded': isGraded,
                  'grader': isGraded ? graderCtrl.text : null,
                  'grade_value': isGraded ? gradeCtrl.text : null,
                  'parallel_id': isOtherParallel ? null : selectedParallelId,
                  'parallel_name': parallelName,
                });
                ref.invalidate(userCardsProvider);
                if (!mounted || !sheetContext.mounted) return;
                Navigator.of(sheetContext).pop();
                if (!mounted) return;
                AdaptiveSnackBar.show(context, message: 'Card updated.', type: AdaptiveSnackBarType.success);
              } catch (e) {
                if (!mounted) return;
                AdaptiveSnackBar.show(context, message: 'Error: $e', type: AdaptiveSnackBarType.error);
              } finally {
                if (mounted) {
                  setSheetState(() => saving = false);
                }
              }
            }

            return ModalSheetScaffold(
              title: 'Edit your copy',
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: _EditCardPreview(card: card),
                  ),
                  const SizedBox(height: 16),
                  _SheetFieldLabel('Parallel'),
                  if (parallels.isNotEmpty)
                    AdaptiveDropdown<String?>(
                      value: selectedParallelId,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Base')),
                        ...parallels.map((p) => DropdownMenuItem(
                              value: p.id,
                              child: Text('${p.name}${p.serialMax != null ? ' /${p.serialMax}' : ''}'),
                            )),
                        const DropdownMenuItem(value: '__other__', child: Text('Other…')),
                      ],
                      onChanged: (id) => setSheetState(() {
                        selectedParallelId = id;
                        otherParallelCtrl.text = '';
                      }),
                    )
                  else
                    AdaptiveTextField(
                      controller: otherParallelCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      placeholder: 'Base',
                      cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(sheetContext),
                      decoration: InputDecoration(
                        hintText: 'Base',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                    ),
                  if (isOtherParallel) ...[
                    const SizedBox(height: 12),
                    _SheetFieldLabel('Parallel name'),
                    AdaptiveTextField(
                      controller: otherParallelCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      placeholder: 'e.g. Pink Refractor',
                      cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(sheetContext),
                      decoration: InputDecoration(
                        hintText: 'e.g. Pink Refractor',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _SheetFieldLabel('Price Paid'),
                  AdaptiveTextField(
                    controller: pricePaidCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [usdPaidFmt],
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    placeholder: '\$0.00',
                    cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(sheetContext),
                    decoration: InputDecoration(
                      hintText: '\$0.00',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                  ),
                  if (card.serialMax != null) ...[
                    const SizedBox(height: 16),
                    _SheetFieldLabel('Serial # (your copy, e.g. 34 of /${card.serialMax})'),
                    AdaptiveTextField(
                      controller: serialCtrl,
                      keyboardType: TextInputType.number,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      placeholder: 'e.g. 34',
                      cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(sheetContext),
                      decoration: InputDecoration(
                        hintText: 'e.g. 34',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: _SheetFieldLabel.inline('Graded copy'),
                          ),
                        ),
                        AdaptiveSwitch(
                          value: isGraded,
                          onChanged: (v) => setSheetState(() => isGraded = v),
                          activeColor: AppTheme.primary,
                        ),
                      ],
                    ),
                  ),
                  if (isGraded) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: AdaptiveDropdown<String>(
                            value: graderCtrl.text.isEmpty ? 'PSA' : graderCtrl.text,
                            decoration: InputDecoration(
                              labelText: 'Grader',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              isDense: true,
                            ),
                            items: _graders.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                            onChanged: (v) => setSheetState(() => graderCtrl.text = v ?? 'PSA'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AdaptiveTextField(
                            controller: gradeCtrl,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            placeholder: '10',
                            cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(sheetContext),
                            decoration: InputDecoration(
                              labelText: 'Grade',
                              hintText: '10',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Divider(height: 1, color: colors.outline.withValues(alpha: 0.2)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: AdaptiveButton.child(
                      onPressed: saving ? null : saveFromSheet,
                      style: AdaptiveButtonStyle.filled,
                      color: AppTheme.primary,
                      child: saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'Save',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    pricePaidCtrl.dispose();
    serialCtrl.dispose();
    graderCtrl.dispose();
    gradeCtrl.dispose();
    otherParallelCtrl.dispose();
  }

  Future<void> _delete(UserCard card) async {
    final confirm = await showAdaptiveDialog<bool>(
      context: context,
      title: 'Delete Card',
      content: 'Remove this card from your collection?',
      cancelLabel: 'Cancel',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (confirm == true) {
      await ref.read(cardsServiceProvider).deleteCard(card.id);
      ref.invalidate(userCardsProvider);
      if (mounted) _close(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final padding = MediaQuery.paddingOf(context);
    final bottomPad = padding.bottom;
    final topInset = padding.top;
    final onLight = _scrolledPastHero;
    final iconTint = onLight ? colors.onSurface : Colors.white;

    if (_isCatalog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeMeasureHero();
      });
    }

    final scaffold = Scaffold(
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
        leadingWidth: _guidePricesLoading ? 0 : 64,
        automaticallyImplyLeading: false,
        leading: _guidePricesLoading
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Center(
                  child: GlassCircleIconButton(
                    icon: Icons.arrow_back_ios_new,
                    onPressed: _handleBack,
                    tooltip: 'Back',
                    iconSize: 17,
                    onDarkSurface: !onLight,
                  ),
                ),
              ),
        actions: widget.isOwned && !_guidePricesLoading
            ? [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: AdaptivePopupMenuButton.icon<String>(
                      icon: 'ellipsis',
                      tint: iconTint,
                      size: 44,
                      buttonStyle: PopupButtonStyle.glass,
                      items: const [
                        AdaptivePopupMenuItem<String>(
                          label: 'Edit',
                          icon: 'pencil',
                          value: 'edit',
                        ),
                        AdaptivePopupMenuItem<String>(
                          label: 'Delete',
                          icon: 'trash',
                          value: 'delete',
                        ),
                      ],
                      onSelected: (_, entry) {
                        final card = _resolvedCard();
                        switch (entry.value) {
                          case 'edit':
                            _openEditSheet(card);
                            break;
                          case 'delete':
                            _delete(card);
                            break;
                        }
                      },
                    ),
                  ),
                ),
              ]
            : null,
      ),
      body: _guidePricesLoading
          ? _buildDetailLoadingPane(context, colors)
          : _isCatalog
              ? _buildCatalogBody(context, colors, topInset, bottomPad)
              : _buildDetailListView(context, colors, topInset, bottomPad),
    );

    if (!_isCatalog) return scaffold;

    return PopScope(
      canPop: !_needsDoublePopFromScan,
      onPopInvokedWithResult: (didPop, result) {
        if (_needsDoublePopFromScan && !didPop) {
          _handleBack();
        }
      },
      child: scaffold,
    );
  }

  /// Shared scroll: hero → (Value + Your copy | catalog CTAs) → market.
  Widget _buildDetailListView(
    BuildContext context,
    ColorScheme colors,
    double topInset,
    double bottomPad,
  ) {
    final contentPad = EdgeInsets.fromLTRB(16, 24, 16, _kShellTabBarScrollInset + bottomPad);

    if (widget.isOwned) {
      final card = _resolvedCard();
      final hasValue = card.displayValue != null;
      final pl = hasValue ? card.pl : null;
      final plPct =
          (hasValue && card.pricePaid != null && card.pricePaid! > 0) ? card.plPct : null;

      return ListView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          FullBleedHero(
            topInset: topInset,
            details: HeroDetails(
              player: card.player,
              sport: card.sport,
              cardNumber: card.cardNumber,
              imageUrl: card.imageUrl,
              parallel: card.parallel,
              year: card.year,
              releaseName: card.set,
              setName: card.checklist,
              serialNumber: card.serialNumber,
              serialMax: card.serialMax,
              rookie: card.rookie,
              autograph: card.autograph,
              memorabilia: card.memorabilia,
              ssp: card.ssp,
              isGraded: card.isGraded,
              grader: card.grader,
              grade: card.grade,
            ),
          ),
          Padding(
            padding: contentPad,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildValueSection(context, colors, card, hasValue, pl, plPct),
                const SizedBox(height: 24),
                _buildYourCopySection(context, card),
                const SizedBox(height: 24),
                _buildMarketSection(context, colors, card: card),
              ],
            ),
          ),
        ],
      );
    }

    final masterCard = _refreshedMaster ?? _catalog.masterCard;
    final parallel = _catalog.parallelName;
    final heroTrimmed = masterCard.imageUrl?.trim();
    final heroImageUrl =
        (heroTrimmed != null && heroTrimmed.isNotEmpty) ? heroTrimmed : null;

    final guideMatchRow = _effectiveGuideMatchRow;
    final guidePricesRaw =
        _linkedGradePricesFromDb ?? _gradeAveragesFromCard(guideMatchRow);
    final hasUsableGuidePrices = guideGradeMapHasAnyPrice(guidePricesRaw);
    final guideRecentPrices = hasUsableGuidePrices
        ? _resolvedGuideRecentPrices(guidePricesRaw)
        : (_stableGuideRecentPrices = null);
    final guidePriceCardId =
        masterCard.guidePriceCardId ?? _effectiveGuideMatchRow?.cardId;
    final hasGuideCatalogLink =
        guidePriceCardId != null && guidePriceCardId.trim().isNotEmpty;

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
        final parallelMatch = (w.parallel?.trim() ?? 'Base') == parallel.trim();
        return playerMatch && cardNumberMatch && parallelMatch;
      });
    }).value ?? false;

    return ListView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        FullBleedHero(
          key: _heroKey,
          topInset: topInset,
          details: HeroDetails(
            player: masterCard.player,
            sport: _catalog.sport ?? '',
            cardNumber: masterCard.cardNumber,
            imageUrl: heroImageUrl,
            parallel: parallel,
            year: _catalog.year,
            releaseName: _catalog.releaseName,
            setName: _catalog.setName,
            serialMax: _catalog.parallelSerialMax ?? masterCard.serialMax,
            rookie: masterCard.isRookie,
            autograph: masterCard.isAuto || _catalog.parallelIsAuto,
            memorabilia: masterCard.isPatch,
            ssp: masterCard.isSSP,
          ),
        ),
        Padding(
          padding: contentPad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCatalogActionsRow(
                copyCount: copyCount,
                inWishlist: inWishlist,
              ),
              const SizedBox(height: 24),
              if (hasGuideCatalogLink &&
                  _guideMatchResult != null &&
                  shouldShowGuideParallelPicker(
                    catalogParallelName: _catalog.parallelName,
                    rows: _guideMatchRowsToPick(),
                  )) ...[
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
                        unawaited(_persistGuideCatalogRow(c));
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
              ],
              _buildMarketSection(
                context,
                colors,
                masterCard: masterCard,
                guidePriceCardId: guidePriceCardId,
                guideRecentPrices: guideRecentPrices,
                hasUsableGuidePrices: hasUsableGuidePrices,
                hasGuideCatalogLink: hasGuideCatalogLink,
                titleGain: masterCard.gain,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCatalogActionsRow({
    required int copyCount,
    required bool inWishlist,
  }) {
    return Row(
      children: [
        Expanded(
          child: copyCount > 0
              ? ActiveStateIndicator(
                  icon: Icons.check_circle,
                  label: 'In Collection ($copyCount)',
                )
              : AdaptiveButton.child(
                  onPressed: _onAddToCollection,
                  style: AdaptiveButtonStyle.filled,
                  color: AppTheme.primary,
                  child: const Text(
                    'Add to Collection',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
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
                  onPressed: _onAddToWishlist,
                  style: AdaptiveButtonStyle.bordered,
                  color: AppTheme.primary,
                  padding: ChromeMetrics.adaptiveBorderedButtonPadding,
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.favorite_border,
                            size: 18, color: AppTheme.primary),
                        SizedBox(width: 8),
                        Text('Add to Wishlist'),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildCatalogBody(
    BuildContext context,
    ColorScheme colors,
    double topInset,
    double bottomPad,
  ) {
    if (_guideSyncDebugJson != null) {
      return _buildGuideSyncDebugPane(context, colors);
    }
    return _buildDetailListView(context, colors, topInset, bottomPad);
  }

  Widget _buildDetailLoadingPane(BuildContext context, ColorScheme colors) {
    return Material(
      color: colors.surface,
      child: const Center(child: CardFanLoader(size: 72)),
    );
  }

  Widget _buildValueSection(
    BuildContext context,
    ColorScheme colors,
    UserCard card,
    bool hasValue,
    double? pl,
    double? plPct,
  ) {
    return Semantics(
      container: true,
      label: 'Value and profit or loss',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DetailSectionHeader('Value'),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _InfoBox(
                  label: 'Current Value',
                  value: hasValue ? formatUsd(card.displayValue!) : 'N/A',
                  trend: hasValue ? card.valueTrendForDisplay : 0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _PlCard(pl: pl, plPct: plPct)),
            ],
          ),
          const SizedBox(height: 8),
          if (hasValue)
            _ValueRefreshNotice(
              refreshedAt: card.displayValueRefreshedAt,
              relativeRefreshed: _relativeRefreshed,
              marketGuideHeadline: card.headlineValueUsesGuidePrices,
            )
          else
            InlineNoticeContainer(
              icon: Icon(Icons.info_outline,
                  size: 20, color: colors.onSurface.withValues(alpha: 0.60)),
              child: Text(
                _missingCatalogValueNotice(card),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      height: 1.35,
                      color: colors.onSurface.withValues(alpha: 0.75),
                    ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildYourCopySection(BuildContext context, UserCard card) {
    return Semantics(
      container: true,
      label: 'Your copy of this card',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DetailSectionHeader('Your copy'),
          const SizedBox(height: 16),
          DetailPropertyTile(label: 'Parallel', value: card.parallel),
          const SizedBox(height: 8),
          DetailPropertyTile(label: 'Price paid', value: formatUsd(card.pricePaid ?? 0)),
          if (card.serialNumber != null || card.serialMax != null) ...[
            const SizedBox(height: 8),
            DetailPropertyTile(
              label: 'Serial #',
              value: card.serialNumber != null && card.serialMax != null
                  ? '${card.serialNumber}/${card.serialMax}'
                  : card.serialMax != null
                      ? '/${card.serialMax}'
                      : card.serialNumber!,
            ),
          ],
          if (card.isGraded) ...[
            const SizedBox(height: 8),
            DetailPropertyTile(
              label: 'Grade',
              value: '${card.grader ?? 'PSA'} ${card.grade ?? ''}'.trim(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMarketSection(
    BuildContext context,
    ColorScheme colors, {
    UserCard? card,
    MasterCard? masterCard,
    String? guidePriceCardId,
    Map<String, double?>? guideRecentPrices,
    bool hasUsableGuidePrices = false,
    bool hasGuideCatalogLink = false,
    double? titleGain,
  }) {
    final String masterId;
    final String initialGrade;
    final String? guideId;
    final Map<String, double?>? recentPrices;
    final bool skipScraper;
    final bool showDbComps;
    final double? gain;

    if (card != null) {
      masterId = card.masterCardId ?? '';
      initialGrade = _resolveDefaultGrade(card);
      guideId = card.embeddedMasterGuideCardId;
      recentPrices = card.hasUsableGuideGradePricesForMarket
          ? card.guideGradePricesForMarketSection
          : null;
      skipScraper = card.hasUsableGuideGradePricesForMarket;
      showDbComps = card.hasUsableGuideGradePricesForMarket;
      gain = card.masterDefinitionGain;
    } else {
      masterId = masterCard!.id;
      initialGrade = 'Raw';
      guideId = guidePriceCardId;
      recentPrices = guideRecentPrices;
      skipScraper = true;
      showDbComps = hasUsableGuidePrices || hasGuideCatalogLink;
      gain = titleGain;
    }

    if (masterId.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'No catalog link — market data unavailable.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onSurface.withValues(alpha: 0.60),
              ),
        ),
      );
    }

    if (_isCatalog && !hasGuideCatalogLink) {
      if (!_guidePricesLoading && _guideSyncDebugJson == null) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            PriceGuideCopy.marketDataWhenMatched,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.60),
                ),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return MarketAnalysisSection(
      key: ValueKey('market-$masterId-${guideId ?? ''}'),
      masterCardId: masterId,
      initialGrade: initialGrade,
      segmentColor: colors.primary,
      guidePriceCardId: guideId,
      guideRecentPrices: recentPrices,
      skipScraperSoldComps: skipScraper,
      showDbSoldCompsWhenAvailable: showDbComps,
      titleGain: gain,
      soldCompsCompactPrompt: card == null,
    );
  }

  Widget _buildGuideSyncDebugPane(BuildContext context, ColorScheme colors) {
      return Material(
          color: colors.surface,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    PriceGuideCopy.debugLookupTitle,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    PriceGuideCopy.debugRequestJsonLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurface.withValues(alpha: 0.65),
                        ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colors.outline.withValues(alpha: 0.35),
                        ),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(10),
                        child: SelectableText(
                          _guideSyncDebugJson!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontFamily: 'Menlo',
                                fontFamilyFallback: const ['Courier', 'monospace'],
                                fontSize: 11,
                                height: 1.35,
                              ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AdaptiveButton.child(
                    onPressed: () {
                      setState(() {
                        _guidePricesLoading = true;
                        _guideSyncDebugJson = null;
                      });
                      unawaited(_bootstrapCatalogDetail());
                    },
                    style: AdaptiveButtonStyle.filled,
                    color: AppTheme.primary,
                    child: const Text(
                      PriceGuideCopy.debugRetryLookup,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
  }
}

class _PlCard extends StatelessWidget {
  const _PlCard({required this.pl, required this.plPct});

  final double? pl;
  final double? plPct;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasValue = pl != null && plPct != null;
    final positive = hasValue ? pl! >= 0 : true;
    final accent = positive ? _detailProfitColor(context) : colors.error;

    return AdaptiveListCard(
      margin: EdgeInsets.zero,
      cornerRadius: 12,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('P/L', style: _detailMetaLabelStyle(context)),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  hasValue ? formatUsdSigned(pl!) : 'N/A',
                  style: _detailValueEmphasisStyle(context)?.copyWith(color: accent),
                ),
                Text(
                  hasValue ? '${plPct!.toStringAsFixed(1)}%' : 'N/A',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ValueRefreshNotice extends StatelessWidget {
  const _ValueRefreshNotice({
    required this.refreshedAt,
    required this.relativeRefreshed,
    this.marketGuideHeadline = false,
  });

  final DateTime? refreshedAt;
  final String Function(DateTime) relativeRefreshed;
  /// When true, [refreshedAt] reflects guide-price / `current_prices`, not sold-comps refresh.
  final bool marketGuideHeadline;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final t = refreshedAt;
    final text = t != null
        ? (marketGuideHeadline
            ? PriceGuideCopy.priceGuideLastUpdated(relativeRefreshed(t), _fmtClock(t))
            : 'Sold comps value last refreshed ${relativeRefreshed(t)} · ${_fmtClock(t)}')
        : (marketGuideHeadline
            ? PriceGuideCopy.noPriceGuideTimestamp
            : 'Value has not been refreshed yet — open Edit or pull collection refresh when available.');

    final theme = Theme.of(context);
    return Semantics(
      label: text,
      child: InlineNoticeContainer(
        icon: Icon(Icons.schedule, size: 20, color: colors.onSurface.withValues(alpha: 0.60)),
        child: Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            height: 1.35,
            color: colors.onSurface.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }

  String _fmtClock(DateTime t) {
    final l = t.toLocal();
    final h = l.hour > 12 ? l.hour - 12 : (l.hour == 0 ? 12 : l.hour);
    final am = l.hour >= 12 ? 'PM' : 'AM';
    return '${l.month}/${l.day}/${l.year} $h:${l.minute.toString().padLeft(2, '0')} $am';
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.label, required this.value, this.trend = 0});
  final String label;
  final String value;
  final int trend;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AdaptiveListCard(
      margin: EdgeInsets.zero,
      cornerRadius: 12,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: _detailMetaLabelStyle(context)),
            const SizedBox(height: 4),
            Row(
              children: [
                if (trend != 0) ...[
                  Icon(
                    trend > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 16,
                    semanticLabel: trend > 0 ? 'Trending up' : 'Trending down',
                    color: trend > 0 ? _detailProfitColor(context) : colors.error,
                  ),
                  const SizedBox(width: 2),
                ],
                Text(value, style: _detailValueEmphasisStyle(context)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Edit-sheet helpers (mirrors the catalog Add-to-Collection sheet) ────────

class _SheetFieldLabel extends StatelessWidget {
  const _SheetFieldLabel(this.label) : _inline = false;
  const _SheetFieldLabel.inline(this.label) : _inline = true;

  final String label;
  final bool _inline;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final inputTheme = Theme.of(context).inputDecorationTheme;
    final baseStyle = inputTheme.labelStyle ?? textTheme.bodySmall ?? const TextStyle(fontSize: 12);
    final style = baseStyle.copyWith(
      color: colors.onSurface.withValues(alpha: 0.65),
      fontWeight: FontWeight.w600,
    );
    if (_inline) {
      return Text(label, style: style);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(label, style: style),
    );
  }
}

class _EditCardPreview extends StatelessWidget {
  const _EditCardPreview({required this.card});

  final UserCard card;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AdaptiveListCard(
      margin: EdgeInsets.zero,
      cornerRadius: 12,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: card.player,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                if (card.cardNumber != null)
                  TextSpan(
                    text: '  #${card.cardNumber}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: colors.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            if (card.year != null || card.set != null || card.checklist != null)
              Text(
                [
                  if (card.year != null) '${card.year}',
                  if (card.set != null) card.set,
                  if (card.checklist != null && card.checklist != card.set) card.checklist,
                ].join(' · '),
                style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.6)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (card.parallel != 'Base')
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  card.parallel,
                  style: TextStyle(fontSize: 12, color: colors.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 8),
            CardAttributesWrap(
              rookie: card.rookie,
              autograph: card.autograph,
              memorabilia: card.memorabilia,
              ssp: card.ssp,
              serialMax: card.serialMax,
            ),
          ],
        ),
      ),
    );
  }
}

