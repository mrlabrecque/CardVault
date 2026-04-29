import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/cards_service.dart';
import '../../core/services/comps_service.dart';
import '../../core/widgets/attr_tag.dart';
import '../../core/widgets/app_breadcrumb.dart';
import '../../core/widgets/info_box.dart';
import '../../core/widgets/card_fan_loader.dart';
import '../../core/widgets/adaptive_dropdown.dart';

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

class _StagedCard {
  _StagedCard({
    required this.tempId,
    required this.masterCardId,
    required this.setId,
    required this.player,
    this.cardNumber,
    this.setName,
    this.parallelId,
    this.parallelName = 'Base',
    this.serialMax,
    this.serialNumber,
    this.isRookie = false,
    this.isAuto = false,
    this.isPatch = false,
    this.isSSP = false,
    this.pricePaid,
    this.isGraded = false,
    this.grader,
    this.gradeValue,
  });
  final String tempId;
  final String masterCardId;
  final String setId;
  final String player;
  final String? cardNumber;
  final String? setName;
  final String? parallelId;
  final String parallelName;
  final int? serialMax;
  final String? serialNumber;
  final bool isRookie;
  final bool isAuto;
  final bool isPatch;
  final bool isSSP;
  final double? pricePaid;
  final bool isGraded;
  final String? grader;
  final String? gradeValue;
}

class BulkAddScreen extends ConsumerStatefulWidget {
  const BulkAddScreen({super.key});

  @override
  ConsumerState<BulkAddScreen> createState() => _BulkAddScreenState();
}

class _BulkAddScreenState extends ConsumerState<BulkAddScreen> {
  // ── Catalog filters ──────────────────────────────────────────
  String _catalogFilterYear = '';
  String _catalogFilterSport = '';

  // ── Release browse ───────────────────────────────────────────
  List<ReleaseRecord> _browseResults = [];
  bool _browseLoading = false;
  int _browseOffset = 0;
  static const int _browsePageSize = 30;

  // ── Session ──────────────────────────────────────────────────
  ReleaseRecord? _selectedRelease;

  // ── Box price calculator ─────────────────────────────────────
  final _boxPriceCtrl = TextEditingController();
  final _boxQtyCtrl = TextEditingController();
  double? get _pricePerCard {
    final price = double.tryParse(_boxPriceCtrl.text);
    final qty = int.tryParse(_boxQtyCtrl.text);
    if (price == null || qty == null || qty <= 0) return null;
    return (price / qty * 100).roundToDouble() / 100;
  }

  // ── Card search (cross-release via CardSight) ────────────────
  final _cardCtrl = TextEditingController();
  List<CardSightCardResult> _cardResults = [];
  bool _loadingCards = false;
  bool _resolvingCard = false;

  // ── Resolved card (after resolveCardFromCatalog) ──────────────
  MasterCard? _selectedCard;
  CardSightCardResult? _selectedCsCard;
  String? _selectedSetId;
  List<SetParallel> _parallels = [];

  // ── Parallels ────────────────────────────────────────────────
  SetParallel? _selectedParallel;
  String _parallelName = 'Base';

  // ── Your copy ────────────────────────────────────────────────
  final _pricePaidCtrl = TextEditingController();
  final _serialNumberCtrl = TextEditingController();
  bool _isGraded = false;
  String _grader = 'PSA';
  final _gradeValueCtrl = TextEditingController();

  // ── Staging ──────────────────────────────────────────────────
  final List<_StagedCard> _staged = [];
  bool _committing = false;
  int _tempIdCounter = 0;

  @override
  void initState() {
    super.initState();
    _loadBrowseReleases(reset: true);
  }

  @override
  void dispose() {
    _boxPriceCtrl.dispose();
    _boxQtyCtrl.dispose();
    _cardCtrl.dispose();
    _pricePaidCtrl.dispose();
    _serialNumberCtrl.dispose();
    _gradeValueCtrl.dispose();
    super.dispose();
  }

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
        _browseOffset = _browseResults.length;
      });
    } finally {
      setState(() => _browseLoading = false);
    }
  }


  void _selectRelease(ReleaseRecord release) {
    setState(() {
      _selectedRelease = release;
      _resetCardForm();
    });
  }

  Future<void> _searchCards(String q) async {
    if (q.isEmpty) {
      setState(() { _cardResults = []; });
      return;
    }
    final release = _selectedRelease;
    if (release == null || release.cardsightId == null) return;

    setState(() { _loadingCards = true; });
    try {
      final svc = ref.read(cardsServiceProvider);
      final results = await svc.searchCardsInRelease(release.cardsightId!, q, take: 20);
      setState(() { _cardResults = results; _loadingCards = false; });
    } catch (_) {
      setState(() { _loadingCards = false; });
    }
  }

  Future<void> _selectCsCard(CardSightCardResult csCard) async {
    setState(() { _resolvingCard = true; _cardResults = []; });
    _cardCtrl.text = csCard.number != null ? '${csCard.name} #${csCard.number}' : csCard.name;

    try {
      final release = _selectedRelease!;
      final svc = ref.read(cardsServiceProvider);
      final result = await svc.resolveCardFromCatalog(
        card: csCard,
        releaseName: release.name,
        releaseYear: release.year ?? DateTime.now().year,
        releaseSegmentId: null,
      );

      if (!mounted) return;
      final ppc = _pricePerCard;
      setState(() {
        _selectedCard = MasterCard(
          id: result.masterCardId,
          player: csCard.name,
          cardNumber: csCard.number,
          isRookie: csCard.attributes.contains('RC'),
          isAuto: csCard.attributes.contains('AU'),
          isPatch: csCard.attributes.contains('GU'),
          isSSP: csCard.attributes.contains('SSP'),
        );
        _selectedCsCard = csCard;
        _selectedSetId = result.setId;
        _parallels = result.parallels;
        _selectedParallel = null;
        _parallelName = 'Base';
        if (ppc != null) {
          _pricePaidCtrl.text = ppc.toStringAsFixed(2);
        }
        _resolvingCard = false;
      });
      // Lazily fetch card image from CardSight
      ref.read(compsServiceProvider).fetchCardImage(result.masterCardId);
    } catch (_) {
      if (!mounted) return;
      setState(() { _resolvingCard = false; });
    }
  }

  void _clearCardSelection() {
    setState(() {
      _selectedCard = null;
      _selectedCsCard = null;
      _selectedSetId = null;
      _cardCtrl.clear();
      _cardResults = [];
      _parallels = [];
      _selectedParallel = null;
      _parallelName = 'Base';
      _pricePaidCtrl.clear();
      _serialNumberCtrl.clear();
      _isGraded = false;
      _grader = 'PSA';
      _gradeValueCtrl.clear();
    });
  }

  bool get _canStage {
    if (_selectedCard == null) return false;
    if (_pricePaidCtrl.text.isEmpty) return false;
    if (double.tryParse(_pricePaidCtrl.text) == null) return false;
    if (_isGraded && _gradeValueCtrl.text.trim().isEmpty) return false;
    return true;
  }

  void _stageCard() {
    if (!_canStage) return;
    final card = _selectedCard!;
    final csCard = _selectedCsCard!;
    final pricePaid = double.parse(_pricePaidCtrl.text);

    _staged.add(_StagedCard(
      tempId: '${_tempIdCounter++}',
      masterCardId: card.id,
      setId: _selectedSetId ?? '',
      player: card.player,
      cardNumber: card.cardNumber,
      setName: csCard.setName,
      parallelId: _selectedParallel?.id,
      parallelName: _parallelName,
      serialMax: card.serialMax,
      serialNumber: _serialNumberCtrl.text,
      isRookie: card.isRookie,
      isAuto: card.isAuto,
      isPatch: card.isPatch,
      isSSP: card.isSSP,
      pricePaid: pricePaid,
      isGraded: _isGraded,
      grader: _grader,
      gradeValue: _gradeValueCtrl.text,
    ));

    _resetCardForm();
    // Restore price per card after reset
    final ppc = _pricePerCard;
    if (ppc != null) {
      _pricePaidCtrl.text = ppc.toStringAsFixed(2);
    }

    setState(() {});
  }

  void _resetCardForm() {
    _cardCtrl.clear();
    _cardResults = [];
    _selectedCard = null;
    _selectedCsCard = null;
    _parallels = [];
    _selectedParallel = null;
    _parallelName = 'Base';
    _pricePaidCtrl.clear();
    _serialNumberCtrl.clear();
    _isGraded = false;
    _grader = 'PSA';
    _gradeValueCtrl.clear();
  }

  void _removeStagedCard(int index) {
    _staged.removeAt(index);
    setState(() {});
  }

  Future<void> _commitAll() async {
    if (_staged.isEmpty) return;
    setState(() { _committing = true; });

    try {
      final svc = ref.read(cardsServiceProvider);

      for (final staged in _staged) {
        final cardId = await svc.addCard(AddCardFormData(
          masterCardId: staged.masterCardId,
          player: staged.player,
          cardNumber: staged.cardNumber,
          parallelId: staged.parallelId,
          parallelName: staged.parallelName,
          pricePaid: staged.pricePaid,
          serialNumber: staged.serialNumber,
          isGraded: staged.isGraded,
          grader: staged.grader ?? 'PSA',
          gradeValue: staged.gradeValue,
          isRookie: staged.isRookie,
          isAuto: staged.isAuto,
          isPatch: staged.isPatch,
          isSSP: staged.isSSP,
        ));

        // Fetch pricing from scrapechain (fire-and-forget)
        unawaited(ref.read(compsServiceProvider).refreshCardValue(cardId).catchError((_) {
          // Pricing fetch failed, but card was added — user can refresh later
        }));
      }

      // Invalidate the cards provider to refresh the list
      ref.invalidate(userCardsProvider);

      if (!mounted) return;
      setState(() { _committing = false; _staged.clear(); });
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() { _committing = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (_selectedRelease == null) {
      return _buildBrowseView(colors);
    }
    return _buildBulkAddView(context, colors);
  }

  Widget _buildBrowseView(ColorScheme colors) {
    return Scaffold(
      body: Column(
        children: [
          AppBreadcrumb(
            parent: 'Collection',
            current: 'Bulk Add',
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
                      });
                      _loadBrowseReleases(reset: true);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AdaptiveDropdown<String>(
                    value: _catalogFilterSport,
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
                      });
                      _loadBrowseReleases(reset: true);
                    },
                  ),
                ),
              ],
            ),
          ),
          // Release list
          Expanded(
            child: _browseLoading && _browseResults.isEmpty
                ? const Center(child: CardFanLoader())
                : _browseResults.isEmpty
                    ? Center(
                        child: Text(
                          'No releases found.\nTry a different year or sport.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.onSurface.withValues(alpha: 0.5)),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _browseResults.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final r = _browseResults[i];
                          return ListTile(
                            title: Text(r.displayName,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            subtitle: r.sport != null
                                ? Text(r.sport!, style: const TextStyle(fontSize: 12))
                                : null,
                            trailing: const Icon(Icons.chevron_right, size: 18),
                            onTap: () => _selectRelease(r),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulkAddView(BuildContext context, ColorScheme colors) {
    return Scaffold(
      body: Column(
        children: [
          AppBreadcrumb(
            grandparent: 'Collection',
            parent: 'Bulk Add',
            current: _selectedRelease!.displayName,
            onBack: () => setState(() => _selectedRelease = null),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              // ── BOX CALCULATOR ──
              if (_selectedRelease != null) ...[
                const Text('Box Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _boxPriceCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Box Price',
                          prefixText: '\$',
                          isDense: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _boxQtyCtrl,
                        decoration: const InputDecoration(
                          labelText: '# Cards',
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                if (_pricePerCard != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '\$${_pricePerCard!.toStringAsFixed(2)} per card',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                const SizedBox(height: 24),

                // ── CARD ENTRY ──
                const Text('Add Card', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _cardCtrl,
                        decoration: InputDecoration(
                          hintText: 'Player or card #...',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        enabled: _selectedRelease?.cardsightId != null,
                        onChanged: (q) => setState(() => _cardResults = []),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _selectedRelease?.cardsightId != null && _cardCtrl.text.isNotEmpty && !_loadingCards
                          ? () => _searchCards(_cardCtrl.text)
                          : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: _loadingCards ? 0.4 : 1.0),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _loadingCards
                            ? const Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                ),
                              )
                            : const Icon(Icons.search, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
                if (_selectedRelease?.cardsightId == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'This release is not linked to CardSight',
                      style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                    ),
                  ),
                if (_cardResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: _cardResults.map((card) => ListTile(
                        title: Text(card.name, style: const TextStyle(fontSize: 13)),
                        subtitle: Row(
                          children: [
                            if (card.number != null) ...[
                              Text('#${card.number}', style: const TextStyle(fontSize: 11)),
                              const SizedBox(width: 8),
                            ],
                            Text(card.setName, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                            if (card.attributes.contains('RC')) ...[
                              const SizedBox(width: 4),
                              const AttrTag('RC'),
                            ],
                            if (card.attributes.contains('AU')) ...[
                              const SizedBox(width: 4),
                              const AttrTag('AU'),
                            ],
                          ],
                        ),
                        dense: true,
                        onTap: () => _selectCsCard(card),
                      )).toList(),
                    ),
                  ),
                if (_resolvingCard)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Center(
                      child: Column(
                        children: [
                          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(height: 8),
                          const Text('Loading card...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),

                // ── SELECTED CARD ──
                if (_selectedCard != null) ...[
                  const SizedBox(height: 12),
                  InfoBox(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedCard!.player,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (_selectedCard!.cardNumber != null) ...[
                                    Text('#${_selectedCard!.cardNumber}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                    const SizedBox(width: 8),
                                  ],
                                  Text(_selectedCsCard!.setName, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                  if (_selectedCard!.isRookie) ...[
                                    const SizedBox(width: 4),
                                    const AttrTag('RC'),
                                  ],
                                  if (_selectedCard!.isAuto) ...[
                                    const SizedBox(width: 4),
                                    const AttrTag('AU'),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _clearCardSelection,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),

                  // ── YOUR COPY ──
                  const SizedBox(height: 16),
                  const Text('Your Copy', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 12),
                  AdaptiveDropdown<String>(
                    value: _parallelName,
                    decoration: const InputDecoration(
                      labelText: 'Parallel',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: [
                      const DropdownMenuItem(value: 'Base', child: Text('Base'))
                    ] + _parallels.map((p) => DropdownMenuItem(
                      value: p.name,
                      child: Text('${p.name}${p.serialMax != null ? ' /${p.serialMax}' : ''}'),
                    )).toList(),
                    onChanged: (name) {
                      if (name == null) return;
                      setState(() {
                        _parallelName = name;
                        _selectedParallel = _parallels.firstWhere((p) => p.name == name, orElse: () => SetParallel(id: '', name: name));
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pricePaidCtrl,
                    enabled: false,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Price Paid',
                      prefixText: '\$',
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _serialNumberCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Serial #',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Graded', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                      GestureDetector(
                        onTap: () => setState(() => _isGraded = !_isGraded),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 44, height: 24,
                          decoration: BoxDecoration(
                            color: _isGraded ? const Color(0xFF800020) : Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _isGraded ? const Color(0xFF800020) : Theme.of(context).colorScheme.outline),
                          ),
                          child: AnimatedAlign(
                            duration: const Duration(milliseconds: 200),
                            alignment: _isGraded ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.all(3),
                              width: 18, height: 18,
                              decoration: BoxDecoration(
                                color: _isGraded ? Colors.white : Theme.of(context).colorScheme.outline,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_isGraded) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: AdaptiveDropdown<String>(
                            value: _grader,
                            decoration: const InputDecoration(
                              labelText: 'Grader',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            items: _graders.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                            onChanged: (g) => setState(() { _grader = g ?? 'PSA'; }),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _gradeValueCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Grade',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _canStage ? _stageCard : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Add to Batch'),
                    ),
                  ),
                ],
              ],

              // ── STAGED LIST ──
              if (_staged.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Batch (${_staged.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 8),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _staged.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (_, idx) {
                    final card = _staged[idx];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  card.cardNumber != null ? '${card.player} #${card.cardNumber}' : card.player,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${card.setName ?? '—'} · ${card.parallelName} · \$${card.pricePaid?.toStringAsFixed(2) ?? '—'}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                                if (card.isGraded)
                                  Text(
                                    '${card.grader} ${card.gradeValue}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => _removeStagedCard(idx),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 80),
            ],
          ),
        ),
            ),
          ),
          ],
        ),
      bottomSheet: _staged.isNotEmpty
          ? Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(context).padding.bottom + 12,
              ),
              color: Colors.white,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _committing ? null : _commitAll,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _committing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                      : Text('Save ${_staged.length} Cards to Collection'),
                ),
              ),
            )
          : null,
    );
  }
}
