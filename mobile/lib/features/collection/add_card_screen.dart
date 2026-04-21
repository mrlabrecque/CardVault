import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/cards_service.dart';

const _graders = ['PSA', 'BGS', 'SGC', 'CGC', 'CSG'];

class AddCardScreen extends ConsumerStatefulWidget {
  const AddCardScreen({super.key});

  @override
  ConsumerState<AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends ConsumerState<AddCardScreen> {
  // ── Step 1: Release ─────────────────────────────────────────
  final _releaseCtrl = TextEditingController();
  List<ReleaseRecord> _releaseResults = [];
  bool _loadingReleases = false;
  ReleaseRecord? _selectedRelease;

  // ── Step 2: Set ──────────────────────────────────────────────
  List<SetRecord> _sets = [];
  bool _loadingSets = false;
  SetRecord? _selectedSet;
  final _setFilterCtrl = TextEditingController();

  // ── Step 3: Card ─────────────────────────────────────────────
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

  // ── Your Copy ────────────────────────────────────────────────
  List<SetParallel> _parallels = [];
  bool _loadingParallels = false;
  SetParallel? _selectedParallel;
  String _parallelName = 'Base';
  final _pricePaidCtrl = TextEditingController();
  final _serialNumberCtrl = TextEditingController();
  bool _isGraded = false;
  String _grader = 'PSA';
  final _gradeValueCtrl = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _releaseCtrl.dispose();
    _setFilterCtrl.dispose();
    _cardCtrl.dispose();
    _newPlayerCtrl.dispose();
    _newCardNumberCtrl.dispose();
    _newSerialMaxCtrl.dispose();
    _pricePaidCtrl.dispose();
    _serialNumberCtrl.dispose();
    _gradeValueCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchReleases(String query) async {
    setState(() => _loadingReleases = true);
    try {
      final results = await ref.read(cardsServiceProvider).searchReleases(query);
      setState(() => _releaseResults = results);
    } finally {
      setState(() => _loadingReleases = false);
    }
  }

  Future<void> _selectRelease(ReleaseRecord release) async {
    setState(() {
      _selectedRelease = release;
      _releaseCtrl.text = release.displayName;
      _releaseResults = [];
      _selectedSet = null;
      _sets = [];
      _setFilterCtrl.clear();
      _selectedCard = null;
      _cardCtrl.clear();
      _isNewCard = false;
      _parallels = [];
      _selectedParallel = null;
      _parallelName = 'Base';
      _loadingSets = true;
    });
    try {
      final sets = await ref.read(cardsServiceProvider).getSetsForRelease(release.id);
      setState(() => _sets = sets);
      if (sets.length == 1) _selectSet(sets.first);
    } finally {
      setState(() => _loadingSets = false);
    }
  }

  void _selectSet(SetRecord set) async {
    setState(() {
      _selectedSet = set;
      _selectedCard = null;
      _cardCtrl.clear();
      _cardResults = [];
      _isNewCard = false;
      _parallels = [];
      _selectedParallel = null;
      _parallelName = 'Base';
      _loadingParallels = true;
    });
    try {
      final parallels = await ref.read(cardsServiceProvider).getParallels(set.id);
      setState(() => _parallels = parallels);
    } finally {
      setState(() => _loadingParallels = false);
    }
  }

  Future<void> _searchCards(String query) async {
    if (_selectedSet == null) return;
    setState(() => _loadingCards = true);
    try {
      final results = await ref.read(cardsServiceProvider).searchMasterCards(_selectedSet!.id, query);
      setState(() => _cardResults = results);
    } finally {
      setState(() => _loadingCards = false);
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

  void _selectParallel(SetParallel? p) {
    setState(() {
      _selectedParallel = p;
      _parallelName = p?.name ?? 'Base';
    });
  }

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
      await ref.read(cardsServiceProvider).addCard(form);
      ref.invalidate(userCardsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Card added!'), duration: Duration(seconds: 2)),
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
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Card'),
        actions: [
          TextButton(
            onPressed: _canSave ? _save : null,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader('Release', colors),
          const SizedBox(height: 8),
          _ReleaseSearch(
            controller: _releaseCtrl,
            results: _releaseResults,
            loading: _loadingReleases,
            selected: _selectedRelease,
            onSearch: _searchReleases,
            onSelect: _selectRelease,
            onClear: () => setState(() {
              _selectedRelease = null;
              _releaseCtrl.clear();
              _releaseResults = [];
              _sets = [];
              _selectedSet = null;
              _selectedCard = null;
              _isNewCard = false;
            }),
          ),

          if (_selectedRelease != null) ...[
            const SizedBox(height: 20),
            _sectionHeader('Set', colors),
            const SizedBox(height: 8),
            if (_loadingSets)
              const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: CircularProgressIndicator()))
            else
              _SetPicker(
                sets: _sets,
                selected: _selectedSet,
                filterCtrl: _setFilterCtrl,
                onSelect: _selectSet,
                onClear: () => setState(() {
                  _selectedSet = null;
                  _setFilterCtrl.clear();
                  _selectedCard = null;
                  _cardCtrl.clear();
                  _isNewCard = false;
                  _parallels = [];
                  _selectedParallel = null;
                  _parallelName = 'Base';
                }),
              ),
          ],

          if (_selectedSet != null) ...[
            const SizedBox(height: 20),
            _sectionHeader('Card', colors),
            const SizedBox(height: 8),
            _CardSearch(
              controller: _cardCtrl,
              results: _cardResults,
              loading: _loadingCards,
              selected: _selectedCard,
              isNewCard: _isNewCard,
              onSearch: _searchCards,
              onSelect: _selectCard,
              onNewCard: () => setState(() {
                _isNewCard = true;
                _selectedCard = null;
                _cardCtrl.clear();
                _cardResults = [];
              }),
              onClear: () => setState(() {
                _selectedCard = null;
                _isNewCard = false;
                _cardCtrl.clear();
              }),
            ),
            if (_isNewCard) ...[
              const SizedBox(height: 12),
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
            ],
          ],

          if (_selectedSet != null && (_selectedCard != null || _isNewCard)) ...[
            const SizedBox(height: 20),
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
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _canSave ? _save : null,
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save Card'),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, ColorScheme colors) {
    return Text(
      title,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurface.withValues(alpha: 0.6), letterSpacing: 0.5),
    );
  }
}

// ── Release Search Widget ─────────────────────────────────────────────────────

class _ReleaseSearch extends StatefulWidget {
  const _ReleaseSearch({
    required this.controller,
    required this.results,
    required this.loading,
    required this.selected,
    required this.onSearch,
    required this.onSelect,
    required this.onClear,
  });
  final TextEditingController controller;
  final List<ReleaseRecord> results;
  final bool loading;
  final ReleaseRecord? selected;
  final void Function(String) onSearch;
  final void Function(ReleaseRecord) onSelect;
  final VoidCallback onClear;

  @override
  State<_ReleaseSearch> createState() => _ReleaseSearchState();
}

class _ReleaseSearchState extends State<_ReleaseSearch> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (widget.selected != null) {
      return _SelectedChip(label: widget.selected!.displayName, onClear: widget.onClear);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          onChanged: widget.onSearch,
          decoration: InputDecoration(
            hintText: 'Search releases…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: widget.loading ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
          ),
        ),
        if (widget.results.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: colors.outline.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.results.length > 8 ? 8 : widget.results.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = widget.results[i];
                return ListTile(
                  dense: true,
                  title: Text(r.displayName, style: const TextStyle(fontSize: 14)),
                  subtitle: r.sport != null ? Text(r.sport!, style: const TextStyle(fontSize: 12)) : null,
                  onTap: () => widget.onSelect(r),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

// ── Set Picker Widget ─────────────────────────────────────────────────────────

class _SetPicker extends StatelessWidget {
  const _SetPicker({required this.sets, required this.selected, required this.filterCtrl, required this.onSelect, required this.onClear});
  final List<SetRecord> sets;
  final SetRecord? selected;
  final TextEditingController filterCtrl;
  final void Function(SetRecord) onSelect;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (sets.isEmpty) return const Text('No sets found for this release.', style: TextStyle(fontSize: 13));

    if (selected != null) {
      return _SelectedChip(label: selected!.name, onClear: onClear);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sets.length > 4)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: filterCtrl,
              decoration: InputDecoration(
                hintText: 'Filter sets…',
                prefixIcon: const Icon(Icons.search, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: sets.where((s) {
            final q = filterCtrl.text.toLowerCase();
            return q.isEmpty || s.name.toLowerCase().contains(q);
          }).map((s) => ChoiceChip(
            label: Text(s.name),
            selected: false,
            onSelected: (_) => onSelect(s),
          )).toList(),
        ),
      ],
    );
  }
}

// ── Card Search Widget ────────────────────────────────────────────────────────

class _CardSearch extends StatelessWidget {
  const _CardSearch({
    required this.controller,
    required this.results,
    required this.loading,
    required this.selected,
    required this.isNewCard,
    required this.onSearch,
    required this.onSelect,
    required this.onNewCard,
    required this.onClear,
  });
  final TextEditingController controller;
  final List<MasterCard> results;
  final bool loading;
  final MasterCard? selected;
  final bool isNewCard;
  final void Function(String) onSearch;
  final void Function(MasterCard) onSelect;
  final VoidCallback onNewCard;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (selected != null) {
      return _SelectedChip(label: selected!.displayName, onClear: onClear);
    }
    if (isNewCard) {
      return Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('New Card', style: TextStyle(fontSize: 13, color: colors.primary, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onClear, child: const Text('Cancel')),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          onChanged: onSearch,
          decoration: InputDecoration(
            hintText: 'Search player name…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: loading ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
          ),
        ),
        if (results.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              border: Border.all(color: colors.outline.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: results.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final c = results[i];
                return ListTile(
                  dense: true,
                  title: Text(c.player, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  subtitle: _cardSubtitle(c),
                  onTap: () => onSelect(c),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onNewCard,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Not in checklist? Add manually'),
          style: OutlinedButton.styleFrom(textStyle: const TextStyle(fontSize: 13)),
        ),
      ],
    );
  }

  Widget? _cardSubtitle(MasterCard c) {
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
        // Parallel
        if (loadingParallels)
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Center(child: CircularProgressIndicator()))
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 16, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: colors.primary, fontWeight: FontWeight.w500))),
          GestureDetector(
            onTap: onClear,
            child: Icon(Icons.close, size: 16, color: colors.onSurface.withValues(alpha: 0.4)),
          ),
        ],
      ),
    );
  }
}
