import 'dart:async';
import 'dart:convert';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/cards_service.dart';
import '../../core/services/comps_service.dart';
import '../../core/utils/adaptive_ui.dart';
import '../../core/utils/usd_field.dart';
import '../../core/widgets/attr_tag.dart';
import '../../core/widgets/card_attributes_wrap.dart';
import '../../core/widgets/info_box.dart';
import '../../core/widgets/card_fan_loader.dart';
import '../../core/theme/chrome_metrics.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/fonts.dart';
import '../../core/widgets/app_bar_action_capsule.dart';
import '../../core/widgets/app_bar_shell_trailing_actions.dart';
import '../../core/widgets/app_segmented_control.dart';
import '../../core/widgets/adaptive_dropdown.dart';
import '../../core/widgets/glass_nav_bar.dart';
import '../../core/widgets/glass_search_field.dart';
import '../../core/widgets/sticky_chrome_scaffold.dart';
import '../wishlist/wishlist_screen.dart' show wishlistProvider;
import '../wishlist/card_sheet.dart';
import '../scan/scan_catalog_bridge.dart';
import '../scan/scan_models.dart';
import 'master_card_detail_screen.dart';
import 'widgets/active_state_indicator.dart';
import 'widgets/card_detail_view.dart';
import 'widgets/card_comps_section.dart';
import 'widgets/filter_sort_action_bar.dart';

/// First-frame hints for [StickyChromeScaffold.stickyHeightEstimate] until layout measures.
const double _kStickyEstSegment = 52;
const double _kStickyEstBrowsePlus = 118;
const double _kStickyEstSetSearch =
    ChromeMetrics.searchBarSecondaryTopInset +
    ChromeMetrics.searchHeaderExtent +
    ChromeMetrics.searchBarBottomInset;
const double _kStickyEstCardSearch = _kStickyEstSetSearch;
const double _kStickyEstGlobalSearch =
    ChromeMetrics.searchBarSecondaryTopInset +
    ChromeMetrics.searchHeaderExtent +
    ChromeMetrics.searchBarBottomInset;

// Persisted navigation state (browse only)
class _CatalogNavState {
  final _CatalogStep step;
  final String browseSearchQuery;
  final String browseFilterYear;
  final String browseFilterSport;
  final String setSearchQuery;
  final String? selectedReleaseId;
  final String? selectedSetId;
  final String? selectedCardId;

  _CatalogNavState({
    required this.step,
    this.browseSearchQuery = '',
    this.browseFilterYear = '',
    this.browseFilterSport = '',
    this.setSearchQuery = '',
    this.selectedReleaseId,
    this.selectedSetId,
    this.selectedCardId,
  });

  Map<String, dynamic> toJson() {
    return {
      'step': step.index,
      'browseSearchQuery': browseSearchQuery,
      'browseFilterYear': browseFilterYear,
      'browseFilterSport': browseFilterSport,
      'setSearchQuery': setSearchQuery,
      'selectedReleaseId': selectedReleaseId,
      'selectedSetId': selectedSetId,
      'selectedCardId': selectedCardId,
    };
  }

  static _CatalogNavState? fromJson(Map<String, dynamic> json) {
    try {
      return _CatalogNavState(
        step: _CatalogStep.values[json['step'] as int? ?? 0],
        browseSearchQuery: json['browseSearchQuery'] as String? ?? '',
        browseFilterYear: json['browseFilterYear'] as String? ?? '',
        browseFilterSport: json['browseFilterSport'] as String? ?? '',
        setSearchQuery: json['setSearchQuery'] as String? ?? '',
        selectedReleaseId: json['selectedReleaseId'] as String?,
        selectedSetId: json['selectedSetId'] as String?,
        selectedCardId: json['selectedCardId'] as String?,
      );
    } catch (e) {
      return null;
    }
  }
}

const _addCardNavStateKey = 'add_card_nav_state';

/// Resolves a [set_card_base_variants] row id + optional [set_parallels] id to the
/// per-parallel `master_card_definitions` id (same as [CardsService.ensureCatalogVariant]).
class CatalogBrowseVariantKey {
  const CatalogBrowseVariantKey({required this.baseMasterId, required this.parallelId});
  final String baseMasterId;
  final String? parallelId;

  @override
  bool operator ==(Object other) =>
      other is CatalogBrowseVariantKey &&
      other.baseMasterId == baseMasterId &&
      other.parallelId == parallelId;

  @override
  int get hashCode => Object.hash(baseMasterId, parallelId);
}

final catalogBrowseResolvedMasterIdProvider =
    FutureProvider.family<String, CatalogBrowseVariantKey>((ref, key) async {
  return ref.watch(cardsServiceProvider).ensureCatalogVariant(
        catalogVariantId: key.baseMasterId,
        parallelId: key.parallelId,
      );
    });

const _graders = ['PSA', 'BGS', 'SGC', 'CGC', 'CSG'];

const _catalogYears = [
  '2026', '2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018', '2017',
];

enum _CatalogStep { sportPicker, browsing, sets, card, parallel, detail, addCopy }
enum _CatalogMode { browse, search }

/// When set, catalog opens on the card detail step (e.g. after a scan).
class CatalogScanEntry {
  const CatalogScanEntry({required this.detection, required this.sport});
  final ImageScanMatchResult detection;
  final String sport;
}

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key, this.scanEntry});
  final CatalogScanEntry? scanEntry;

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> with WidgetsBindingObserver {
  // ── Catalog mode (Browse vs Search) ──────────────────────────
  _CatalogMode _mode = _CatalogMode.browse;

  // ── Global search state ──────────────────────────────────────
  final _globalSearchCtrl = TextEditingController();
  List<dynamic> _globalSearchResults = [];
  bool _globalSearchLoading = false;
  Timer? _searchDebounceTimer;
  MasterCard? _searchSelectedCard;
  SetRecord? _searchSelectedSet;
  ReleaseRecord? _searchSelectedRelease;
  List<SetParallel> _searchParallels = [];
  SetParallel? _searchSelectedParallel;
  String _searchParallelName = 'Base';
  bool _searchParallelSelected = false;
  bool _searchParallelsLoading = false;

  // ── Catalog step ─────────────────────────────────────────────
  _CatalogStep _catalogStep = _CatalogStep.sportPicker;
  String _catalogFilterYear = '';
  String _catalogFilterSport = '';
  final _browseSearchCtrl = TextEditingController();
  bool _restoringState = true;

  // ── Browse step (release list) ───────────────────────────────
  List<ReleaseRecord> _browseResults = [];
  bool _browseLoading = false;
  bool _browseHasMore = false;
  int _browseOffset = 0;
  static const int _browsePageSize = 30;

  // ── Sets step ────────────────────────────────────────────────
  ReleaseRecord? _browseSelectedRelease;
  List<SetRecord> _browseSets = [];
  bool _browseSetsLoading = false;
  bool _lazyImporting = false;
  final _setSearchCtrl = TextEditingController();

  // ── Card step: Release + Set (set after browsing) ────────────
  ReleaseRecord? _selectedRelease;
  SetRecord? _selectedSet;

  // ── Step 3: Card ─────────────────────────────────────────────
  final _cardCtrl = TextEditingController();
  List<MasterCard> _cardResults = [];
  List<MasterCard> _allCards = [];
  MasterCard? _selectedCard;
  bool _isNewCard = false;

  // ── New card fields ──────────────────────────────────────────
  final _newPlayerCtrl = TextEditingController();
  final _newCardNumberCtrl = TextEditingController();
  final _newSerialMaxCtrl = TextEditingController();
  bool _newIsRookie = false;
  bool _newIsAuto = false;
  bool _newIsPatch = false;
  bool _newIsSSP = false;

  // ── Your Copy ────────────────────────────────────────────────
  List<SetParallel> _parallels = [];
  final _loadingParallels = false;
  SetParallel? _selectedParallel;
  String _parallelName = 'Base';
  final _pricePaidCtrl = TextEditingController();
  final _serialNumberCtrl = TextEditingController();
  final _targetPriceCtrl = TextEditingController();
  bool _isGraded = false;
  String _grader = 'PSA';
  final _gradeValueCtrl = TextEditingController();
  final _pricePaidUsdFormatter = createUsdCurrencyInputFormatter();

  bool _saving = false;

  /// While true, scan-driven catalog opens show [CardFanLoader] instead of browse
  /// steps until resolve finishes or partial flow reveals the catalog UI.
  bool _scanResolving = false;

  /// Copy of [CatalogScreen.scanEntry] captured in [initState] (and updated when
  /// reopening from [didUpdateWidget]). Post-frame work must not read
  /// `widget.scanEntry` alone: GoRouter can rebuild this route without `extra`
  /// for a frame, which would wrongly run [_restoreNavigationState] and flash
  /// the browse catalog before scan resolve runs.
  CatalogScanEntry? _scanBootstrapEntry;

  @override
  void initState() {
    super.initState();
    // Opening from scan: show loader until [_openCatalogFromScan] opens master
    // (full path) or hands off to partial browse. Do not use `_restoringState`
    // here — that path is for prefs restore and would block initState re-runs.
    _scanBootstrapEntry = widget.scanEntry;
    if (_scanBootstrapEntry != null) {
      _restoringState = false;
      _scanResolving = true;
    }
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_scanBootstrapEntry != null) {
        final e = _scanBootstrapEntry!;
        await _openCatalogFromScan(e.detection, e.sport);
        return;
      }
      await _restoreNavigationState();
    });
  }

  @override
  void didUpdateWidget(covariant CatalogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_shouldReopenScanEntry(oldWidget.scanEntry, widget.scanEntry)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || widget.scanEntry == null) return;
      setState(() {
        _scanBootstrapEntry = widget.scanEntry;
        _scanResolving = true;
      });
      await _openCatalogFromScan(widget.scanEntry!.detection, widget.scanEntry!.sport);
    });
  }

  /// New scan `extra` while [CatalogScreen] is still mounted (same route, new args).
  bool _shouldReopenScanEntry(CatalogScanEntry? oldE, CatalogScanEntry? newE) {
    if (newE == null) return false;
    if (oldE == null) return true;
    if (oldE.sport != newE.sport) return true;
    final a = oldE.detection.card;
    final b = newE.detection.card;
    if (a.id != b.id || a.releaseId != b.releaseId || a.setId != b.setId) return true;
    if (a.name != b.name || a.number != b.number) return true;
    if (oldE.detection.confidence != newE.detection.confidence) return true;
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Removed - no longer saving search state
  }

  Future<void> _restoreNavigationState() async {
    if (!mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stateJson = prefs.getString(_addCardNavStateKey);
      if (stateJson != null) {
        final saved = _CatalogNavState.fromJson(jsonDecode(stateJson) as Map<String, dynamic>);
        if (saved != null && mounted) {
          setState(() {
            _catalogStep = saved.step;
            _browseSearchCtrl.text = saved.browseSearchQuery;
            _catalogFilterYear = saved.browseFilterYear;
            _catalogFilterSport = saved.browseFilterSport;
            _setSearchCtrl.text = saved.setSearchQuery;
          });

          // Load data based on which step we're restoring to
          if (saved.step == _CatalogStep.browsing) {
            // If restoring to browsing but no sport is selected, go back to sportPicker
            if (saved.browseFilterSport.isEmpty) {
              if (mounted) {
                setState(() => _catalogStep = _CatalogStep.sportPicker);
              }
            } else {
              await _loadBrowseReleases(reset: true);
            }
          } else if ((saved.step == _CatalogStep.sets || saved.step == _CatalogStep.card || saved.step == _CatalogStep.parallel || saved.step == _CatalogStep.detail) &&
                     saved.selectedReleaseId != null) {
            // Reload the selected release and its sets
            try {
              final releases = await ref.read(cardsServiceProvider).browseReleases(offset: 0, limit: 1000);
              final release = releases.firstWhere((r) => r.id == saved.selectedReleaseId!);

              if (mounted) {
                setState(() {
                  _browseSelectedRelease = release;
                  _selectedRelease = release;
                });

                // Load sets for this release
                await _selectBrowseRelease(release);

                // If restoring to card, parallel, or detail, load the set and cards
                if ((saved.step == _CatalogStep.card || saved.step == _CatalogStep.parallel || saved.step == _CatalogStep.detail) &&
                    saved.selectedSetId != null && _browseSets.isNotEmpty) {
                  final set = _browseSets.firstWhere((s) => s.id == saved.selectedSetId!);
                  await _selectBrowseSet(set);

                  // If restoring to parallel or detail, re-select the card
                  if ((saved.step == _CatalogStep.parallel || saved.step == _CatalogStep.detail) &&
                      saved.selectedCardId != null &&
                      _allCards.isNotEmpty) {
                    final match = _allCards.where((c) => c.id == saved.selectedCardId!).firstOrNull;
                    if (match != null) _selectCard(match);
                  }
                }
              }
            } catch (_) {
              if (mounted) await _loadBrowseReleases(reset: true);
            }
          } else {
            await _loadBrowseReleases(reset: true);
          }
          if (mounted) {
            setState(() => _restoringState = false);
          }
          return;
        }
      }
    } catch (_) {
      // Ignore restore errors
    }
    if (mounted) {
      await _loadBrowseReleases(reset: true);
      setState(() => _restoringState = false);
    }
  }

  /// Scan flow sends lowercase slugs (e.g. `basketball`); browse filters use catalog labels.
  String _catalogSportFromScanSlug(String scanSport) {
    switch (scanSport.trim().toLowerCase()) {
      case 'baseball':
        return 'Baseball';
      case 'basketball':
        return 'Basketball';
      case 'football':
        return 'Football';
      case 'hockey':
        return 'Hockey';
      case 'soccer':
        return 'Soccer';
      default:
        if (scanSport.isEmpty) return scanSport;
        return '${scanSport[0].toUpperCase()}${scanSport.substring(1).toLowerCase()}';
    }
  }

  String _releaseHintFromCard(ScannedCatalogCard card) {
    final rn = card.releaseName?.trim();
    if (rn != null && rn.isNotEmpty) return rn;
    final m = card.manufacturer?.trim();
    if (m != null && m.isNotEmpty) return m;
    return '';
  }

  String _normScanText(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  int _scoreReleaseForScan(ReleaseRecord r, {required String hint, required int? year}) {
    var score = 0;
    if (year != null && r.year == year) score += 16;
    if (hint.isEmpty) return score;
    final rn = _normScanText(r.name);
    final hn = _normScanText(hint);
    if (hn.isEmpty) return score;
    if (rn == hn) return score + 100;
    if (rn.contains(hn) || hn.contains(rn)) return score + 65;
    final rtoks = rn.split(' ').where((t) => t.length > 1).toSet();
    final htoks = hn.split(' ').where((t) => t.length > 1).toSet();
    score += rtoks.intersection(htoks).length * 10;
    return score;
  }

  int _scoreSetForScan(SetRecord s, String setHint) {
    final hn = _normScanText(setHint);
    if (hn.isEmpty) return 0;
    final sn = _normScanText(s.name);
    if (sn.isEmpty) return 0;
    if (sn == hn) return 100;
    if (sn.contains(hn) || hn.contains(sn)) return 70;
    final st = sn.split(' ').where((t) => t.length > 1).toSet();
    final ht = hn.split(' ').where((t) => t.length > 1).toSet();
    return st.intersection(ht).length * 12;
  }

  /// When CardSight returns metadata but no checklist UUIDs, resolve release/set by name
  /// and land on the checklist (or sets search) instead of restoring stale prefs.
  Future<void> _openCatalogFromScanPartial(
    ImageScanMatchResult detection,
    String scanSport,
  ) async {
    if (!mounted) return;
    await _clearNavigationState();
    if (!mounted) return;

    final card = detection.card;
    final catalogSport = _catalogSportFromScanSlug(scanSport);
    final year = int.tryParse(card.year ?? '');
    final releaseHint = _releaseHintFromCard(card);
    final setHint = card.setName?.trim() ?? '';

    setState(() {
      _restoringState = false;
      _scanResolving = false;
      _scanBootstrapEntry = null;
      _mode = _CatalogMode.browse;
      _catalogFilterSport = catalogSport;
      _catalogFilterYear = card.year?.trim() ?? '';
      _browseSearchCtrl.text = releaseHint;
      _setSearchCtrl.clear();
      _catalogStep = _CatalogStep.browsing;
      _browseSelectedRelease = null;
      _selectedRelease = null;
      _browseSets = [];
      _selectedSet = null;
      _browseResults = [];
      _browseOffset = 0;
      _browseHasMore = false;
    });

    final svc = ref.read(cardsServiceProvider);
    ReleaseRecord? resolvedRelease;
    var bestReleaseScore = 0;
    var resolvedFromSearch = false;
    List<ReleaseRecord> searchCandidates = [];

    if (releaseHint.isNotEmpty) {
      searchCandidates = await svc.searchReleases(releaseHint);
      searchCandidates = searchCandidates
          .where(
            (r) =>
                r.sport == null ||
                r.sport!.toLowerCase() == catalogSport.toLowerCase(),
          )
          .toList();
      if (year != null) {
        final byYear = searchCandidates.where((r) => r.year == year).toList();
        if (byYear.isNotEmpty) searchCandidates = byYear;
      }
      for (final r in searchCandidates) {
        final sc = _scoreReleaseForScan(r, hint: releaseHint, year: year);
        if (sc > bestReleaseScore) {
          bestReleaseScore = sc;
          resolvedRelease = r;
        }
      }
      if (bestReleaseScore < 28) {
        resolvedRelease = null;
        bestReleaseScore = 0;
      } else {
        resolvedFromSearch = true;
      }
    }

    if (resolvedRelease == null) {
      await _loadBrowseReleases(reset: true);
      if (!mounted) return;
      bestReleaseScore = 0;
      for (final r in _browseResults) {
        final sc = _scoreReleaseForScan(r, hint: releaseHint, year: year);
        if (sc > bestReleaseScore) {
          bestReleaseScore = sc;
          resolvedRelease = r;
        }
      }
      var pages = 0;
      while (mounted && bestReleaseScore < 28 && _browseHasMore && pages < 6) {
        pages++;
        await _loadBrowseReleases();
        if (!mounted) return;
        for (final r in _browseResults) {
          final sc = _scoreReleaseForScan(r, hint: releaseHint, year: year);
          if (sc > bestReleaseScore) {
            bestReleaseScore = sc;
            resolvedRelease = r;
          }
        }
      }
      if (bestReleaseScore < 22) resolvedRelease = null;
    }

    if (resolvedRelease != null && resolvedFromSearch && searchCandidates.isNotEmpty) {
      setState(() => _browseResults = List<ReleaseRecord>.from(searchCandidates));
    }

    if (resolvedRelease != null) {
      await _selectBrowseRelease(resolvedRelease);
      if (!mounted) return;

      if (_browseSets.isEmpty) {
        if (mounted) {
          AdaptiveSnackBar.show(
            context,
            message:
                'Found the release, but no sets are available yet. Try again after this release is imported.',
            type: AdaptiveSnackBarType.info,
          );
          unawaited(_saveNavigationState());
        }
        return;
      }

      SetRecord? bestSet;
      var bestSetScore = 0;
      if (setHint.isNotEmpty) {
        for (final s in _browseSets) {
          final sc = _scoreSetForScan(s, setHint);
          if (sc > bestSetScore) {
            bestSetScore = sc;
            bestSet = s;
          }
        }
      }

      if (bestSet != null && bestSetScore >= 32) {
        await _selectBrowseSet(bestSet);
        if (!mounted) return;

        final nameQ = (card.name?.trim().isNotEmpty == true) ? card.name!.trim() : '';
        final numQ = (card.number?.trim().isNotEmpty == true) ? card.number!.trim() : '';
        final primaryQ = nameQ.isNotEmpty ? nameQ : numQ;
        setState(() {
          _cardCtrl.text = primaryQ;
        });
        _searchCards(primaryQ);

        final scanParallel = card.parallel;
        final matchedParallel = pickCatalogParallel(
          parallels: _parallels,
          scanParallel: scanParallel,
          cardHedgeVariant: detection.cardHedgeVariant,
        );
        final label = catalogParallelDisplayLabel(
          resolved: matchedParallel,
          scanParallel: scanParallel,
          cardHedgeVariant: detection.cardHedgeVariant,
        );
        setState(() {
          _selectedParallel = matchedParallel;
          _parallelName = label;
        });

        if (mounted) {
          AdaptiveSnackBar.show(
            context,
            message: nameQ.isEmpty
                ? 'Opened this set from your scan. Search by player or card # to finish.'
                : 'Opened this set from your scan. Pick your card from the list or refine search.',
            type: AdaptiveSnackBarType.info,
          );
        }
      } else {
        setState(() {
          _setSearchCtrl.text = setHint;
        });
        if (mounted) {
          AdaptiveSnackBar.show(
            context,
            message:
                'Choose the set that matches your card, then search the checklist.',
            type: AdaptiveSnackBarType.info,
          );
        }
      }
    } else {
      await _loadBrowseReleases(reset: true);
      if (mounted) {
        AdaptiveSnackBar.show(
          context,
          message:
              'Could not match this scan to a catalog release. Try search or adjust year/sport filters.',
          type: AdaptiveSnackBarType.info,
        );
      }
    }

    if (mounted) unawaited(_saveNavigationState());
  }

  Future<void> _openCatalogFromScan(ImageScanMatchResult detection, String sport) async {
    if (!mounted) return;
    final card = detection.card;
    if (card.id == null || card.id!.trim().isEmpty) {
      await _openCatalogFromScanPartial(detection, sport);
      return;
    }

    final vaultRelease = card.releaseId?.trim();
    final vaultSet = card.setId?.trim();
    final hasVaultPair =
        (vaultRelease?.isNotEmpty ?? false) && (vaultSet?.isNotEmpty ?? false);
    final spineRelease = card.cardsightReleaseId?.trim();
    final spineSet = card.cardsightSetId?.trim();
    final hasSpinePair =
        (spineRelease?.isNotEmpty ?? false) && (spineSet?.isNotEmpty ?? false);

    if (!hasVaultPair && !hasSpinePair) {
      await _openCatalogFromScanPartial(detection, sport);
      return;
    }

    try {
      final svc = ref.read(cardsServiceProvider);
      final scanId = card.id!.trim();
      final year = int.tryParse(card.year ?? '') ?? DateTime.now().year;
      final releaseName = (card.releaseName?.trim().isNotEmpty == true)
          ? card.releaseName!
          : (card.manufacturer ?? 'Unknown Release');

      final catalogReleaseId = hasVaultPair ? vaultRelease! : spineRelease!;
      final catalogSetId = hasVaultPair ? vaultSet! : spineSet!;

      final csResult = CatalogSearchCardResult(
        id: scanId,
        name: card.name ?? '',
        number: card.number,
        setId: catalogSetId,
        setName: card.setName ?? '',
        releaseId: catalogReleaseId,
        attributes: const [],
      );

      final resolved = await svc.resolveCardFromCatalog(
        card: csResult,
        releaseName: releaseName,
        releaseYear: year,
        releaseSegmentId: card.segmentId ?? '',
      );

      final rs = await svc.getReleaseAndSetForSetId(resolved.setId);
      final release = rs.release;
      final set = rs.set;

      final master = MasterCard(
        id: resolved.masterCardId,
        player: (card.name ?? '').trim(),
        cardNumber: (card.number?.trim().isNotEmpty == true) ? card.number : null,
        imageUrl: (card.imageUrl?.trim().isNotEmpty == true) ? card.imageUrl : null,
      );

      final scanParallel = card.parallel;
      final matchedParallel = pickCatalogParallel(
        parallels: resolved.parallels,
        scanParallel: scanParallel,
        cardHedgeVariant: detection.cardHedgeVariant,
      );
      final parallelLabel = catalogParallelDisplayLabel(
        resolved: matchedParallel,
        scanParallel: scanParallel,
        cardHedgeVariant: detection.cardHedgeVariant,
      );
      SetParallel? effectiveParallel = matchedParallel;
      if (matchedParallel != null &&
          scanParallel != null &&
          matchedParallel.serialMax == null &&
          scanParallel.numberedTo != null) {
        effectiveParallel = SetParallel(
          id: matchedParallel.id,
          name: matchedParallel.name,
          serialMax: scanParallel.numberedTo,
          isAuto: matchedParallel.isAuto,
        );
      }

      if (!mounted) return;
      final resolvedVariantId = await svc.ensureCatalogVariant(
        catalogVariantId: master.id,
        parallelId: effectiveParallel?.id,
      );
      if (!mounted) return;
      final chId = detection.cardHedgeCardId?.trim();
      if (chId != null && chId.isNotEmpty) {
        await ref.read(compsServiceProvider).persistCardHedgeHydratedFromCardId(
              masterVariantId: resolvedVariantId,
              guidePriceCardId: chId,
            );
      }
      if (!mounted) return;
      unawaited(ref.read(compsServiceProvider).fetchCardImage(resolvedVariantId));
      await _openMasterCardDetail(
        card: master,
        parallelName: parallelLabel,
        parallel: effectiveParallel,
        release: release,
        set: set,
        openedFromScanResults: true,
      );
    } catch (_) {
      if (mounted) {
        AdaptiveSnackBar.show(
          context,
          message: 'Could not open this card in the catalog. Try browsing manually.',
          type: AdaptiveSnackBarType.error,
        );
        await _restoreNavigationState();
        setState(() {
          _scanBootstrapEntry = null;
          _scanResolving = false;
        });
      }
    } finally {
      if (mounted && _scanBootstrapEntry != null) {
        setState(() {
          _scanResolving = false;
          _scanBootstrapEntry = null;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_saveNavigationState());
    _searchDebounceTimer?.cancel();
    _browseSearchCtrl.dispose();
    _setSearchCtrl.dispose();
    _cardCtrl.dispose();
    _newPlayerCtrl.dispose();
    _newCardNumberCtrl.dispose();
    _newSerialMaxCtrl.dispose();
    _pricePaidCtrl.dispose();
    _serialNumberCtrl.dispose();
    _targetPriceCtrl.dispose();
    _gradeValueCtrl.dispose();
    _globalSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveNavigationState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final state = _CatalogNavState(
        step: _catalogStep,
        browseSearchQuery: _browseSearchCtrl.text,
        browseFilterYear: _catalogFilterYear,
        browseFilterSport: _catalogFilterSport,
        setSearchQuery: _setSearchCtrl.text,
        selectedReleaseId: _browseSelectedRelease?.id ?? _selectedRelease?.id,
        selectedSetId: _selectedSet?.id,
        selectedCardId: _selectedCard?.id,
      );
      final json = jsonEncode(state.toJson());
      await prefs.setString(_addCardNavStateKey, json);
    } catch (_) {
    }
  }

  Future<void> _clearNavigationState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_addCardNavStateKey);
    } catch (e) {
      // Silently fail
    }
  }

  // ── Browse step methods ───────────────────────────────────────

  Future<void> _loadBrowseReleases({bool reset = false}) async {
    if (reset) setState(() { _browseOffset = 0; _browseResults = []; });
    setState(() => _browseLoading = true);
    try {
      final year = _catalogFilterYear.isNotEmpty ? int.tryParse(_catalogFilterYear) : null;
      final sport = _catalogFilterSport.isNotEmpty ? _catalogFilterSport : null;
      final results = await ref.read(cardsServiceProvider).browseReleases(
        year: year,
        sport: sport,
        offset: _browseOffset,
        limit: _browsePageSize,
      );
      setState(() {
        _browseResults = reset ? results : [..._browseResults, ...results];
        _browseHasMore = results.length == _browsePageSize;
        _browseOffset = _browseResults.length;
      });
    } finally {
      setState(() => _browseLoading = false);
    }
  }

  Future<void> _selectBrowseRelease(ReleaseRecord release) async {
    setState(() {
      _browseSelectedRelease = release;
      _catalogStep = _CatalogStep.sets;
      _browseSets = [];
      _browseSetsLoading = true;
    });
    unawaited(_saveNavigationState());
    try {
      final existing = await ref.read(cardsServiceProvider).getSetsForRelease(release.id);
      if (existing.isNotEmpty) {
        setState(() => _browseSets = existing);
      } else if (release.catalogImportReleaseKey != null) {
        await ref.read(cardsServiceProvider).importSetsForRelease(
          cardsightReleaseId: release.catalogImportReleaseKey!,
          releaseName: release.name,
          releaseYear: release.year?.toString(),
        );
        final fresh = await ref.read(cardsServiceProvider).getSetsForRelease(release.id);
        setState(() => _browseSets = fresh);
      }
    } catch (e) {
      if (mounted) {
        AdaptiveSnackBar.show(context, message: 'Failed to load sets: $e', type: AdaptiveSnackBarType.error);
        setState(() => _catalogStep = _CatalogStep.browsing);
      }
    } finally {
      if (mounted) setState(() => _browseSetsLoading = false);
    }
  }

  Future<void> _selectBrowseSet(SetRecord set) async {
    final release = _browseSelectedRelease!;
    setState(() => _lazyImporting = true);
    try {
      // Lazy-load parallels if needed
      var parallels = await ref.read(cardsServiceProvider).getParallels(set.id);
      if (parallels.isEmpty && set.catalogImportSetKey != null) {
        final result = await ref.read(cardsServiceProvider).lazyImportCatalog(
          cardsightReleaseId: release.catalogImportReleaseKey!,
          releaseName:        release.name,
          releaseYear:        release.year?.toString() ?? '',
          releaseSegmentId:   '',
          cardsightSetId:     set.catalogImportSetKey!,
        );
        parallels = result.parallels;
      }

      // Lazy-load cards if needed
      var cards = await ref.read(cardsServiceProvider).searchMasterCards(set.id, '', limit: 10000);
      if (cards.isEmpty && set.catalogImportSetKey != null && release.catalogImportReleaseKey != null) {
        await ref.read(cardsServiceProvider).importCardsForSet(
          cardsightReleaseId: release.catalogImportReleaseKey!,
          cardsightSetId: set.catalogImportSetKey!,
          setId: set.id,
        );
        cards = await ref.read(cardsServiceProvider).searchMasterCards(set.id, '', limit: 10000);
      }

      setState(() {
        _selectedRelease = release;
        _selectedSet = set;
        _parallels = parallels;
        _selectedParallel = null;
        _parallelName = 'Base';
        _selectedCard = null;
        _cardCtrl.clear();
        _setSearchCtrl.clear();
        _allCards = cards;
        _cardResults = cards;
        _isNewCard = false;
        _catalogStep = _CatalogStep.card;
      });
    } catch (e) {
      if (mounted) AdaptiveSnackBar.show(context, message: 'Error: $e', type: AdaptiveSnackBarType.error);
    } finally {
      if (mounted) setState(() => _lazyImporting = false);
    }
  }

  // ── Card search ───────────────────────────────────────────────

  void _searchCards(String query) {
    if (_selectedSet == null) {
      setState(() { _cardResults = []; });
      return;
    }
    final raw = query.trim().toLowerCase();
    if (raw.isEmpty) {
      setState(() => _cardResults = List<MasterCard>.from(_allCards));
      return;
    }
    final q = raw.replaceFirst(RegExp(r'^#'), '');
    setState(() {
      _cardResults = _allCards.where((card) {
        final player = card.player.toLowerCase();
        if (player.contains(raw) || player.contains(q)) return true;
        final numRaw = (card.cardNumber ?? '').trim().toLowerCase();
        if (numRaw.isEmpty) return false;
        final numNorm = numRaw.replaceFirst(RegExp(r'^#'), '');
        if (numNorm == q || numNorm.contains(q) || q.contains(numNorm)) return true;
        final qi = int.tryParse(q);
        final ni = int.tryParse(numNorm);
        if (qi != null && ni != null && qi == ni) return true;
        return false;
      }).toList();
    });
  }

  void _selectCard(MasterCard card) {
    final hasParallels = _parallels.isNotEmpty;
    setState(() {
      _selectedCard = card;
      _cardCtrl.text = card.displayName;
      _cardResults = [];
      _isNewCard = false;
      _selectedParallel = null;
      _parallelName = 'Base';
      // Always land at the parallel step (or stay at `card` if there are
      // no parallels). The detail UI is now a pushed route — we open it
      // below for the no-parallels case once state is settled.
      _catalogStep = hasParallels ? _CatalogStep.parallel : _CatalogStep.card;
    });
    unawaited(_saveNavigationState());
    unawaited(ref.read(compsServiceProvider).fetchCardImage(card.id));
    if (!hasParallels && !_restoringState) {
      _openMasterCardDetail(
        card: card,
        parallelName: 'Base',
        parallel: null,
        release: _selectedRelease,
        set: _selectedSet,
      );
    }
  }

  void _selectParallel(SetParallel? p) {
    setState(() {
      _selectedParallel = p;
      _parallelName = p?.name ?? 'Base';
    });
  }

  /// Push the read-only master-card detail route. Both browse and search flows
  /// land here once the user has chosen a card + parallel — the route is the
  /// catalog-side counterpart of [ItemDetailScreen] without the value/copy
  /// sections.
  ///
  /// The catalog's selected-card/parallel state must already reflect [card]
  /// and [parallelName]. [onAddToCollection] / [onAddToWishlist] close over the
  /// resolved `master_card_definitions` id so add / wishlist use the variant row
  /// (parallel FK, guide prices, `current_prices`), not the base-only list id.
  Future<void> _openMasterCardDetail({
    required MasterCard card,
    required String parallelName,
    SetParallel? parallel,
    ReleaseRecord? release,
    SetRecord? set,
    bool openedFromScanResults = false,
  }) async {
    final resolvedId = await ref.read(cardsServiceProvider).ensureCatalogVariant(
      catalogVariantId: card.id,
      parallelId: parallel?.id,
    );
    if (!mounted) return;
    final resolvedMaster =
        await ref.read(cardsServiceProvider).fetchMasterCardById(resolvedId);
    if (!mounted) return;
    final displayCard = resolvedMaster ??
        MasterCard(
          id: resolvedId,
          player: card.player,
          cardNumber: card.cardNumber,
          isRookie: card.isRookie,
          isAuto: card.isAuto || (parallel?.isAuto ?? false),
          isPatch: card.isPatch,
          isSSP: card.isSSP,
          serialMax: parallel?.serialMax ?? card.serialMax,
          imageUrl: card.imageUrl,
          gain: card.gain,
        );
    // `Navigator.push(MaterialPageRoute(...))`. The latter pushes onto the
    // inner Navigator below the shell but stays opaque to go_router, so when
    // the user taps a tab, `context.go(...)` updates the router's stack
    // without popping the imperative route — leaving the master detail
    // screen on top of the new tab. Routing through go_router keeps the
    // pushed page on the same stack as everything else, so tab taps pop it
    // cleanly.
    await context.push<void>(
      '/catalog/master',
      extra: MasterCardDetailArgs(
        masterCard:         MasterCard(
          id: displayCard.id,
          player: displayCard.player,
          cardNumber: displayCard.cardNumber,
          isRookie: displayCard.isRookie,
          isAuto: displayCard.isAuto || (parallel?.isAuto ?? false),
          isPatch: displayCard.isPatch,
          isSSP: displayCard.isSSP,
          serialMax: parallel?.serialMax ?? displayCard.serialMax,
          imageUrl: displayCard.imageUrl,
          guidePriceCardId: displayCard.guidePriceCardId,
          gain: displayCard.gain,
        ),
        parallelName: parallelName,
        parallelSerialMax: parallel?.serialMax,
        parallelIsAuto: parallel?.isAuto ?? false,
        releaseName: release?.name,
        setName: set?.name,
        year: release?.year,
        sport: release?.sport,
        onAddToCollection: () => _showAddCopySheet(
              catalogMasterIdOverride: resolvedId,
              catalogParallelOverride: parallel,
            ),
        onAddToWishlist: () => _addToWishlist(
              catalogMasterIdOverride: resolvedId,
              catalogParallelOverride: parallel,
            ),
        openedFromScanResults: openedFromScanResults,
      ),
    );
  }

  // ── Save ─────────────────────────────────────────────────────

  bool get _canSave {
    final hasCard = _selectedCard != null || (_isNewCard && _newPlayerCtrl.text.trim().isNotEmpty);
    return _selectedSet != null && hasCard && !_saving;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      String? resolvedMasterId;
      if (_selectedCard != null) {
        resolvedMasterId = await ref.read(cardsServiceProvider).ensureCatalogVariant(
          catalogVariantId: _selectedCard!.id,
          parallelId: _selectedParallel?.id,
        );
      }
      final form = AddCardFormData(
        masterCardId: resolvedMasterId,
        setId: _selectedSet?.id,
        player: _isNewCard ? _newPlayerCtrl.text.trim() : (_selectedCard?.player ?? ''),
        cardNumber: _isNewCard ? (_newCardNumberCtrl.text.trim().isEmpty ? null : _newCardNumberCtrl.text.trim()) : null,
        serialMax: _isNewCard ? int.tryParse(_newSerialMaxCtrl.text.trim()) : null,
        isRookie: _isNewCard ? _newIsRookie : false,
        isAuto: _isNewCard ? _newIsAuto : false,
        isPatch: _isNewCard ? _newIsPatch : false,
        isSSP: _isNewCard ? _newIsSSP : false,
        parallelId: _selectedParallel?.id,
        parallelName: _parallelName,
        pricePaid: parseUsdInput(_pricePaidCtrl.text),
        serialNumber: _serialNumberCtrl.text.trim().isEmpty ? null : _serialNumberCtrl.text.trim(),
        isGraded: _isGraded,
        grader: _isGraded ? _grader : 'PSA',
        gradeValue: _isGraded && _gradeValueCtrl.text.trim().isNotEmpty ? _gradeValueCtrl.text.trim() : null,
      );
      final created = await ref.read(cardsServiceProvider).addCard(form);
      await ref.read(compsServiceProvider).syncMasterCatalogPricingForVariant(created.masterCardId);
      ref.invalidate(userCardsProvider);
      await ref.read(userCardsProvider.future);
      unawaited(ref.read(compsServiceProvider).fetchCardImage(created.masterCardId));
      if (mounted) {
        AdaptiveSnackBar.show(context, message: 'Card added!', type: AdaptiveSnackBarType.success, duration: const Duration(seconds: 2));
        unawaited(_clearNavigationState());
        setState(() {
          _catalogStep = _CatalogStep.sets;
          _selectedCard = null;
          _cardCtrl.clear();
          _cardResults = [];
          _isNewCard = false;
          _selectedRelease = null;
          _selectedSet = null;
          _pricePaidCtrl.clear();
          _serialNumberCtrl.clear();
          _isGraded = false;
          _grader = 'PSA';
          _gradeValueCtrl.clear();
          _parallelName = 'Base';
          _selectedParallel = null;
          _newPlayerCtrl.clear();
          _newCardNumberCtrl.clear();
          _newSerialMaxCtrl.clear();
          _newIsRookie = false;
          _newIsAuto = false;
          _newIsPatch = false;
          _newIsSSP = false;
        });
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.pop();
        });
      }
    } catch (e) {
      if (mounted) AdaptiveSnackBar.show(context, message: 'Error: $e', type: AdaptiveSnackBarType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showAddCopySheet({
    String? catalogMasterIdOverride,
    SetParallel? catalogParallelOverride,
  }) {
    final card = _mode == _CatalogMode.search ? _searchSelectedCard : _selectedCard;
    final set = _mode == _CatalogMode.search ? _searchSelectedSet : _selectedSet;
    final release = _mode == _CatalogMode.search ? _searchSelectedRelease : _selectedRelease;
    final selectedParallel = _mode == _CatalogMode.search ? _searchSelectedParallel : _selectedParallel;
    final effectiveParallel = catalogParallelOverride ?? selectedParallel;
    final parallelLabel = (effectiveParallel?.name.trim().isNotEmpty ?? false)
        ? effectiveParallel!.name.trim()
        : (_mode == _CatalogMode.search ? _searchParallelName : _parallelName);

    showAdaptiveSheet(
      context: context,
      builder: (_) => CardSheet(
        title: 'Add to Your Collection',
        card: card,
        setName: set?.name,
        releaseName: release?.displayName,
        previewParallelName: parallelLabel,
        previewParallelSerialMax: effectiveParallel?.serialMax,
        previewParallelIsAuto: effectiveParallel?.isAuto ?? false,
        showPricePaid: true,
        pricePaidCtrl: _pricePaidCtrl,
        showSerialNumber: effectiveParallel?.serialMax != null,
        serialNumberCtrl: _serialNumberCtrl,
        showGraded: true,
        isGraded: _isGraded,
        grader: _grader,
        gradeValueCtrl: _gradeValueCtrl,
        onGradedChanged: (v) => setState(() => _isGraded = v),
        onGraderChanged: (g) => setState(() => _grader = g ?? 'PSA'),
        onSave: (data) async {
          setState(() => _saving = true);
          try {
            final baseMasterId = catalogMasterIdOverride ?? card?.id;
            if (baseMasterId == null) {
              return 'No catalog card selected.';
            }
            final variantId = await ref.read(cardsServiceProvider).ensureCatalogVariant(
              catalogVariantId: baseMasterId,
              parallelId: effectiveParallel?.id,
            );
            final form = AddCardFormData(
              masterCardId: variantId,
              setId: set?.id,
              player: card?.player ?? '',
              cardNumber: card?.cardNumber,
              serialMax: card?.serialMax,
              isRookie: card?.isRookie ?? false,
              isAuto: card?.isAuto ?? false,
              isPatch: card?.isPatch ?? false,
              isSSP: card?.isSSP ?? false,
              parallelId: effectiveParallel?.id,
              parallelName: parallelLabel,
              pricePaid: parseUsdInput(_pricePaidCtrl.text),
              serialNumber: _serialNumberCtrl.text.trim().isEmpty ? null : _serialNumberCtrl.text.trim(),
              isGraded: _isGraded,
              grader: _isGraded ? _grader : 'PSA',
              gradeValue: _isGraded && _gradeValueCtrl.text.trim().isNotEmpty ? _gradeValueCtrl.text.trim() : null,
            );
            final created = await ref.read(cardsServiceProvider).addCard(form);
            await ref.read(compsServiceProvider).syncMasterCatalogPricingForVariant(created.masterCardId);
            ref.invalidate(userCardsProvider);
            await ref.read(userCardsProvider.future);
            unawaited(ref.read(compsServiceProvider).fetchCardImage(created.masterCardId));
            if (mounted) {
              _pricePaidCtrl.clear();
              _serialNumberCtrl.clear();
              setState(() {
                _isGraded = false;
                _grader = 'PSA';
              });
              _gradeValueCtrl.clear();
              AdaptiveSnackBar.show(context, message: 'Card added!', type: AdaptiveSnackBarType.success, duration: const Duration(seconds: 2));
            }
            return null;
          } catch (e) {
            return e.toString();
          } finally {
            if (mounted) setState(() => _saving = false);
          }
        },
      ),
    );
  }

  Future<void> _addToWishlist({
    String? catalogMasterIdOverride,
    SetParallel? catalogParallelOverride,
  }) async {
    final card = _mode == _CatalogMode.search ? _searchSelectedCard : _selectedCard;
    final set = _mode == _CatalogMode.search ? _searchSelectedSet : _selectedSet;
    final release = _mode == _CatalogMode.search ? _searchSelectedRelease : _selectedRelease;
    final selectedParallel = _mode == _CatalogMode.search ? _searchSelectedParallel : _selectedParallel;
    final effectiveParallel = catalogParallelOverride ?? selectedParallel;
    final parallelLabel = (effectiveParallel?.name.trim().isNotEmpty ?? false)
        ? effectiveParallel!.name.trim()
        : (_mode == _CatalogMode.search ? _searchParallelName : (_selectedParallel?.name ?? 'Base'));

    showAdaptiveSheet(
      context: context,
      builder: (_) => CardSheet(
        title: 'Add to Wishlist',
        card: card,
        setName: set?.name,
        releaseName: release?.displayName,
        previewParallelName: parallelLabel,
        previewParallelSerialMax: effectiveParallel?.serialMax,
        previewParallelIsAuto: effectiveParallel?.isAuto ?? false,
        showTargetPrice: true,
        targetPriceCtrl: _targetPriceCtrl,
        showGraded: false,
        onSave: (_) async {
          try {
            final baseMasterId = catalogMasterIdOverride ?? card?.id;
            if (baseMasterId == null) {
              return 'No catalog card selected.';
            }
            final variantId = await ref.read(cardsServiceProvider).ensureCatalogVariant(
              catalogVariantId: baseMasterId,
              parallelId: effectiveParallel?.id,
            );
            await ref.read(wishlistProvider.notifier).add({
              'player': (card?.player ?? '').trim(),
              'year': release?.year,
              'set_name': release?.name,
              'card_number': (card?.cardNumber ?? '').trim(),
              'parallel': parallelLabel,
              'is_rookie': card?.isRookie ?? false,
              'is_auto': card?.isAuto ?? false,
              'is_patch': card?.isPatch ?? false,
              'serial_max': card?.serialMax,
              'grade': null,
              'ebay_query': null,
              'exclude_terms': [],
              'target_price': parseUsdInput(_targetPriceCtrl.text),
              'master_card_id': variantId,
              'release_id': release?.id,
              'set_id': set?.id,
              'sport': release?.sport,
            });
            ref.invalidate(wishlistProvider);
            _targetPriceCtrl.clear();
            if (mounted) {
              AdaptiveSnackBar.show(
                context,
                message: 'Added to Wishlist!',
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
  }

  // ── AppBar helpers ─────────────────────────────────────────────

  bool get _omitCatalogShellTrailing {
    final atBrowseRoot =
        _catalogStep == _CatalogStep.sportPicker && _mode == _CatalogMode.browse;
    final atSearchRoot = _mode == _CatalogMode.search && _searchSelectedCard == null;
    return !(atBrowseRoot || atSearchRoot);
  }

  /// Browse catalog loading: hide segment row + filter chrome; center fan loader on body.
  bool get _catalogBlockingLoader {
    if (_restoringState) return true;
    if (_scanBootstrapEntry != null && _scanResolving) return true;
    if (_mode != _CatalogMode.browse) return false;
    return switch (_catalogStep) {
      _CatalogStep.browsing =>
        _browseLoading && _browseResults.isEmpty,
      _CatalogStep.sets => _browseSetsLoading || _lazyImporting,
      _ => false,
    };
  }

  Widget _catalogBlockingLoaderBody(ColorScheme colors) {
    return ColoredBox(
      color: colors.surface,
      child: const Center(child: CardFanLoader()),
    );
  }

  String _appBarTitle() {
    if (_mode == _CatalogMode.search) {
      if (_searchSelectedCard != null && (_searchParallels.isEmpty || _searchParallelSelected)) {
        return _searchSelectedCard!.player;
      }
      if (_searchSelectedCard != null && _searchParallels.isNotEmpty) {
        return 'Select Parallel';
      }
      if (_searchSelectedSet != null) return _searchSelectedSet!.name;
      if (_searchSelectedRelease != null) return _searchSelectedRelease!.displayName;
      return 'Catalog';
    }
    return switch (_catalogStep) {
      _CatalogStep.sportPicker => 'Catalog',
      _CatalogStep.browsing  => _catalogFilterSport.isNotEmpty ? _catalogFilterSport : 'Sports',
      _CatalogStep.sets      => _browseSelectedRelease?.displayName ?? 'Sets',
      _CatalogStep.card      => _selectedSet?.name ?? 'Find a Card',
      _CatalogStep.parallel  => _selectedCard?.player ?? 'Select Parallel',
      _CatalogStep.detail    => _selectedCard?.player ?? 'Card',
      _CatalogStep.addCopy   => 'Add to Collection',
    };
  }

  void _handleStepBack() {
    if (_mode == _CatalogMode.search) {
      if (_searchParallelSelected && _searchParallels.isNotEmpty) {
        // Going back from card details - show parallel selection again
        setState(() {
          _searchSelectedParallel = null;
          _searchParallelName = 'Base';
          _searchParallelSelected = false;
        });
      } else {
        // Going back from card/set/release selection - clear everything
        setState(() {
          _searchSelectedCard = null;
          _searchSelectedSet = null;
          _searchSelectedRelease = null;
          _searchParallels = [];
          _searchSelectedParallel = null;
          _searchParallelName = 'Base';
          _searchParallelSelected = false;
        });
      }
      return;
    }
    switch (_catalogStep) {
      case _CatalogStep.sportPicker:
        context.pop();
      case _CatalogStep.browsing:
        setState(() {
          _catalogStep = _CatalogStep.sportPicker;
          _catalogFilterSport = '';
          _browseResults = [];
        });
      case _CatalogStep.sets:
        setState(() {
          _catalogStep = _CatalogStep.browsing;
          _browseSelectedRelease = null;
          _browseSets = [];
          _setSearchCtrl.clear();
        });
      case _CatalogStep.card:
        setState(() {
          _catalogStep = _CatalogStep.sets;
          _selectedCard = null;
          _cardCtrl.clear();
          _cardResults = [];
          _isNewCard = false;
          _selectedSet = null;
        });
      case _CatalogStep.parallel:
        setState(() {
          _catalogStep = _CatalogStep.card;
          _selectedCard = null;
          _cardCtrl.clear();
          _cardResults = _allCards;
          _isNewCard = false;
        });
      case _CatalogStep.detail:
        setState(() {
          if (_parallels.isNotEmpty) {
            _catalogStep = _CatalogStep.parallel;
          } else {
            _catalogStep = _CatalogStep.card;
            _selectedCard = null;
            _cardCtrl.clear();
            _cardResults = _allCards;
            _isNewCard = false;
          }
        });
      case _CatalogStep.addCopy:
        setState(() {
          _catalogStep = _CatalogStep.detail;
          _pricePaidCtrl.clear();
          _serialNumberCtrl.clear();
          _isGraded = false;
          _grader = 'PSA';
          _gradeValueCtrl.clear();
          _parallelName = 'Base';
          _selectedParallel = null;
        });
    }
  }

  // ── Sticky chrome (segment row ± filters) ────────────────────

  Widget _catalogSegmentRow(
    ColorScheme colors, {
    required bool hasSecondaryChrome,
  }) {
    final segmentPadding = EdgeInsets.fromLTRB(
      ChromeMetrics.compactHorizontalInset,
      ChromeMetrics.segmentOnlyTopInset,
      ChromeMetrics.compactHorizontalInset,
      hasSecondaryChrome ? 0 : ChromeMetrics.segmentOnlyBottomInset,
    );
    return Padding(
      padding: segmentPadding,
      child: AppSegmentedControl(
        segmentKey: const ValueKey('catalog-mode-segment'),
        labels: const ['Browse', 'Search'],
        selectedIndex: _mode == _CatalogMode.browse ? 0 : 1,
        onValueChanged: (index) {
          setState(() {
            _mode = index == 0 ? _CatalogMode.browse : _CatalogMode.search;
          });
        },
        color: colors.primary,
      ),
    );
  }

  Widget _browseReleaseFiltersColumn(ColorScheme colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: AdaptiveDropdown<String>(
            value: _catalogFilterYear,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('Any year', style: TextStyle(fontSize: 13))),
              ..._catalogYears.map((y) => DropdownMenuItem(value: y, child: Text(y, style: const TextStyle(fontSize: 13)))),
            ],
            onChanged: (v) {
              setState(() {
                _catalogFilterYear = v ?? '';
                _browseSearchCtrl.clear();
              });
              _loadBrowseReleases(reset: true);
            },
          ),
        ),
        Container(
          padding: ChromeMetrics.searchBarRowPadding(),
          child: GlassSearchField(
            controller: _browseSearchCtrl,
            hint: 'Search releases…',
            onChanged: (_) => setState(() {}),
            onClear: () => setState(() => _browseSearchCtrl.clear()),
          ),
        ),
      ],
    );
  }

  /// Single blurred strip under the app bar for this screen (segments only, or segments + bars).
  ({Widget child, double heightEstimate}) _catalogStickyChrome(ColorScheme colors) {
    const segmentEst = _kStickyEstSegment;
    Widget? secondary;
    double secondaryHeight = 0;

    if (_catalogBlockingLoader) {
      return (child: const SizedBox.shrink(), heightEstimate: 0);
    }

    if (_mode == _CatalogMode.search) {
      if (_searchSelectedCard != null && _searchParallelsLoading) {
        return (
          child: _catalogSegmentRow(colors, hasSecondaryChrome: false),
          heightEstimate: segmentEst,
        );
      }
      if (_searchSelectedCard != null && _searchParallels.isNotEmpty && !_searchParallelSelected) {
        return (
          child: _catalogSegmentRow(colors, hasSecondaryChrome: false),
          heightEstimate: segmentEst,
        );
      }
      if (_searchSelectedCard != null) {
        return (
          child: _catalogSegmentRow(colors, hasSecondaryChrome: false),
          heightEstimate: segmentEst,
        );
      }
      secondaryHeight = _kStickyEstGlobalSearch;
      secondary = Padding(
        padding: ChromeMetrics.searchBarSecondaryPadding(),
        child: FilterSortActionBar<void>(
          searchController: _globalSearchCtrl,
          onSearchChanged: _onSearchChanged,
          onSearchClear: () => setState(() {
            _globalSearchCtrl.clear();
            _globalSearchResults = [];
          }),
          searchHint: 'Search releases, sets, or cards…',
        ),
      );
      return (
        heightEstimate: segmentEst + secondaryHeight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _catalogSegmentRow(colors, hasSecondaryChrome: true),
            secondary,
          ],
        ),
      );
    }

    switch (_catalogStep) {
      case _CatalogStep.browsing:
        secondaryHeight = _kStickyEstBrowsePlus;
        secondary = _browseReleaseFiltersColumn(colors);
        break;
      case _CatalogStep.sets:
        secondaryHeight = _kStickyEstSetSearch;
        secondary = Padding(
          padding: ChromeMetrics.searchBarSecondaryPadding(
            horizontal: ChromeMetrics.horizontalInset,
            top: 12,
          ),
          child: GlassSearchField(
            controller: _setSearchCtrl,
            hint: 'Search sets…',
            onChanged: (_) => setState(() {}),
            onClear: () => setState(() => _setSearchCtrl.clear()),
          ),
        );
        break;
      case _CatalogStep.card:
        secondaryHeight = _kStickyEstCardSearch;
        secondary = Padding(
          padding: ChromeMetrics.searchBarSecondaryPadding(
            horizontal: ChromeMetrics.horizontalInset,
            top: 12,
          ),
          child: GlassSearchField(
            controller: _cardCtrl,
            hint: 'Search player name…',
            onChanged: _searchCards,
            onClear: () {
              _cardCtrl.clear();
              _searchCards('');
            },
          ),
        );
        break;
      case _CatalogStep.sportPicker:
      case _CatalogStep.parallel:
      case _CatalogStep.detail:
      case _CatalogStep.addCopy:
        break;
    }
    final hasSecondaryChrome = secondary != null;
    return (
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _catalogSegmentRow(colors, hasSecondaryChrome: hasSecondaryChrome),
          ?secondary,
        ],
      ),
      heightEstimate: segmentEst + secondaryHeight,
    );
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final blockingLoader = _catalogBlockingLoader;
    final sticky = blockingLoader
        ? (child: const SizedBox.shrink(), heightEstimate: 0.0)
        : _catalogStickyChrome(colors);
    return StickyChromeScaffold(
      stickyHeightEstimate: sticky.heightEstimate,
      stickyChrome: sticky.child,
      appBar: buildGlassNavBar(
        context,
        useBlurBackground: true,
        leading: (_catalogStep == _CatalogStep.sportPicker && _mode == _CatalogMode.browse) ||
                 (_mode == _CatalogMode.search && _searchSelectedCard == null) ||
                 (_scanBootstrapEntry != null && _scanResolving) ||
                 blockingLoader
            ? null
            : AppBarGlassCircleButton(
                onPressed: _handleStepBack,
                icon: Icons.chevron_left,
              ),
        centerTitle: false,
        title: blockingLoader
            ? const SizedBox.shrink()
            : Text(
                _appBarTitle(),
                style: AppFonts.appBarTitle.copyWith(color: colors.onSurface),
              ),
        actions: blockingLoader
            ? null
            : appBarShellTrailingActions(
                context,
                omitShellTrailing: _omitCatalogShellTrailing,
              ),
      ),
      bodyBuilder: (context, contentTopInset) {
        if (blockingLoader) return _catalogBlockingLoaderBody(colors);
        if (_mode == _CatalogMode.browse) {
          return switch (_catalogStep) {
            _CatalogStep.sportPicker => _buildSportPickerView(colors, contentTopInset),
            _CatalogStep.browsing  => _buildBrowseView(colors, contentTopInset),
            _CatalogStep.sets      => _buildSetsView(colors, contentTopInset),
            _CatalogStep.card      => _buildCardSearchView(colors, contentTopInset),
            _CatalogStep.parallel  => _buildParallelView(colors, contentTopInset),
            _CatalogStep.detail    => _buildCardDetailView(colors, contentTopInset),
            _CatalogStep.addCopy   => _buildYourCopyFormView(colors, contentTopInset),
          };
        }
        return _buildSearchMode(colors, contentTopInset);
      },
    );
  }

  // ── Browse view (release list) ────────────────────────────────

  Widget _buildBrowseView(ColorScheme colors, double contentTopInset) {
    final searchQuery = _browseSearchCtrl.text.toLowerCase();
    final filtered = _browseResults.where((r) {
      final name = r.displayName.toLowerCase();
      final sport = (r.sport ?? '').toLowerCase();
      return name.contains(searchQuery) || sport.contains(searchQuery);
    }).toList();
    final listPadTop = contentTopInset;

    if (filtered.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: listPadTop),
        child: Center(
          child: Text(
            _browseResults.isEmpty
                ? 'No releases found.\nTry a different year or sport.'
                : 'No results match your search.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurface.withValues(alpha: 0.5)),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.only(top: listPadTop),
      itemCount: filtered.length + (_browseHasMore && filtered.length == _browseResults.length ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        if (i == filtered.length) {
          return _browseLoading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              : AdaptiveListTile(
                  hideBottomDivider: true,
                  title: Text('Load more',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.primary, fontSize: 14)),
                  onTap: _loadBrowseReleases,
                );
        }
        final r = filtered[i];
        return AdaptiveListTile(
          hideBottomDivider: true,
          title: Text(r.displayName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: r.sport != null ? Text(r.sport!, style: const TextStyle(fontSize: 12)) : null,
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => _selectBrowseRelease(r),
        );
      },
    );
  }

  // ── Sport picker view ─────────────────────────────────────────

  Widget _buildSportPickerView(ColorScheme colors, double contentTopInset) {
    final sports = [
      ('Baseball', 'Baseball', '⚾', Color(0xFFB45309)),
      ('Basketball', 'Basketball', '🏀', Color(0xFFF97316)),
      ('Football', 'Football', '🏈', Color(0xFF8B5CF6)),
      ('Soccer', 'Soccer', '⚽', Color(0xFF16A34A)),
      ('Hockey', 'Hockey', '🏒', Color(0xFF2563EB)),
    ];

    return GridView.count(
      padding: EdgeInsets.fromLTRB(16, contentTopInset, 16, 24),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.2,
      children: sports.map((sport) {
        final (name, value, emoji, tintColor) = sport;
        return GestureDetector(
          onTap: () {
            setState(() {
              _catalogFilterSport = value;
              _catalogFilterYear = '';
              _browseSearchCtrl.clear();
            });
            _loadBrowseReleases(reset: true);
            setState(() => _catalogStep = _CatalogStep.browsing);
          },
          child: Container(
            decoration: BoxDecoration(
              color: tintColor.withValues(alpha: 0.15),
              border: Border.all(
                color: tintColor.withValues(alpha: 0.3),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Sets view ─────────────────────────────────────────────────

  Widget _buildSetsView(ColorScheme colors, double contentTopInset) {
    final searchQuery = _setSearchCtrl.text.toLowerCase();
    final filtered = _browseSets.where((s) {
      return s.name.toLowerCase().contains(searchQuery);
    }).toList();

    final listPadTop = contentTopInset;
    if (filtered.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: listPadTop),
        child: Center(
          child: Text(
            _browseSets.isEmpty ? 'No sets found.' : 'No results match your search.',
            style: TextStyle(color: colors.onSurface.withValues(alpha: 0.5)),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.only(top: listPadTop),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final s = filtered[i];
        return AdaptiveListTile(
          hideBottomDivider: true,
          title: Text(s.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: s.cardCount != null ? Text('${s.cardCount} cards', style: const TextStyle(fontSize: 12)) : null,
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => _selectBrowseSet(s),
        );
      },
    );
  }

  // ── Card search view ─────────────────────────────────────────────────────

  Widget _buildCardSearchView(ColorScheme colors, double contentTopInset) {
    return _buildCardResultsArea(colors, topInset: contentTopInset);
  }

  // ── Parallel step ─────────────────────────────────────────────

  Widget _buildParallelView(ColorScheme colors, double contentTopInset) {
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.only(top: contentTopInset),
            itemCount: _parallels.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final isBase = i == 0;
              final p = isBase ? null : _parallels[i - 1];
              return _buildParallelListTile(
                parallel: p,
                onTap: () {
                  setState(() {
                    _selectedParallel = p;
                    _parallelName = p?.name ?? 'Base';
                  });
                  if (_selectedCard != null) {
                    _openMasterCardDetail(
                      card: _selectedCard!,
                      parallelName: p?.name ?? 'Base',
                      parallel: p,
                      release: _selectedRelease,
                      set: _selectedSet,
                    );
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Card detail view (read-only, showing Add to Collection/Wishlist buttons) ──

  Widget _buildCardDetailView(ColorScheme colors, double contentTopInset) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, contentTopInset + 16, 16, 24),
            children: [
              CardDetailView(
                masterCard: _selectedCard,
                setName: _selectedSet?.name,
                releaseName: _browseSelectedRelease?.displayName ?? _selectedRelease?.displayName,
                parallelName: _selectedParallel?.name ?? 'Base',
                year: _selectedRelease?.year != null ? int.tryParse(_selectedRelease!.year.toString()) : null,
                sport: _selectedRelease?.sport,
                sections: const [CardDetailSection.hero],
              ),
              const SizedBox(height: 16),
              if (_selectedCard != null)
                Consumer(
                  builder: (context, ref, _) {
                    final vKey = CatalogBrowseVariantKey(
                      baseMasterId: _selectedCard!.id,
                      parallelId: _selectedParallel?.id,
                    );
                    final resolved = ref.watch(catalogBrowseResolvedMasterIdProvider(vKey));
                    return resolved.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                      ),
                      error: (e, s) => const SizedBox.shrink(),
                      data: (variantId) {
                        final selectedParallelName = _selectedParallel?.name ?? 'Base';
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Consumer(
                                    builder: (context, ref, child) {
                                      final userCardsAsync = ref.watch(userCardsProvider);
                                      final copyCount = userCardsAsync.whenData((allCards) {
                                        return allCards.where((card) {
                                          if (card.masterCardId == variantId) return true;
                                          return card.masterCardId == _selectedCard!.id &&
                                              (card.cardNumber?.trim() ?? '') ==
                                                  (_selectedCard!.cardNumber?.trim() ?? '') &&
                                              card.parallel.trim() == selectedParallelName.trim();
                                        }).length;
                                      }).value ??
                                          0;

                                      return copyCount > 0
                                          ? ActiveStateIndicator(
                                              icon: Icons.check_circle,
                                              label: 'In Collection ($copyCount)',
                                              animateIcon: true,
                                            )
                                          : AdaptiveButton.child(
                                              onPressed: () => _showAddCopySheet(),
                                              style: AdaptiveButtonStyle.filled,
                                              color: AppTheme.primary,
                                              child: const Text(
                                                'Add to Collection',
                                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                              ),
                                            );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Consumer(
                                    builder: (context, ref, child) {
                                      final wishlistAsync = ref.watch(wishlistProvider);
                                      final isInWishlist = wishlistAsync.whenData((wishlist) {
                                        return wishlist.any((item) {
                                          final mid = item.masterCardId?.trim();
                                          if (mid != null && mid.isNotEmpty && mid == variantId) {
                                            return true;
                                          }
                                          final playerMatch = (item.player?.trim().toLowerCase() ?? '') ==
                                              (_selectedCard!.player.trim().toLowerCase());
                                          final cardNumberMatch = (item.cardNumber?.trim() ?? '') ==
                                              (_selectedCard!.cardNumber?.trim() ?? '');
                                          final parallelMatch = (item.parallel?.trim() ?? 'Base') ==
                                              selectedParallelName.trim();
                                          return playerMatch && cardNumberMatch && parallelMatch;
                                        });
                                      }).value ??
                                          false;

                                      return isInWishlist
                                          ? const ActiveStateIndicator(
                                              icon: Icons.favorite,
                                              label: 'In Wishlist',
                                              animateIcon: true,
                                            )
                                          : AdaptiveButton.child(
                                              onPressed: () => _addToWishlist(),
                                              style: AdaptiveButtonStyle.bordered,
                                              color: AppTheme.primary,
                                              padding: ChromeMetrics.adaptiveBorderedButtonPadding,
                                              child: DefaultTextStyle.merge(
                                                style: const TextStyle(
                                                    color: AppTheme.primary, fontWeight: FontWeight.w600),
                                                child: const Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(Icons.favorite_border, size: 18, color: AppTheme.primary),
                                                    SizedBox(width: 8),
                                                    Text('Add to Wishlist'),
                                                  ],
                                                ),
                                              ),
                                            );
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ref
                                .watch(
                                  soldCompsExistForGradeProvider(
                                    SoldCompsGradeKey(
                                      masterCardId: variantId,
                                      grade: 'Raw',
                                    ),
                                  ),
                                )
                                .when(
                                  data: (has) => has
                                      ? CardCompsSection(
                                          masterCardId: variantId,
                                          initialGrade: 'Raw',
                                        )
                                      : const SizedBox.shrink(),
                                  loading: () => const SizedBox.shrink(),
                                  error: (e, s) => const SizedBox.shrink(),
                                ),
                          ],
                        );
                      },
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Your Copy form view ───────────────────────────────────────────────────

  Widget _buildYourCopyFormView(ColorScheme colors, double contentTopInset) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, contentTopInset + 12, 16, 24),
            children: [
              // Selected card chip or new card indicator
              if (_selectedCard != null) ...[
                _SelectedChip(
                  label: _selectedCard!.displayName,
                  onClear: () => setState(() {
                    _selectedCard = null;
                    _cardCtrl.clear();
                    _cardResults = [];
                    _catalogStep = _CatalogStep.card;
                  }),
                ),
                const SizedBox(height: 16),
              ] else if (_isNewCard) ...[
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('New Card',
                          style: TextStyle(fontSize: 13, color: colors.primary, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => setState(() {
                        _isNewCard = false;
                        _newPlayerCtrl.clear();
                        _newCardNumberCtrl.clear();
                        _newSerialMaxCtrl.clear();
                        _newIsRookie = false;
                        _newIsAuto = false;
                        _newIsPatch = false;
                        _newIsSSP = false;
                        _catalogStep = _CatalogStep.card;
                      }),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              // New card definition fields
              if (_isNewCard) ...[
                _sectionHeader('Card Definition', colors),
                const SizedBox(height: 8),
                _NewCardFields(
                  playerCtrl: _newPlayerCtrl,
                  cardNumberCtrl: _newCardNumberCtrl,
                  serialMaxCtrl: _newSerialMaxCtrl,
                  isRookie: _newIsRookie,
                  isAuto: _newIsAuto,
                  isPatch: _newIsPatch,
                  isSSP: _newIsSSP,
                  onToggleRookie: (v) => setState(() => _newIsRookie = v),
                  onToggleAuto: (v) => setState(() => _newIsAuto = v),
                  onTogglePatch: (v) => setState(() => _newIsPatch = v),
                  onToggleSSP: (v) => setState(() => _newIsSSP = v),
                ),
                const SizedBox(height: 20),
              ],
              // Your Copy section
              _sectionHeader('Your Copy', colors),
              const SizedBox(height: 8),
              _YourCopyFields(
                parallels: _parallels,
                loadingParallels: _loadingParallels,
                selectedParallel: _selectedParallel,
                parallelName: _parallelName,
                pricePaidCtrl: _pricePaidCtrl,
                pricePaidInputFormatters: [_pricePaidUsdFormatter],
                serialNumberCtrl: _serialNumberCtrl,
                isGraded: _isGraded,
                grader: _grader,
                gradeValueCtrl: _gradeValueCtrl,
                onParallelChanged: _selectParallel,
                onParallelNameChanged: (v) => setState(() => _parallelName = v),
                onGradedChanged: (v) => setState(() => _isGraded = v),
                onGraderChanged: (v) => setState(() => _grader = v),
              ),
              const SizedBox(height: 24),
              // Save button
              AdaptiveButton.child(
                onPressed: _canSave ? _save : null,
                style: AdaptiveButtonStyle.filled,
                color: AppTheme.primary,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Add to Collection',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Card results area ─────────────────────────────────────────

  Widget _buildCardResultsArea(ColorScheme colors, {double topInset = 0}) {
    if (_cardResults.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: topInset),
        child: Center(
          child: Text('No cards found.',
              style: TextStyle(color: colors.onSurface.withValues(alpha: 0.4))),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.only(top: topInset),
      itemCount: _cardResults.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final c = _cardResults[i];
        final attrs = _cardAttributePills(c);
        return AdaptiveListTile(
          hideBottomDivider: true,
          onTap: () => _selectCard(c),
          title: _buildNameWithAttributes(c.displayName, attrs),
          trailing: const Icon(Icons.chevron_right, size: 18),
        );
      },
    );
  }

  Widget? _parallelAttrPills(SetParallel p) {
    final hasAttrs = p.serialMax != null || p.isAuto;
    if (!hasAttrs) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        if (p.isAuto) const AttrTag('AUTO', color: CardAttributePalette.auto),
        if (p.serialMax != null) AttrTag('/${p.serialMax}', color: const Color(0xFF3B82F6)),
      ],
    );
  }

  Widget _buildParallelListTile({
    required SetParallel? parallel,
    required VoidCallback onTap,
  }) {
    final isBase = parallel == null;
    final label = isBase ? 'Base' : parallel.name;
    final attrs = isBase ? null : _parallelAttrPills(parallel);

    return AdaptiveListTile(
      hideBottomDivider: true,
      onTap: onTap,
      title: _buildNameWithAttributes(label, attrs),
      trailing: const Icon(Icons.chevron_right, size: 18),
    );
  }

  Widget _buildNameWithAttributes(String label, Widget? attrs) {
    return Row(
      children: [
        Flexible(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (attrs != null) ...[
          const SizedBox(width: 6),
          attrs,
        ],
      ],
    );
  }

  Widget? _cardAttributePills(MasterCard c) {
    final hasAttrs = c.isRookie || c.isAuto || c.isPatch || c.isSSP || c.serialMax != null;
    if (!hasAttrs) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        if (c.isRookie) const AttrTag('RC', color: CardAttributePalette.rookie),
        if (c.isAuto) const AttrTag('AUTO', color: CardAttributePalette.auto),
        if (c.isPatch) const AttrTag('PATCH', color: CardAttributePalette.patch),
        if (c.isSSP) const AttrTag('SSP', color: CardAttributePalette.ssp),
        if (c.serialMax != null) AttrTag('/${c.serialMax}', color: const Color(0xFF3B82F6)),
      ],
    );
  }


  // ── Shared helpers ────────────────────────────────────────────

  Widget _sectionHeader(String title, ColorScheme colors) {
    return Text(
      title,
      style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: colors.onSurface.withValues(alpha: 0.6),
          letterSpacing: 0.5),
    );
  }

  // ── Global search ────────────────────────────────────────────
  void _onSearchChanged(String query) {
    _searchDebounceTimer?.cancel();
    if (query.isEmpty) {
      setState(() {
        _globalSearchResults = [];
        _globalSearchLoading = false;
      });
      return;
    }
    setState(() => _globalSearchLoading = true);
    _searchDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performGlobalSearch(query);
    });
  }

  Future<void> _performGlobalSearch(String query) async {
    if (!mounted) return;
    try {
      final result = await ref.read(cardsServiceProvider).searchCatalog(query);

      final results = <dynamic>[];

      // Add releases
      for (final release in result.releases) {
        results.add(('release', release));
      }

      // Add sets
      for (final (set, release) in result.sets) {
        results.add(('set', set, release));
      }

      // Add cards
      for (final (card, set, release) in result.cards) {
        results.add(('card', card, set, release));
      }

      if (mounted) {
        setState(() {
          _globalSearchResults = results;
          _globalSearchLoading = false;
        });
        }
    } catch (e) {
      if (mounted) {
        setState(() => _globalSearchLoading = false);
        AdaptiveSnackBar.show(context, message: 'Search error: $e', type: AdaptiveSnackBarType.error);
      }
    }
  }

Widget _buildSearchMode(ColorScheme colors, double contentTopInset) {
    // Show loader while parallels are loading
    if (_searchSelectedCard != null && _searchParallelsLoading) {
      return Padding(
        padding: EdgeInsets.only(top: contentTopInset),
        child: const Center(child: CardFanLoader()),
      );
    }

    // Show parallel selection if card selected but parallels exist and none chosen yet
    if (_searchSelectedCard != null && _searchParallels.isNotEmpty && !_searchParallelSelected) {
      return Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.only(top: contentTopInset),
              itemCount: _searchParallels.length + 1,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final isBase = i == 0;
                final p = isBase ? null : _searchParallels[i - 1];
                return _buildParallelListTile(
                  parallel: p,
                  onTap: () {
                    setState(() {
                      _searchSelectedParallel = p;
                      _searchParallelName = p?.name ?? 'Base';
                    });
                    if (_searchSelectedCard != null) {
                      _openMasterCardDetail(
                        card: _searchSelectedCard!,
                        parallelName: p?.name ?? 'Base',
                        parallel: p,
                        release: _searchSelectedRelease,
                        set: _searchSelectedSet,
                      );
                    }
                  },
                );
              },
            ),
          ),
        ],
      );
    }

    // Once a search-selected card has no parallels (or has been confirmed via
    // the parallel picker), the catalog falls through and the master card
    // detail screen is opened as a pushed route — see [_openMasterCardDetail]
    // calls in the search-result tap and parallel-tile tap handlers above.

    // Show search results list (search field lives in [_catalogStickyChrome])
    final listPadTop = contentTopInset;
    if (_globalSearchLoading) {
      return Padding(
        padding: EdgeInsets.only(top: listPadTop),
        child: const Center(child: CardFanLoader()),
      );
    }
    if (_globalSearchResults.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: listPadTop),
        child: Center(
          child: Text(
            _globalSearchCtrl.text.isEmpty
                ? 'Search releases, sets, or cards…'
                : 'No results found.',
            style: TextStyle(color: colors.onSurface.withValues(alpha: 0.5)),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.only(top: listPadTop),
      itemCount: _globalSearchResults.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final result = _globalSearchResults[i];
        if (result.$1 == 'release') {
          final release = result.$2 as ReleaseRecord;
          return AdaptiveListTile(
            hideBottomDivider: true,
            title: Text(
              release.displayName,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: release.sport != null ? Text(release.sport!) : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Release', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
            onTap: () {
              setState(() {
                _searchSelectedRelease = release;
                _searchSelectedSet = null;
                _searchSelectedCard = null;
              });
            },
          );
        }
        if (result.$1 == 'set') {
          final set = result.$2 as SetRecord;
          final release = result.$3 as ReleaseRecord;
          return AdaptiveListTile(
            hideBottomDivider: true,
            title: Text(
              set.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(release.displayName, style: const TextStyle(fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Set', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
            onTap: () {
              setState(() {
                _searchSelectedRelease = release;
                _searchSelectedSet = set;
                _searchSelectedCard = null;
              });
            },
          );
        }
        if (result.$1 == 'card') {
          final card = result.$2 as MasterCard;
          final set = result.$3 as SetRecord;
          final release = result.$4 as ReleaseRecord;
          final attrs = _cardAttributePills(card);
          return AdaptiveListTile(
            hideBottomDivider: true,
            title: _buildNameWithAttributes(card.displayName, attrs),
            subtitle: Text('${release.displayName} • ${set.name}', style: const TextStyle(fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Card', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
            onTap: () async {
              setState(() {
                _searchSelectedRelease = release;
                _searchSelectedSet = set;
                _searchSelectedCard = card;
                _searchSelectedParallel = null;
                _searchParallelName = 'Base';
                _searchParallelSelected = false;
                _searchParallelsLoading = true;
              });
              unawaited(ref.read(compsServiceProvider).fetchCardImage(card.id));

              List<SetParallel> parallels = const [];
              try {
                parallels = await ref.read(cardsServiceProvider).getParallels(set.id);
              } catch (_) {
                // Treat fetch errors as "no parallels available" so the user
                // can still open the master card detail.
              }
              if (!mounted) return;
              setState(() {
                _searchParallels = parallels;
                _searchParallelsLoading = false;
              });
              // No parallels for this set → skip the picker and open the
              // detail screen directly with the Base parallel. After the
              // user pops back, clear the search selection so the AppBar
              // title and content fall back to the global results list.
              if (parallels.isEmpty) {
                await _openMasterCardDetail(
                  card: card,
                  parallelName: 'Base',
                  parallel: null,
                  release: release,
                  set: set,
                );
                if (!mounted) return;
                setState(() {
                  _searchSelectedCard = null;
                  _searchSelectedSet = null;
                  _searchSelectedRelease = null;
                  _searchParallels = const [];
                  _searchSelectedParallel = null;
                  _searchParallelName = 'Base';
                });
              }
            },
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

}

// ── New Card Fields Widget ────────────────────────────────────────────────────

class _NewCardFields extends StatelessWidget {
  const _NewCardFields({
    required this.playerCtrl,
    required this.cardNumberCtrl,
    required this.serialMaxCtrl,
    required this.isRookie,
    required this.isAuto,
    required this.isPatch,
    required this.isSSP,
    required this.onToggleRookie,
    required this.onToggleAuto,
    required this.onTogglePatch,
    required this.onToggleSSP,
  });
  final TextEditingController playerCtrl;
  final TextEditingController cardNumberCtrl;
  final TextEditingController serialMaxCtrl;
  final bool isRookie;
  final bool isAuto;
  final bool isPatch;
  final bool isSSP;
  final void Function(bool) onToggleRookie;
  final void Function(bool) onToggleAuto;
  final void Function(bool) onTogglePatch;
  final void Function(bool) onToggleSSP;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _field(context, playerCtrl, 'Player Name *', TextInputType.text),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _field(context, cardNumberCtrl, 'Card #', TextInputType.text)),
          const SizedBox(width: 8),
          Expanded(child: _field(context, serialMaxCtrl, 'Serial Number (e.g. 99)', TextInputType.number)),
        ]),
        const SizedBox(height: 8),
        _toggleRow('RC', isRookie, onToggleRookie),
        const SizedBox(height: 8),
        _toggleRow('AUTO', isAuto, onToggleAuto),
        const SizedBox(height: 8),
        _toggleRow('PATCH', isPatch, onTogglePatch),
        const SizedBox(height: 8),
        _toggleRow('SSP', isSSP, onToggleSSP),
      ],
    );
  }

  Widget _field(BuildContext context, TextEditingController ctrl, String label, TextInputType type) {
    return AdaptiveTextField(
      controller: ctrl,
      keyboardType: type,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      placeholder: label,
      cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(context),
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      ),
    );
  }

  Widget _toggleRow(String label, bool value, void Function(bool) onChanged) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ── Your Copy Fields Widget ───────────────────────────────────────────────────

class _YourCopyFields extends StatelessWidget {
  const _YourCopyFields({
    required this.parallels,
    required this.loadingParallels,
    required this.selectedParallel,
    required this.parallelName,
    required this.pricePaidCtrl,
    this.pricePaidInputFormatters,
    required this.serialNumberCtrl,
    required this.isGraded,
    required this.grader,
    required this.gradeValueCtrl,
    required this.onParallelChanged,
    required this.onParallelNameChanged,
    required this.onGradedChanged,
    required this.onGraderChanged,
  });
  final List<SetParallel> parallels;
  final bool loadingParallels;
  final SetParallel? selectedParallel;
  final String parallelName;
  final TextEditingController pricePaidCtrl;
  final List<TextInputFormatter>? pricePaidInputFormatters;
  final TextEditingController serialNumberCtrl;
  final bool isGraded;
  final String grader;
  final TextEditingController gradeValueCtrl;
  final void Function(SetParallel?) onParallelChanged;
  final void Function(String) onParallelNameChanged;
  final void Function(bool) onGradedChanged;
  final void Function(String) onGraderChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loadingParallels)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (parallels.isNotEmpty)
          AdaptiveDropdown<SetParallel?>(
            value: selectedParallel,
            decoration: InputDecoration(
              labelText: 'Parallel',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Base')),
              ...parallels.map((p) => DropdownMenuItem(value: p, child: Text(p.name))),
            ],
            onChanged: onParallelChanged,
          )
        else
          AdaptiveTextField(
            onChanged: onParallelNameChanged,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            placeholder: 'Parallel (e.g. Silver)',
            cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(context),
            decoration: InputDecoration(
              labelText: 'Parallel (e.g. Silver)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: AdaptiveTextField(
              controller: pricePaidCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: pricePaidInputFormatters,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              placeholder: 'Price Paid',
              cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(context),
              decoration: InputDecoration(
                labelText: 'Price Paid',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AdaptiveTextField(
              controller: serialNumberCtrl,
              keyboardType: TextInputType.text,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              placeholder: 'Serial # (e.g. 34)',
              cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(context),
              decoration: InputDecoration(
                labelText: 'Serial # (e.g. 34)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(
              child: Text('Graded', style: TextStyle(fontSize: 14)),
            ),
            Switch.adaptive(
              value: isGraded,
              onChanged: onGradedChanged,
            ),
          ],
        ),
        if (isGraded) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: AdaptiveDropdown<String>(
                value: grader,
                decoration: InputDecoration(
                  labelText: 'Grader',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
                items: _graders.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                onChanged: (v) => onGraderChanged(v ?? 'PSA'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AdaptiveTextField(
                controller: gradeValueCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                placeholder: 'Grade (e.g. 9.5)',
                cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(context),
                decoration: InputDecoration(
                  labelText: 'Grade (e.g. 9.5)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
            ),
          ]),
        ],
      ],
    );
  }
}

// ── Shared selected chip ──────────────────────────────────────────────────────

class _SelectedChip extends StatelessWidget {
  const _SelectedChip({required this.label, required this.onClear});
  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InfoBox(
      color: colors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 16, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 14, color: colors.primary, fontWeight: FontWeight.w500)),
          ),
          GestureDetector(
            onTap: onClear,
            child: Icon(Icons.close, size: 16, color: colors.onSurface.withValues(alpha: 0.4)),
          ),
        ],
      ),
    );
  }
}
