import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/cards_service.dart';
import '../../core/services/comps_service.dart';
import '../../core/widgets/app_breadcrumb.dart';
import '../../core/widgets/attr_tag.dart';
import '../../core/widgets/info_box.dart';
import '../../core/widgets/card_fan_loader.dart';
import '../wishlist/wishlist_screen.dart';
import '../wishlist/card_sheet.dart';
import 'widgets/card_detail_view.dart';
import 'widgets/card_comps_section.dart';

const _graders = ['PSA', 'BGS', 'SGC', 'CGC', 'CSG'];

const _catalogYears = [
  '2026', '2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018', '2017',
];

const _catalogSports = [
  ('Any sport', ''),
  ('Baseball', 'Baseball'),
  ('Basketball', 'Basketball'),
  ('Football', 'Football'),
  ('Soccer', 'Soccer'),
  ('Hockey', 'Hockey'),
];

enum _CatalogStep { browsing, sets, card, detail, addCopy }

class AddCardScreen extends ConsumerStatefulWidget {
  const AddCardScreen({super.key});

  @override
  ConsumerState<AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends ConsumerState<AddCardScreen> {
  // ── Catalog step ─────────────────────────────────────────────
  _CatalogStep _catalogStep = _CatalogStep.browsing;
  String _catalogFilterYear = '';
  String _catalogFilterSport = '';
  final _browseSearchCtrl = TextEditingController();

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
  int _cardPage = 0;
  static const int _cardPageSize = 50;
  bool _cardHasMore = false;

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
  bool _isGraded = false;
  String _grader = 'PSA';
  final _gradeValueCtrl = TextEditingController();

  bool _saving = false;


  @override
  void initState() {
    super.initState();
    _loadBrowseReleases(reset: true);
  }

  @override
  void dispose() {
    _browseSearchCtrl.dispose();
    _setSearchCtrl.dispose();
    _cardCtrl.dispose();
    _newPlayerCtrl.dispose();
    _newCardNumberCtrl.dispose();
    _newSerialMaxCtrl.dispose();
    _pricePaidCtrl.dispose();
    _serialNumberCtrl.dispose();
    _gradeValueCtrl.dispose();
    super.dispose();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load sets: $e'), backgroundColor: Colors.red),
        );
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _lazyImporting = false);
    }
  }

  // ── Card search ───────────────────────────────────────────────

  void _searchCards(String query) {
    if (_selectedSet == null) {
      setState(() { _cardResults = []; _cardHasMore = false; });
      return;
    }
    final q = query.toLowerCase();
    final filtered = _allCards.where((card) {
      final player = card.player.toLowerCase();
      return player.contains(q);
    }).toList();
    setState(() {
      _cardResults = filtered;
      _cardHasMore = false;
    });
  }

  void _selectCard(MasterCard card) {
    setState(() {
      _selectedCard = card;
      _cardCtrl.text = card.displayName;
      _cardResults = [];
      _cardHasMore = false;
      _cardPage = 0;
      _isNewCard = false;
      _catalogStep = _CatalogStep.detail;
    });
    // Lazily fetch card image from CardSight
    ref.read(compsServiceProvider).fetchCardImage(card.id);
  }

  void _selectParallel(SetParallel? p) {
    setState(() {
      _selectedParallel = p;
      _parallelName = p?.name ?? 'Base';
    });
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
      final newCardId = await ref.read(cardsServiceProvider).addCard(form);
      ref.invalidate(userCardsProvider);
      unawaited(ref.read(compsServiceProvider).refreshCardValue(newCardId).catchError((e) {
        print('[refreshCardValue error] $e');
      }));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Card added!'), duration: Duration(seconds: 2)),
        );
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showAddCopySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CardSheet(
        title: 'Add to Your Collection',
        card: _selectedCard,
        setName: _selectedSet?.name,
        releaseName: _selectedRelease?.displayName,
        showParallel: true,
        parallels: _parallels,
        selectedParallel: _selectedParallel,
        onParallelChanged: (p) => setState(() {
          _selectedParallel = p;
          _parallelName = p?.name ?? 'Base';
        }),
        showPricePaid: true,
        pricePaidCtrl: _pricePaidCtrl,
        showSerialNumber: (_selectedParallel?.name ?? _parallelName).contains('/'),
        serialNumberCtrl: _serialNumberCtrl,
        showGraded: true,
        isGraded: _isGraded,
        grader: _grader,
        gradeValueCtrl: _gradeValueCtrl,
        onGradedChanged: (v) => setState(() => _isGraded = v),
        onGraderChanged: (g) => setState(() => _grader = g ?? 'PSA'),
        onSave: (data) async {
          if (!_canSave) return 'Unable to save';
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
            final newCardId = await ref.read(cardsServiceProvider).addCard(form);
            ref.invalidate(userCardsProvider);
            unawaited(ref.read(compsServiceProvider).refreshCardValue(newCardId).catchError((e) {
              print('[refreshCardValue error] $e');
            }));
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Card added!'), duration: Duration(seconds: 2)),
              );
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
            }
            return null;
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
              );
            }
            return e.toString();
          } finally {
            if (mounted) setState(() => _saving = false);
          }
        },
      ),
    );
  }

  void _showAddToWishlist() {
    final watchWordsCtrl = TextEditingController();
    final targetPriceCtrl = TextEditingController();
    final gradeValueCtrl = TextEditingController();
    var selectedParallel = _selectedParallel;
    var isGraded = false;
    var grader = 'PSA';

    // Fetch card image if not already cached
    if (_selectedCard?.id != null) {
      ref.read(compsServiceProvider).fetchCardImage(_selectedCard!.id);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setState) => CardSheet(
          title: 'Add to Wishlist',
          card: _selectedCard,
          year: _selectedRelease?.year,
          setName: _selectedRelease?.name,
          releaseName: _selectedRelease?.displayName,
          showParallel: true,
          parallels: _parallels,
          selectedParallel: selectedParallel,
          onParallelChanged: (p) => setState(() {
            selectedParallel = p;
          }),
          showWatchWords: true,
          watchWordsCtrl: watchWordsCtrl,
          showTargetPrice: true,
          targetPriceCtrl: targetPriceCtrl,
          showGraded: true,
          isGraded: isGraded,
          grader: grader,
          gradeValueCtrl: gradeValueCtrl,
          onGradedChanged: (v) => setState(() => isGraded = v),
          onGraderChanged: (g) => setState(() => grader = g ?? 'PSA'),
          onSave: (data) async {
            try {
              final grade = isGraded && gradeValueCtrl.text.trim().isNotEmpty
                  ? '$grader ${gradeValueCtrl.text.trim()}'
                  : null;
              await ref.read(wishlistProvider.notifier).add({
                'player': (_selectedCard?.player ?? '').trim(),
                'year': _selectedRelease?.year,
                'set_name': _selectedRelease?.name,
                'card_number': (_selectedCard?.cardNumber ?? '').trim(),
                'parallel': (selectedParallel?.name ?? 'Base').trim(),
                'is_rookie': _selectedCard?.isRookie ?? false,
                'is_auto': _selectedCard?.isAuto ?? false,
                'is_patch': _selectedCard?.isPatch ?? false,
                'serial_max': _selectedCard?.serialMax,
                'grade': grade,
                'ebay_query': null,
                'exclude_terms': [],
                'target_price': double.tryParse(targetPriceCtrl.text),
                'master_card_id': _selectedCard?.id,
                'release_id': _selectedRelease?.id,
                'set_id': _selectedSet?.id,
                'sport': _selectedRelease?.sport,
              });
              ref.invalidate(wishlistProvider);
              if (sheetContext.mounted) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(content: Text('Added to Wishlist!'), duration: Duration(seconds: 2)),
                );
              }
              return null;
            } catch (e) {
              return e.toString();
            }
          },
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: switch (_catalogStep) {
        _CatalogStep.browsing => _buildBrowseView(colors),
        _CatalogStep.sets     => _buildSetsView(colors),
        _CatalogStep.card     => _buildCardSearchView(colors),
        _CatalogStep.detail   => _buildCardDetailView(colors),
        _CatalogStep.addCopy  => _buildYourCopyFormView(colors),
      },
    );
  }

  // ── Browse view (release list) ────────────────────────────────

  Widget _buildBrowseView(ColorScheme colors) {
    final searchQuery = _browseSearchCtrl.text.toLowerCase();
    final filtered = _browseResults.where((r) {
      final name = r.displayName.toLowerCase();
      final sport = (r.sport ?? '').toLowerCase();
      return name.contains(searchQuery) || sport.contains(searchQuery);
    }).toList();

    return Column(
      children: [
        AppBreadcrumb(
          current: 'Catalog',
          onBack: () => context.pop(),
        ),
        // Filter row
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.outline.withValues(alpha: 0.12))),
          ),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _catalogFilterYear,
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
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _catalogFilterSport,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  ),
                  items: _catalogSports.map((s) => DropdownMenuItem(
                    value: s.$2,
                    child: Text(s.$1, style: const TextStyle(fontSize: 13)),
                  )).toList(),
                  onChanged: (v) {
                    setState(() {
                      _catalogFilterSport = v ?? '';
                      _browseSearchCtrl.clear();
                    });
                    _loadBrowseReleases(reset: true);
                  },
                ),
              ),
            ],
          ),
        ),
        // Search bar
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.outline.withValues(alpha: 0.12))),
          ),
          child: TextField(
            controller: _browseSearchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search releases…',
              hintStyle: TextStyle(fontSize: 14, color: colors.onSurface.withValues(alpha: 0.4)),
              prefixIcon: Icon(Icons.search, size: 18, color: colors.onSurface.withValues(alpha: 0.4)),
              suffixIcon: _browseSearchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() => _browseSearchCtrl.clear()),
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
          ),
        ),
        // Release list
        Expanded(
          child: _browseLoading && _browseResults.isEmpty
              ? const Center(child: CardFanLoader())
              : filtered.isEmpty
                  ? Center(
                      child: Text(
                        _browseResults.isEmpty
                            ? 'No releases found.\nTry a different year or sport.'
                            : 'No results match your search.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurface.withValues(alpha: 0.5)),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length + (_browseHasMore && filtered.length == _browseResults.length ? 1 : 0),
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        if (i == filtered.length) {
                          return _browseLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(child: CircularProgressIndicator()),
                                )
                              : ListTile(
                                  title: Text('Load more',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: colors.primary, fontSize: 14)),
                                  onTap: _loadBrowseReleases,
                                );
                        }
                        final r = filtered[i];
                        return ListTile(
                          title: Text(r.displayName,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                          subtitle: r.sport != null
                              ? Text(r.sport!, style: const TextStyle(fontSize: 12))
                              : null,
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: () => _selectBrowseRelease(r),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // ── Sets view ─────────────────────────────────────────────────

  Widget _buildSetsView(ColorScheme colors) {
    final searchQuery = _setSearchCtrl.text.toLowerCase();
    final filtered = _browseSets.where((s) {
      return s.name.toLowerCase().contains(searchQuery);
    }).toList();

    return Column(
      children: [
        AppBreadcrumb(
          parent: 'Catalog',
          current: _browseSelectedRelease?.displayName ?? '',
          onBack: () => setState(() {
            _catalogStep = _CatalogStep.browsing;
            _browseSelectedRelease = null;
            _browseSets = [];
            _setSearchCtrl.clear();
          }),
        ),
        // Search bar
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.outline.withValues(alpha: 0.12))),
          ),
          child: TextField(
            controller: _setSearchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search sets…',
              hintStyle: TextStyle(fontSize: 14, color: colors.onSurface.withValues(alpha: 0.4)),
              prefixIcon: Icon(Icons.search, size: 18, color: colors.onSurface.withValues(alpha: 0.4)),
              suffixIcon: _setSearchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() => _setSearchCtrl.clear()),
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: _browseSetsLoading || _lazyImporting
              ? const Center(child: CardFanLoader())
              : filtered.isEmpty
                  ? Center(
                      child: Text(
                        _browseSets.isEmpty ? 'No sets found.' : 'No results match your search.',
                        style: TextStyle(color: colors.onSurface.withValues(alpha: 0.5)),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final s = filtered[i];
                        return ListTile(
                          title: Text(s.name,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                          subtitle: s.cardCount != null
                              ? Text('${s.cardCount} cards', style: const TextStyle(fontSize: 12))
                              : null,
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: () => _selectBrowseSet(s),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // ── Card search view ─────────────────────────────────────────────────────

  Widget _buildCardSearchView(ColorScheme colors) {
    return Column(
      children: [
        AppBreadcrumb(
          grandparent: 'Catalog',
          onGrandparentBack: () => setState(() {
            _catalogStep = _CatalogStep.browsing;
            _browseSelectedRelease = null;
            _browseSets = [];
            _selectedCard = null;
            _cardCtrl.clear();
            _cardResults = [];
            _isNewCard = false;
            _selectedRelease = null;
            _selectedSet = null;
          }),
          parent: _browseSelectedRelease?.displayName ?? _selectedRelease?.displayName ?? '',
          onBack: () => setState(() {
            _catalogStep = _CatalogStep.sets;
            _selectedCard = null;
            _cardCtrl.clear();
            _cardResults = [];
            _isNewCard = false;
            _selectedSet = null;
          }),
          current: _selectedSet?.name ?? '',
        ),
        // Search field
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _cardCtrl,
            onChanged: _searchCards,
            decoration: InputDecoration(
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
        ),
        // Content area fills remaining space
        Expanded(child: _buildCardResultsArea(colors)),
      ],
    );
  }

  // ── Card detail view (read-only, showing Add to Collection/Wishlist buttons) ──

  Widget _buildCardDetailView(ColorScheme colors) {
    return Column(
      children: [
        AppBreadcrumb(
          items: [
            BreadcrumbItem(label: 'Catalog', onTap: () => setState(() {
              _catalogStep = _CatalogStep.browsing;
              _browseSelectedRelease = null;
              _browseSets = [];
              _selectedCard = null;
              _cardCtrl.clear();
              _cardResults = [];
              _isNewCard = false;
              _selectedRelease = null;
              _selectedSet = null;
            })),
            BreadcrumbItem(
              label: _browseSelectedRelease?.displayName ?? _selectedRelease?.displayName ?? '',
              onTap: () => setState(() {
                _catalogStep = _CatalogStep.sets;
                _selectedCard = null;
                _cardCtrl.clear();
                _cardResults = [];
                _isNewCard = false;
              }),
            ),
            BreadcrumbItem(
              label: _selectedSet?.name ?? '',
              onTap: () => setState(() {
                _catalogStep = _CatalogStep.card;
                _selectedCard = null;
                _cardCtrl.clear();
                _cardResults = _allCards;
                _isNewCard = false;
              }),
            ),
            BreadcrumbItem(label: _selectedCard?.player ?? ''),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
              // Parallel selector
              if (_parallels.isNotEmpty)
                DropdownButtonFormField<SetParallel?>(
                  initialValue: _selectedParallel,
                  decoration: InputDecoration(
                    labelText: 'Parallel',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Base')),
                    ..._parallels.map((p) => DropdownMenuItem(value: p, child: Text(p.name))),
                  ],
                  onChanged: (p) => setState(() {
                    _selectedParallel = p;
                    _parallelName = p?.name ?? 'Base';
                  }),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No parallels for this set',
                    style: TextStyle(fontSize: 13, color: colors.onSurface.withValues(alpha: 0.6)),
                  ),
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
                            final cardMatch = card.masterCardId == _selectedCard?.id;
                            final cardNumberMatch = (card.cardNumber?.trim() ?? '') ==
                                (_selectedCard?.cardNumber?.trim() ?? '');
                            final parallelMatch = card.parallel.trim() == selectedParallelName.trim();
                            return cardMatch && cardNumberMatch && parallelMatch;
                          }).length;
                        }).value ?? 0;

                        return copyCount > 0
                            ? FilledButton.icon(
                                onPressed: null,
                                icon: TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0.0, end: 1.0),
                                  duration: const Duration(milliseconds: 800),
                                  curve: Curves.elasticOut,
                                  builder: (context, scale, child) {
                                    return Transform.scale(
                                      scale: scale,
                                      child: child,
                                    );
                                  },
                                  child: const Icon(Icons.check_circle, size: 18),
                                ),
                                label: Text('In Collection ($copyCount)'),
                              )
                            : FilledButton(
                                onPressed: _showAddCopySheet,
                                child: const Text('Add to Collection'),
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
                                (_selectedCard?.player.trim().toLowerCase() ?? '');
                            final cardNumberMatch = (item.cardNumber?.trim() ?? '') ==
                                (_selectedCard?.cardNumber?.trim() ?? '');
                            final parallelMatch = (item.parallel?.trim() ?? 'Base') ==
                                selectedParallelName.trim();
                            return playerMatch && cardNumberMatch && parallelMatch;
                          });
                        }).value ?? false;

                        return isInWishlist
                            ? FilledButton.icon(
                                onPressed: null,
                                icon: TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0.0, end: 1.0),
                                  duration: const Duration(milliseconds: 800),
                                  curve: Curves.elasticOut,
                                  builder: (context, scale, child) {
                                    return Transform.scale(
                                      scale: scale,
                                      child: child,
                                    );
                                  },
                                  child: const Icon(Icons.favorite, size: 18),
                                ),
                                label: const Text('In Wishlist'),
                              )
                            : OutlinedButton.icon(
                                onPressed: () => _showAddToWishlist(),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.favorite_border, size: 18),
                                label: const Text('Add to Wishlist'),
                              );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
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

  Widget _buildYourCopyFormView(ColorScheme colors) {
    return Column(
      children: [
        AppBreadcrumb(
          grandparent: 'Catalog',
          onGrandparentBack: () => setState(() {
            _catalogStep = _CatalogStep.browsing;
            _browseSelectedRelease = null;
            _browseSets = [];
            _selectedCard = null;
            _cardCtrl.clear();
            _cardResults = [];
            _isNewCard = false;
            _selectedRelease = null;
            _selectedSet = null;
          }),
          parent: _browseSelectedRelease?.displayName ?? _selectedRelease?.displayName ?? '',
          onBack: () => setState(() {
            _catalogStep = _CatalogStep.detail;
            _pricePaidCtrl.clear();
            _serialNumberCtrl.clear();
            _isGraded = false;
            _grader = 'PSA';
            _gradeValueCtrl.clear();
            _parallelName = 'Base';
            _selectedParallel = null;
          }),
          current: _selectedSet?.name ?? '',
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
              FilledButton(
                onPressed: _canSave ? _save : null,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Add to Collection'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Card results area ─────────────────────────────────────────

  Widget _buildCardResultsArea(ColorScheme colors) {
    if (_loadingCards) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_cardResults.isEmpty) {
      return Center(
        child: Text('No cards found.',
            style: TextStyle(color: colors.onSurface.withValues(alpha: 0.4))),
      );
    }
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: _cardResults.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final c = _cardResults[i];
              final attrs = _cardAttributePills(c);
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _selectCard(c),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  c.displayName,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                ),
                                if (attrs != null) ...[
                                  const SizedBox(height: 4),
                                  attrs,
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right, size: 18, color: Color(0xFF9CA3AF)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget? _cardAttributePills(MasterCard c) {
    final hasAttrs = c.isRookie || c.isAuto || c.isPatch || c.isSSP || c.serialMax != null;
    if (!hasAttrs) return null;
    return Wrap(
      spacing: 4,
      children: [
        if (c.isRookie) AttrTag('RC', color: const Color(0xFF16A34A)),
        if (c.isAuto) AttrTag('AUTO', color: const Color(0xFF7C3AED)),
        if (c.isPatch) AttrTag('PATCH', color: const Color(0xFF0369A1)),
        if (c.isSSP) AttrTag('SSP', color: const Color(0xFFEA580C)),
        if (c.serialMax != null) AttrTag('/${c.serialMax}', color: const Color(0xFF6366F1)),
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
        _field(playerCtrl, 'Player Name *', TextInputType.text),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _field(cardNumberCtrl, 'Card #', TextInputType.text)),
          const SizedBox(width: 8),
          Expanded(child: _field(serialMaxCtrl, 'Serial Number (e.g. 99)', TextInputType.number)),
        ]),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilterChip(label: const Text('RC'), selected: isRookie, onSelected: onToggleRookie),
            FilterChip(label: const Text('AUTO'), selected: isAuto, onSelected: onToggleAuto),
            FilterChip(label: const Text('PATCH'), selected: isPatch, onSelected: onTogglePatch),
            FilterChip(label: const Text('SSP'), selected: isSSP, onSelected: onToggleSSP),
          ],
        ),
      ],
    );
  }

  Widget _field(TextEditingController ctrl, String label, TextInputType type) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      ),
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
          DropdownButtonFormField<SetParallel?>(
            initialValue: selectedParallel,
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
          TextField(
            onChanged: onParallelNameChanged,
            decoration: InputDecoration(
              labelText: 'Parallel (e.g. Silver)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: pricePaidCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
            child: TextField(
              controller: serialNumberCtrl,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                labelText: 'Serial # (e.g. 34)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Graded', style: TextStyle(fontSize: 14)),
          value: isGraded,
          onChanged: onGradedChanged,
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        if (isGraded) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: grader,
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
              child: TextField(
                controller: gradeValueCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
