import 'dart:async';
import 'dart:convert';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/cards_service.dart';
import '../../core/services/comps_service.dart';
import '../../core/utils/adaptive_ui.dart';
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
import '../../core/widgets/sticky_chrome_scaffold.dart';
import '../wishlist/wishlist_screen.dart';
import '../wishlist/card_sheet.dart';
import '../scan/scan_screen.dart';
import 'master_card_detail_screen.dart';
import 'widgets/active_state_indicator.dart';
import 'widgets/card_detail_view.dart';
import 'widgets/card_comps_section.dart';
import 'widgets/filter_sort_action_bar.dart';

/// First-frame hints for [StickyChromeScaffold.stickyHeightEstimate] until layout measures.
const double _kStickyEstSegment = 52;
const double _kStickyEstBrowsePlus = 118;
const double _kStickyEstSetSearch = 72;
const double _kStickyEstCardSearch = 72;
const double _kStickyEstGlobalSearch = 64;

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

const _graders = ['PSA', 'BGS', 'SGC', 'CGC', 'CSG'];

const _catalogYears = [
  '2026', '2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018', '2017',
];

enum _CatalogStep { sportPicker, browsing, sets, card, parallel, detail, addCopy }
enum _CatalogMode { browse, search }

/// When set, catalog opens on the card detail step (e.g. after a scan).
class CatalogScanEntry {
  const CatalogScanEntry({required this.detection, required this.sport});
  final CardSightDetection detection;
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
  final _loadingCards = false;
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

  bool _saving = false;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final entry = widget.scanEntry;
      if (entry != null) {
        await _openCatalogFromScan(entry.detection, entry.sport);
      } else {
        await _restoreNavigationState();
      }
    });
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

  Future<void> _openCatalogFromScan(CardSightDetection detection, String sport) async {
    if (!mounted) return;
    final card = detection.card;
    if (card.id == null || card.releaseId == null || card.setId == null) {
      if (mounted) {
        AdaptiveSnackBar.show(
          context,
          message: 'This match is incomplete — browse the catalog to find the card.',
          type: AdaptiveSnackBarType.info,
        );
        await _restoreNavigationState();
      }
      return;
    }

    try {
      final year = int.tryParse(card.year ?? '') ?? DateTime.now().year;
      final releaseName = (card.releaseName?.trim().isNotEmpty == true)
          ? card.releaseName!
          : (card.manufacturer ?? 'Unknown Release');

      final csResult = CardSightCardResult(
        id: card.id!,
        name: card.name ?? '',
        number: card.number,
        setId: card.setId!,
        setName: card.setName ?? '',
        releaseId: card.releaseId!,
        attributes: const [],
      );

      final svc = ref.read(cardsServiceProvider);
      final resolved = await svc.resolveCardFromCatalog(
        card: csResult,
        releaseName: releaseName,
        releaseYear: year,
        releaseSegmentId: card.segmentId ?? '',
      );

      final relSet = await svc.getReleaseAndSetForSetId(resolved.setId);
      var cards = await svc.searchMasterCards(resolved.setId, '', limit: 10000);
      final master = cards.where((c) => c.id == resolved.masterCardId).firstOrNull ??
          await svc.fetchMasterCardById(resolved.masterCardId);
      if (master == null) throw StateError('Card not found in catalog');
      if (!cards.any((c) => c.id == master.id)) {
        cards = [...cards, master];
      }

      final scanParallel = card.parallel;
      String normalizeParallelName(String name) =>
          name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      SetParallel? matchedParallel;
      if (scanParallel != null && scanParallel.name.isNotEmpty) {
        final target = normalizeParallelName(scanParallel.name);
        for (final p in resolved.parallels) {
          final candidate = normalizeParallelName(p.name);
          if (candidate == target || candidate.contains(target) || target.contains(candidate)) {
            matchedParallel = p;
            break;
          }
        }
      }
      final parallelLabel = scanParallel?.name ?? 'Base';
      final effectiveParallel = switch ((matchedParallel, scanParallel)) {
        (SetParallel p, ParallelInfo s) when p.serialMax == null && s.numberedTo != null => SetParallel(
            id: p.id,
            name: p.name,
            serialMax: s.numberedTo,
            isAuto: p.isAuto,
          ),
        (SetParallel p, _) => p,
        (_, ParallelInfo s) when s.name.isNotEmpty => SetParallel(
            id: s.id.isNotEmpty ? s.id : '__scan_parallel__',
            name: s.name,
            serialMax: s.numberedTo,
          ),
        _ => null,
      };

      if (!mounted) return;
      setState(() {
        _mode = _CatalogMode.browse;
        _catalogFilterSport = sport;
        _browseSelectedRelease = relSet.release;
        _selectedRelease = relSet.release;
        _browseSets = [];
        _selectedSet = relSet.set;
        _parallels = resolved.parallels;
        _selectedParallel = matchedParallel;
        _parallelName = parallelLabel;
        _allCards = cards;
        _cardResults = cards;
        _selectedCard = master;
        _cardCtrl.text = master.displayName;
        _isNewCard = false;
        _catalogStep = resolved.parallels.isEmpty
            ? _CatalogStep.card
            : _CatalogStep.parallel;
        _restoringState = false;
      });
      unawaited(_saveNavigationState());
      unawaited(ref.read(compsServiceProvider).fetchCardImage(master.id));
      _openMasterCardDetail(
        card: master,
        parallelName: parallelLabel,
        parallel: effectiveParallel,
        release: relSet.release,
        set: relSet.set,
      );
    } catch (_) {
      if (mounted) {
        AdaptiveSnackBar.show(
          context,
          message: 'Could not open this card in the catalog. Try browsing manually.',
          type: AdaptiveSnackBarType.error,
        );
        await _restoreNavigationState();
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
      } else if (release.cardsightId != null) {
        await ref.read(cardsServiceProvider).importSetsForRelease(
          cardsightReleaseId: release.cardsightId!,
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
      if (parallels.isEmpty && set.cardsightId != null) {
        final result = await ref.read(cardsServiceProvider).lazyImportCatalog(
          cardsightReleaseId: release.cardsightId!,
          releaseName:        release.name,
          releaseYear:        release.year?.toString() ?? '',
          releaseSegmentId:   '',
          cardsightSetId:     set.cardsightId!,
        );
        parallels = result.parallels;
      }

      // Lazy-load cards if needed
      var cards = await ref.read(cardsServiceProvider).searchMasterCards(set.id, '', limit: 10000);
      if (cards.isEmpty && set.cardsightId != null && release.cardsightId != null) {
        await ref.read(cardsServiceProvider).importCardsForSet(
          cardsightReleaseId: release.cardsightId!,
          cardsightSetId: set.cardsightId!,
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
    final q = query.toLowerCase();
    final filtered = _allCards.where((card) {
      final player = card.player.toLowerCase();
      return player.contains(q);
    }).toList();
    setState(() {
      _cardResults = filtered;
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
  /// and [parallelName] so the existing [_showAddCopySheet] / [_addToWishlist]
  /// handlers (which read from [_mode]-scoped state) work when the buttons
  /// fire from the pushed screen.
  Future<void> _openMasterCardDetail({
    required MasterCard card,
    required String parallelName,
    SetParallel? parallel,
    ReleaseRecord? release,
    SetRecord? set,
  }) async {
    // Goes through go_router (`context.push`) rather than an imperative
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
        masterCard: MasterCard(
          id: card.id,
          player: card.player,
          cardNumber: card.cardNumber,
          isRookie: card.isRookie,
          isAuto: card.isAuto || (parallel?.isAuto ?? false),
          isPatch: card.isPatch,
          isSSP: card.isSSP,
          serialMax: parallel?.serialMax ?? card.serialMax,
          imageUrl: card.imageUrl,
        ),
        parallelName: parallelName,
        parallelSerialMax: parallel?.serialMax,
        parallelIsAuto: parallel?.isAuto ?? false,
        releaseName: release?.name,
        setName: set?.name,
        year: release?.year,
        sport: release?.sport,
        onAddToCollection: _showAddCopySheet,
        onAddToWishlist: _addToWishlist,
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
      final form = AddCardFormData(
        masterCardId: _selectedCard?.id,
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
        pricePaid: double.tryParse(_pricePaidCtrl.text.trim()),
        serialNumber: _serialNumberCtrl.text.trim().isEmpty ? null : _serialNumberCtrl.text.trim(),
        isGraded: _isGraded,
        grader: _isGraded ? _grader : 'PSA',
        gradeValue: _isGraded && _gradeValueCtrl.text.trim().isNotEmpty ? _gradeValueCtrl.text.trim() : null,
      );
      final created = await ref.read(cardsServiceProvider).addCard(form);
      ref.invalidate(userCardsProvider);
      unawaited(
        ref.read(compsServiceProvider).refreshCardValue(created.userCardId).catchError((_) {}),
      );
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

  void _showAddCopySheet() {
    final card = _mode == _CatalogMode.search ? _searchSelectedCard : _selectedCard;
    final set = _mode == _CatalogMode.search ? _searchSelectedSet : _selectedSet;
    final release = _mode == _CatalogMode.search ? _searchSelectedRelease : _selectedRelease;
    final selectedParallel = _mode == _CatalogMode.search ? _searchSelectedParallel : _selectedParallel;

    showAdaptiveSheet(
      context: context,
      builder: (_) => CardSheet(
        title: 'Add to Your Collection',
        card: card,
        setName: set?.name,
        releaseName: release?.displayName,
        previewParallelName: _mode == _CatalogMode.search ? _searchParallelName : _parallelName,
        previewParallelSerialMax: selectedParallel?.serialMax,
        previewParallelIsAuto: selectedParallel?.isAuto ?? false,
        showPricePaid: true,
        pricePaidCtrl: _pricePaidCtrl,
        showSerialNumber: selectedParallel?.serialMax != null,
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
            final parallelName = _mode == _CatalogMode.search ? _searchParallelName : _parallelName;
            final form = AddCardFormData(
              masterCardId: card?.id,
              setId: set?.id,
              player: card?.player ?? '',
              cardNumber: card?.cardNumber,
              serialMax: card?.serialMax,
              isRookie: card?.isRookie ?? false,
              isAuto: card?.isAuto ?? false,
              isPatch: card?.isPatch ?? false,
              isSSP: card?.isSSP ?? false,
              parallelId: selectedParallel?.id,
              parallelName: parallelName,
              pricePaid: double.tryParse(_pricePaidCtrl.text.trim()),
              serialNumber: _serialNumberCtrl.text.trim().isEmpty ? null : _serialNumberCtrl.text.trim(),
              isGraded: _isGraded,
              grader: _isGraded ? _grader : 'PSA',
              gradeValue: _isGraded && _gradeValueCtrl.text.trim().isNotEmpty ? _gradeValueCtrl.text.trim() : null,
            );
            final created = await ref.read(cardsServiceProvider).addCard(form);
            ref.invalidate(userCardsProvider);
            unawaited(
              ref.read(compsServiceProvider).refreshCardValue(created.userCardId).catchError((_) {}),
            );
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

  Future<void> _addToWishlist() async {
    final card = _mode == _CatalogMode.search ? _searchSelectedCard : _selectedCard;
    final set = _mode == _CatalogMode.search ? _searchSelectedSet : _selectedSet;
    final release = _mode == _CatalogMode.search ? _searchSelectedRelease : _selectedRelease;
    final parallelName = _mode == _CatalogMode.search ? _searchParallelName : (_selectedParallel?.name ?? 'Base');

    showAdaptiveSheet(
      context: context,
      builder: (_) => CardSheet(
        title: 'Add to Wishlist',
        card: card,
        setName: set?.name,
        releaseName: release?.displayName,
        previewParallelName: parallelName,
        previewParallelSerialMax: (_mode == _CatalogMode.search ? _searchSelectedParallel : _selectedParallel)?.serialMax,
        previewParallelIsAuto: (_mode == _CatalogMode.search ? _searchSelectedParallel : _selectedParallel)?.isAuto ?? false,
        showTargetPrice: true,
        targetPriceCtrl: _targetPriceCtrl,
        showGraded: false,
        onSave: (_) async {
          try {
            await ref.read(wishlistProvider.notifier).add({
              'player': (card?.player ?? '').trim(),
              'year': release?.year,
              'set_name': release?.name,
              'card_number': (card?.cardNumber ?? '').trim(),
              'parallel': parallelName,
              'is_rookie': card?.isRookie ?? false,
              'is_auto': card?.isAuto ?? false,
              'is_patch': card?.isPatch ?? false,
              'serial_max': card?.serialMax,
              'grade': null,
              'ebay_query': null,
              'exclude_terms': [],
              'target_price': double.tryParse(_targetPriceCtrl.text.trim()),
              'master_card_id': card?.id,
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: AdaptiveTextField(
            controller: _browseSearchCtrl,
            onChanged: (_) => setState(() {}),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            placeholder: 'Search releases…',
            prefixIcon: Icon(Icons.search, size: 18, color: colors.onSurface.withValues(alpha: 0.4)),
            suffixIcon: _browseSearchCtrl.text.isNotEmpty
                ? GestureDetector(
                    onTap: () => setState(() => _browseSearchCtrl.clear()),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.close, size: 16),
                    ),
                  )
                : null,
            cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(context, radius: 10),
            decoration: InputDecoration(
              labelText: 'Search releases',
              hintText: 'Search releases…',
              hintStyle: TextStyle(fontSize: 14, color: colors.onSurface.withValues(alpha: 0.4)),
              prefixIcon: Icon(Icons.search, size: 18, color: colors.onSurface.withValues(alpha: 0.4)),
              suffixIcon: _browseSearchCtrl.text.isNotEmpty
                  ? GestureDetector(
                      onTap: () => setState(() => _browseSearchCtrl.clear()),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.close, size: 16),
                      ),
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
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

    if (_restoringState) {
      return (
        child: _catalogSegmentRow(colors, hasSecondaryChrome: false),
        heightEstimate: segmentEst,
      );
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
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: FilterSortActionBar<void>(
          searchText: _globalSearchCtrl.text,
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: AdaptiveTextField(
            controller: _setSearchCtrl,
            onChanged: (_) => setState(() {}),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            placeholder: 'Search sets…',
            prefixIcon: Icon(Icons.search, size: 18, color: colors.onSurface.withValues(alpha: 0.4)),
            suffixIcon: _setSearchCtrl.text.isNotEmpty
                ? GestureDetector(
                    onTap: () => setState(() => _setSearchCtrl.clear()),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.close, size: 16),
                    ),
                  )
                : null,
            cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(context, radius: 10),
            decoration: InputDecoration(
              labelText: 'Search sets',
              hintText: 'Search sets…',
              hintStyle: TextStyle(fontSize: 14, color: colors.onSurface.withValues(alpha: 0.4)),
              prefixIcon: Icon(Icons.search, size: 18, color: colors.onSurface.withValues(alpha: 0.4)),
              suffixIcon: _setSearchCtrl.text.isNotEmpty
                  ? GestureDetector(
                      onTap: () => setState(() => _setSearchCtrl.clear()),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.close, size: 16),
                      ),
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
          ),
        );
        break;
      case _CatalogStep.card:
        secondaryHeight = _kStickyEstCardSearch;
        secondary = Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: AdaptiveTextField(
            controller: _cardCtrl,
            onChanged: _searchCards,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            placeholder: 'Search player name…',
            prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF9CA3AF)),
            suffixIcon: _loadingCards
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
            cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(context),
            decoration: InputDecoration(
              labelText: 'Search players',
              hintText: 'Search player name…',
              hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
              prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF9CA3AF)),
              suffixIcon: _loadingCards
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
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
          if (secondary != null) secondary,
        ],
      ),
      heightEstimate: segmentEst + secondaryHeight,
    );
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final sticky = _catalogStickyChrome(colors);
    return StickyChromeScaffold(
      stickyHeightEstimate: sticky.heightEstimate,
      stickyChrome: sticky.child,
      appBar: buildGlassNavBar(
        context,
        useBlurBackground: true,
        leading: (_catalogStep == _CatalogStep.sportPicker && _mode == _CatalogMode.browse) ||
                 (_mode == _CatalogMode.search && _searchSelectedCard == null)
            ? null
            : AppBarGlassCircleButton(
                onPressed: _handleStepBack,
                icon: Icons.chevron_left,
              ),
        centerTitle: false,
        title: Text(
          _appBarTitle(),
          style: AppFonts.appBarTitle.copyWith(color: colors.onSurface),
        ),
        actions: appBarShellTrailingActions(
          context,
          omitShellTrailing: _omitCatalogShellTrailing,
        ),
      ),
      bodyBuilder: (context, contentTopInset) {
        if (_restoringState) {
          return Padding(
            padding: EdgeInsets.only(top: contentTopInset),
            child: const Center(child: CardFanLoader()),
          );
        }
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

    if (_browseLoading && _browseResults.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: listPadTop),
        child: const Center(child: CardFanLoader()),
      );
    }
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
    if (_browseSetsLoading || _lazyImporting) {
      return Padding(
        padding: EdgeInsets.only(top: listPadTop),
        child: const Center(child: CardFanLoader()),
      );
    }
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
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: Consumer(
                      builder: (context, ref, child) {
                        final userCardsAsync = ref.watch(userCardsProvider);
                        final copyCount = userCardsAsync.whenData((allCards) {
                          if (_selectedCard == null) return 0;
                          final selectedParallelName = _selectedParallel?.name ?? 'Base';
                          return allCards.where((card) {
                            final cardMatch = card.masterCardId == _selectedCard!.id;
                            final cardNumberMatch = (card.cardNumber?.trim() ?? '') ==
                                (_selectedCard!.cardNumber?.trim() ?? '');
                            final parallelMatch = card.parallel.trim() == selectedParallelName.trim();
                            return cardMatch && cardNumberMatch && parallelMatch;
                          }).length;
                        }).value ?? 0;

                        return copyCount > 0
                            ? ActiveStateIndicator(
                                icon: Icons.check_circle,
                                label: 'In Collection ($copyCount)',
                                animateIcon: true,
                              )
                            : AdaptiveButton.child(
                                onPressed: _showAddCopySheet,
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
                          if (_selectedCard == null) return false;
                          final selectedParallelName = _selectedParallel?.name ?? 'Base';
                          return wishlist.any((item) {
                            final playerMatch = (item.player?.trim().toLowerCase() ?? '') ==
                                (_selectedCard!.player.trim().toLowerCase());
                            final cardNumberMatch = (item.cardNumber?.trim() ?? '') ==
                                (_selectedCard!.cardNumber?.trim() ?? '');
                            final parallelMatch = (item.parallel?.trim() ?? 'Base') ==
                                selectedParallelName.trim();
                            return playerMatch && cardNumberMatch && parallelMatch;
                          });
                        }).value ?? false;

                        return isInWishlist
                            ? const ActiveStateIndicator(
                                icon: Icons.favorite,
                                label: 'In Wishlist',
                                animateIcon: true,
                              )
                            : AdaptiveButton.child(
                                onPressed: _addToWishlist,
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
                              );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Comps section
              if (_selectedCard != null)
                CardCompsSection(
                  masterCardId: _selectedCard!.id,
                  parallelName: _selectedParallel?.name ?? 'Base',
                  initialGrade: 'Raw',
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
    if (_loadingCards) {
      return Padding(
        padding: EdgeInsets.only(top: topInset),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              placeholder: 'Price Paid',
              cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(context),
              decoration: InputDecoration(
                labelText: 'Price Paid',
                prefixText: '\$ ',
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
