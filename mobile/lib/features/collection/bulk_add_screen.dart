import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/cards_service.dart';
import '../../core/widgets/serial_tag.dart';
import '../../core/widgets/attr_tag.dart';

const _graders = ['PSA', 'BGS', 'SGC', 'CGC', 'CSG'];

class _StagedCard {
  _StagedCard({
    required this.tempId,
    this.masterCardId,
    this.setId,
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
    this.newSerialMax,
    this.newIsRookie = false,
    this.newIsAuto = false,
    this.newIsPatch = false,
    this.newIsSSP = false,
  });
  final String tempId;
  final String? masterCardId;
  final String? setId;
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
  final int? newSerialMax;
  final bool newIsRookie;
  final bool newIsAuto;
  final bool newIsPatch;
  final bool newIsSSP;
}

class BulkAddScreen extends ConsumerStatefulWidget {
  const BulkAddScreen({super.key});

  @override
  ConsumerState<BulkAddScreen> createState() => _BulkAddScreenState();
}

class _BulkAddScreenState extends ConsumerState<BulkAddScreen> {
  // ── Session ──────────────────────────────────────────────────
  ReleaseRecord? _selectedRelease;
  List<SetRecord> _sets = [];
  SetRecord? _selectedSet;
  List<SetParallel> _parallels = [];
  bool _loadingReleases = false;
  bool _loadingSets = false;

  // ── Box price calculator ─────────────────────────────────────
  final _boxPriceCtrl = TextEditingController();
  final _boxQtyCtrl = TextEditingController();
  double? get _pricePerCard {
    final price = double.tryParse(_boxPriceCtrl.text);
    final qty = int.tryParse(_boxQtyCtrl.text);
    if (price == null || qty == null || qty <= 0) return null;
    return (price / qty * 100).roundToDouble() / 100;
  }

  // ── Release search ───────────────────────────────────────────
  final _releaseCtrl = TextEditingController();
  List<ReleaseRecord> _releaseResults = [];

  // ── Card search ──────────────────────────────────────────────
  final _cardCtrl = TextEditingController();
  List<MasterCard> _cardResults = [];
  bool _loadingCards = false;
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

  // ── Your copy ────────────────────────────────────────────────
  SetParallel? _selectedParallel;
  String _parallelName = 'Base';
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
    _boxPriceCtrl.addListener(_onBoxCalcChanged);
    _boxQtyCtrl.addListener(_onBoxCalcChanged);
  }

  @override
  void dispose() {
    _releaseCtrl.dispose();
    _cardCtrl.dispose();
    _newPlayerCtrl.dispose();
    _newCardNumberCtrl.dispose();
    _newSerialMaxCtrl.dispose();
    _boxPriceCtrl.dispose();
    _boxQtyCtrl.dispose();
    _pricePaidCtrl.dispose();
    _serialNumberCtrl.dispose();
    _gradeValueCtrl.dispose();
    super.dispose();
  }

  void _onBoxCalcChanged() {
    final ppc = _pricePerCard;
    if (ppc != null) {
      final formatted = ppc == ppc.truncateToDouble() ? ppc.toStringAsFixed(0) : ppc.toStringAsFixed(2);
      if (_pricePaidCtrl.text != formatted) {
        _pricePaidCtrl.text = formatted;
      }
    }
    setState(() {});
  }

  Future<void> _searchReleases(String q) async {
    setState(() => _loadingReleases = true);
    try {
      final r = await ref.read(cardsServiceProvider).searchReleases(q);
      if (mounted) setState(() => _releaseResults = r);
    } finally {
      if (mounted) setState(() => _loadingReleases = false);
    }
  }

  Future<void> _selectRelease(ReleaseRecord r) async {
    setState(() {
      _selectedRelease = r;
      _releaseCtrl.text = r.displayName;
      _releaseResults = [];
      _selectedSet = null;
      _sets = [];
      _parallels = [];
      _selectedCard = null;
      _cardCtrl.clear();
      _isNewCard = false;
      _cardResults = [];
      _loadingSets = true;
    });
    try {
      final sets = await ref.read(cardsServiceProvider).getSetsForRelease(r.id);
      if (mounted) {
        setState(() => _sets = sets);
        if (sets.length == 1) await _selectSet(sets.first);
      }
    } finally {
      if (mounted) setState(() => _loadingSets = false);
    }
  }

  Future<void> _selectSet(SetRecord s) async {
    setState(() {
      _selectedSet = s;
      _selectedCard = null;
      _cardCtrl.clear();
      _cardResults = [];
      _isNewCard = false;
      _parallels = [];
      _selectedParallel = null;
      _parallelName = 'Base';
    });
    final parallels = await ref.read(cardsServiceProvider).getParallels(s.id);
    if (mounted) setState(() => _parallels = parallels);
  }

  Future<void> _searchCards(String q) async {
    if (_selectedSet == null) return;
    setState(() => _loadingCards = true);
    try {
      final r = await ref.read(cardsServiceProvider).searchMasterCards(_selectedSet!.id, q);
      if (mounted) setState(() => _cardResults = r);
    } finally {
      if (mounted) setState(() => _loadingCards = false);
    }
  }

  void _selectCard(MasterCard card) {
    setState(() {
      _selectedCard = card;
      _cardCtrl.text = card.displayName;
      _cardResults = [];
      _isNewCard = false;
    });
  }

  bool get _canStage {
    final hasCard = _selectedCard != null || (_isNewCard && _newPlayerCtrl.text.trim().isNotEmpty);
    final hasPricePaid = double.tryParse(_pricePaidCtrl.text) != null;
    final gradeOk = !_isGraded || _gradeValueCtrl.text.trim().isNotEmpty;
    return hasCard && hasPricePaid && gradeOk;
  }

  void _stageCard() {
    if (!_canStage) return;
    final card = _selectedCard;
    final isNew = _isNewCard;
    _staged.add(_StagedCard(
      tempId: '${_tempIdCounter++}',
      masterCardId: card?.id,
      setId: _selectedSet?.id,
      player: isNew ? _newPlayerCtrl.text.trim() : (card?.player ?? ''),
      cardNumber: isNew ? (_newCardNumberCtrl.text.trim().isEmpty ? null : _newCardNumberCtrl.text.trim()) : card?.cardNumber,
      setName: _selectedSet?.name,
      parallelId: _selectedParallel?.id,
      parallelName: _parallelName,
      serialMax: _selectedParallel?.serialMax ?? card?.serialMax,
      serialNumber: _serialNumberCtrl.text.trim().isEmpty ? null : _serialNumberCtrl.text.trim(),
      isRookie: card?.isRookie ?? false,
      isAuto: card?.isAuto ?? false,
      isPatch: card?.isPatch ?? false,
      isSSP: card?.isSSP ?? false,
      pricePaid: double.tryParse(_pricePaidCtrl.text),
      isGraded: _isGraded,
      grader: _isGraded ? _grader : null,
      gradeValue: _isGraded ? _gradeValueCtrl.text.trim() : null,
      newSerialMax: isNew ? int.tryParse(_newSerialMaxCtrl.text.trim()) : null,
      newIsRookie: isNew ? _newIsRookie : false,
      newIsAuto: isNew ? _newIsAuto : false,
      newIsPatch: isNew ? _newIsPatch : false,
      newIsSSP: isNew ? _newIsSSP : false,
    ));

    // Reset card-level fields; keep parallel + box calc
    setState(() {
      _selectedCard = null;
      _cardCtrl.clear();
      _isNewCard = false;
      _newPlayerCtrl.clear();
      _newCardNumberCtrl.clear();
      _newSerialMaxCtrl.clear();
      _newIsRookie = false;
      _newIsAuto = false;
      _newIsPatch = false;
      _newIsSSP = false;
      _serialNumberCtrl.clear();
      _isGraded = false;
      _gradeValueCtrl.clear();
      // Only reset price if not from box calc
      if (_pricePerCard == null) _pricePaidCtrl.clear();
    });
  }

  Future<void> _commitAll() async {
    if (_staged.isEmpty) return;
    setState(() => _committing = true);
    try {
      final svc = ref.read(cardsServiceProvider);
      for (final c in _staged) {
        await svc.addCard(AddCardFormData(
          masterCardId: c.masterCardId,
          setId: c.setId,
          player: c.player,
          cardNumber: c.cardNumber,
          serialMax: c.newSerialMax,
          isRookie: c.newIsRookie,
          isAuto: c.newIsAuto,
          isPatch: c.newIsPatch,
          isSSP: c.newIsSSP,
          parallelId: c.parallelId,
          parallelName: c.parallelName,
          pricePaid: c.pricePaid,
          serialNumber: c.serialNumber,
          isGraded: c.isGraded,
          grader: c.grader ?? 'PSA',
          gradeValue: c.gradeValue,
        ));
      }
      ref.invalidate(userCardsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_staged.length} card${_staged.length == 1 ? '' : 's'} saved!'), duration: const Duration(seconds: 2)),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _committing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasSession = _selectedRelease != null && _selectedSet != null;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _selectedRelease != null ? _selectedRelease!.displayName : 'Bulk Add',
              style: const TextStyle(fontSize: 17),
            ),
            if (_selectedSet != null)
              Text(_selectedSet!.name, style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.6))),
          ],
        ),
        actions: [
          if (_selectedRelease != null)
            TextButton(
              onPressed: () => setState(() {
                _selectedRelease = null;
                _releaseCtrl.clear();
                _sets = [];
                _selectedSet = null;
                _parallels = [];
                _selectedCard = null;
                _cardCtrl.clear();
                _isNewCard = false;
                _cardResults = [];
                _releaseResults = [];
              }),
              child: const Text('Change'),
            ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.only(left: 16, right: 16, top: 8, bottom: _staged.isNotEmpty ? 88 : 24),
            children: [
              // ── Release search ──────────────────────────────
              if (_selectedRelease == null) ...[
                _sectionLabel('Release', colors),
                const SizedBox(height: 8),
                TextField(
                  controller: _releaseCtrl,
                  onChanged: _searchReleases,
                  decoration: InputDecoration(
                    hintText: 'Search releases…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _loadingReleases
                        ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                ),
                if (_releaseResults.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _Dropdown(
                    children: _releaseResults.take(8).map((r) => ListTile(
                      dense: true,
                      title: Text(r.displayName, style: const TextStyle(fontSize: 14)),
                      subtitle: r.sport != null ? Text(r.sport!, style: const TextStyle(fontSize: 12)) : null,
                      onTap: () => _selectRelease(r),
                    )).toList(),
                  ),
                ],
              ],

              // ── Set picker ──────────────────────────────────
              if (_selectedRelease != null && _selectedSet == null) ...[
                const SizedBox(height: 16),
                _sectionLabel('Set', colors),
                const SizedBox(height: 8),
                if (_loadingSets)
                  const Center(child: CircularProgressIndicator())
                else
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _sets.map((s) => ActionChip(
                      label: Text(s.name, style: const TextStyle(fontSize: 13)),
                      onPressed: () => _selectSet(s),
                    )).toList(),
                  ),
              ],

              // ── Set tabs (when session active, multiple sets) ─
              if (hasSession && _sets.length > 1) ...[
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _sets.map((s) {
                      final active = s.id == _selectedSet?.id;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: active ? null : () => _selectSet(s),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: active ? const Color(0xFF800020) : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: active ? const Color(0xFF800020) : colors.outline.withValues(alpha: 0.4)),
                            ),
                            child: Text(s.name, style: TextStyle(fontSize: 13, color: active ? Colors.white : colors.onSurface, fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // ── Box price calculator ────────────────────────
              if (hasSession) ...[
                const SizedBox(height: 4),
                _BoxPriceCalculator(
                  boxPriceCtrl: _boxPriceCtrl,
                  boxQtyCtrl: _boxQtyCtrl,
                  pricePerCard: _pricePerCard,
                ),
                const SizedBox(height: 20),

                // ── Card search ─────────────────────────────
                _sectionLabel('Card', colors),
                const SizedBox(height: 8),
                if (_selectedCard != null)
                  _SelectedChip(label: _selectedCard!.displayName, onClear: () => setState(() {
                    _selectedCard = null;
                    _cardCtrl.clear();
                    _isNewCard = false;
                  }))
                else if (_isNewCard)
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: colors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                      child: Text('New Card', style: TextStyle(fontSize: 13, color: colors.primary, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    TextButton(onPressed: () => setState(() { _isNewCard = false; _cardCtrl.clear(); }), child: const Text('Cancel')),
                  ])
                else ...[
                  TextField(
                    controller: _cardCtrl,
                    onChanged: _searchCards,
                    decoration: InputDecoration(
                      hintText: 'Search player name…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _loadingCards
                          ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                  ),
                  if (_cardResults.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _Dropdown(
                      maxHeight: 220,
                      children: [
                        ..._cardResults.map((c) => ListTile(
                          dense: true,
                          title: Text(c.player, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                          subtitle: _cardMeta(c),
                          onTap: () => _selectCard(c),
                        )),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => setState(() { _isNewCard = true; _cardCtrl.clear(); _cardResults = []; }),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Not in checklist? Add manually'),
                    style: OutlinedButton.styleFrom(textStyle: const TextStyle(fontSize: 13)),
                  ),
                ],

                // ── New card fields ─────────────────────────
                if (_isNewCard) ...[
                  const SizedBox(height: 12),
                  _NewCardFields(
                    playerCtrl: _newPlayerCtrl,
                    cardNumberCtrl: _newCardNumberCtrl,
                    serialMaxCtrl: _newSerialMaxCtrl,
                    isRookie: _newIsRookie, isAuto: _newIsAuto, isPatch: _newIsPatch, isSSP: _newIsSSP,
                    onToggleRookie: (v) => setState(() => _newIsRookie = v),
                    onToggleAuto: (v) => setState(() => _newIsAuto = v),
                    onTogglePatch: (v) => setState(() => _newIsPatch = v),
                    onToggleSSP: (v) => setState(() => _newIsSSP = v),
                  ),
                ],

                // ── Your copy ───────────────────────────────
                if (_selectedCard != null || _isNewCard) ...[
                  const SizedBox(height: 20),
                  _sectionLabel('Your Copy', colors),
                  const SizedBox(height: 8),
                  if (_parallels.isNotEmpty)
                    DropdownButtonFormField<SetParallel?>(
                      initialValue: _selectedParallel,
                      decoration: InputDecoration(labelText: 'Parallel', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), isDense: true),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Base')),
                        ..._parallels.map((p) => DropdownMenuItem(value: p, child: Text(p.name))),
                      ],
                      onChanged: (p) => setState(() { _selectedParallel = p; _parallelName = p?.name ?? 'Base'; }),
                    )
                  else
                    TextField(
                      onChanged: (v) => setState(() => _parallelName = v.trim().isEmpty ? 'Base' : v.trim()),
                      decoration: InputDecoration(labelText: 'Parallel (e.g. Silver)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), isDense: true),
                    ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _pricePaidCtrl,
                        readOnly: _pricePerCard != null,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Price Paid *',
                          prefixText: '\$ ',
                          suffixText: _pricePerCard != null ? 'from box' : null,
                          suffixStyle: const TextStyle(fontSize: 11, color: Color(0xFF800020)),
                          filled: _pricePerCard != null,
                          fillColor: _pricePerCard != null ? Colors.grey.withValues(alpha: 0.1) : null,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _serialNumberCtrl,
                        decoration: InputDecoration(labelText: 'Serial #', hintText: 'e.g. 45/99', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), isDense: true),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  // Graded toggle
                  GestureDetector(
                    onTap: () => setState(() => _isGraded = !_isGraded),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: _isGraded ? const Color(0xFF800020) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _isGraded ? const Color(0xFF800020) : colors.outline.withValues(alpha: 0.4)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.verified_outlined, size: 16, color: _isGraded ? Colors.white : colors.onSurface.withValues(alpha: 0.6)),
                        const SizedBox(width: 6),
                        Text('Graded', style: TextStyle(fontSize: 13, color: _isGraded ? Colors.white : colors.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w500)),
                      ]),
                    ),
                  ),
                  if (_isGraded) ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _grader,
                          decoration: InputDecoration(labelText: 'Grader', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), isDense: true),
                          items: _graders.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                          onChanged: (v) => setState(() => _grader = v ?? 'PSA'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _gradeValueCtrl,
                          onChanged: (_) => setState(() {}),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(labelText: 'Grade *', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), isDense: true),
                        ),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _canStage ? _stageCard : null,
                      style: FilledButton.styleFrom(backgroundColor: _canStage ? const Color(0xFF800020) : null),
                      child: const Text('Add to Batch'),
                    ),
                  ),
                ],
              ],

              // ── Staged list ─────────────────────────────────
              if (_staged.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(children: [
                  Text('Batch (${_staged.length})', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 8),
                ...List.generate(_staged.length, (i) {
                  final c = _staged[i];
                  return _StagedCardTile(
                    card: c,
                    onRemove: () => setState(() => _staged.removeAt(i)),
                  );
                }),
              ],
            ],
          ),

          // ── Sticky commit bar ────────────────────────────────
          if (_staged.isNotEmpty)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: Border(top: BorderSide(color: colors.outline.withValues(alpha: 0.2))),
                ),
                child: FilledButton(
                  onPressed: _committing ? null : _commitAll,
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF800020), minimumSize: const Size(double.infinity, 48)),
                  child: _committing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Save ${_staged.length} Card${_staged.length == 1 ? '' : 's'} to Collection'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label, ColorScheme colors) => Text(
    label,
    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurface.withValues(alpha: 0.6), letterSpacing: 0.5),
  );

  Widget? _cardMeta(MasterCard c) {
    final parts = <String>[
      if (c.cardNumber != null) '#${c.cardNumber}',
      if (c.isRookie) 'RC',
      if (c.isAuto) 'AUTO',
      if (c.isPatch) 'PATCH',
      if (c.serialMax != null) '/${c.serialMax}',
    ];
    if (parts.isEmpty) return null;
    return Text(parts.join(' · '), style: const TextStyle(fontSize: 12));
  }
}

// ── Box Price Calculator ──────────────────────────────────────────────────────

class _BoxPriceCalculator extends StatelessWidget {
  const _BoxPriceCalculator({required this.boxPriceCtrl, required this.boxQtyCtrl, required this.pricePerCard});
  final TextEditingController boxPriceCtrl;
  final TextEditingController boxQtyCtrl;
  final double? pricePerCard;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: boxPriceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Box Price',
              prefixText: '\$ ',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
              filled: true,
              fillColor: colors.surface,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: boxQtyCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Cards / Box',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
              filled: true,
              fillColor: colors.surface,
            ),
          ),
        ),
        if (pricePerCard != null) ...[
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('\$${pricePerCard!.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF800020))),
            const Text('per card', style: TextStyle(fontSize: 10, color: Colors.grey)),
          ]),
        ],
      ]),
    );
  }
}

// ── New Card Fields ───────────────────────────────────────────────────────────

class _NewCardFields extends StatelessWidget {
  const _NewCardFields({
    required this.playerCtrl, required this.cardNumberCtrl, required this.serialMaxCtrl,
    required this.isRookie, required this.isAuto, required this.isPatch, required this.isSSP,
    required this.onToggleRookie, required this.onToggleAuto, required this.onTogglePatch, required this.onToggleSSP,
  });
  final TextEditingController playerCtrl, cardNumberCtrl, serialMaxCtrl;
  final bool isRookie, isAuto, isPatch, isSSP;
  final void Function(bool) onToggleRookie, onToggleAuto, onTogglePatch, onToggleSSP;

  @override
  Widget build(BuildContext context) => Column(children: [
    TextField(controller: playerCtrl, decoration: InputDecoration(labelText: 'Player Name *', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), isDense: true)),
    const SizedBox(height: 8),
    Row(children: [
      Expanded(child: TextField(controller: cardNumberCtrl, decoration: InputDecoration(labelText: 'Card #', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), isDense: true))),
      const SizedBox(width: 8),
      Expanded(child: TextField(controller: serialMaxCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Serial Number', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), isDense: true))),
    ]),
    const SizedBox(height: 8),
    Wrap(spacing: 8, children: [
      FilterChip(label: const Text('RC'), selected: isRookie, onSelected: onToggleRookie),
      FilterChip(label: const Text('AUTO'), selected: isAuto, onSelected: onToggleAuto),
      FilterChip(label: const Text('PATCH'), selected: isPatch, onSelected: onTogglePatch),
      FilterChip(label: const Text('SSP'), selected: isSSP, onSelected: onToggleSSP),
    ]),
  ]);
}

// ── Staged Card Tile ──────────────────────────────────────────────────────────

class _StagedCardTile extends StatelessWidget {
  const _StagedCardTile({required this.card, required this.onRemove});
  final _StagedCard card;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final meta = <String>[
      if (card.setName != null) card.setName!,
      if (card.parallelName != 'Base') card.parallelName,
      if (card.pricePaid != null) '\$${card.pricePaid!.toStringAsFixed(2)}',
      if (card.isGraded && card.grader != null) '${card.grader} ${card.gradeValue ?? ''}'.trim(),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outline.withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: card.player, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  if (card.cardNumber != null)
                    TextSpan(text: '  #${card.cardNumber}', style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.5))),
                ])),
              ),
              const SizedBox(width: 8),
              Wrap(spacing: 4, children: [
                if (card.isRookie) AttrTag('RC', color: const Color(0xFF16A34A)),
                if (card.isAuto)   AttrTag('AUTO', color: const Color(0xFF7C3AED)),
                if (card.isPatch)  AttrTag('PATCH', color: const Color(0xFF0369A1)),
                SerialTag(serialMax: card.serialMax, serialNumber: card.serialNumber),
              ]),
            ]),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(meta.join(' · '), style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.5))),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onRemove,
          child: Icon(Icons.close, size: 16, color: colors.error),
        ),
      ]),
    );
  }
}

// ── Shared: Dropdown container ────────────────────────────────────────────────

class _Dropdown extends StatelessWidget {
  const _Dropdown({required this.children, this.maxHeight = 200});
  final List<Widget> children;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outline.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: children.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }
}

// ── Shared: Selected chip ─────────────────────────────────────────────────────

class _SelectedChip extends StatelessWidget {
  const _SelectedChip({required this.label, required this.onClear});
  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(Icons.check_circle, size: 16, color: colors.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: colors.primary, fontWeight: FontWeight.w500))),
        GestureDetector(onTap: onClear, child: Icon(Icons.close, size: 16, color: colors.onSurface.withValues(alpha: 0.4))),
      ]),
    );
  }
}
