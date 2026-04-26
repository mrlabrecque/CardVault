import 'package:flutter/material.dart';
import '../../core/models/wishlist_item.dart';
import 'wishlist_screen.dart';

class WishlistFormSheet extends StatefulWidget {
  const WishlistFormSheet({
    super.key,
    this.editing,
    required this.onSave,
    this.prefill,
  });

  final WishlistItem? editing;
  final Future<String?> Function(Map<String, dynamic>) onSave;
  final Map<String, dynamic>? prefill;

  @override
  State<WishlistFormSheet> createState() => _WishlistFormSheetState();
}

class _WishlistFormSheetState extends State<WishlistFormSheet> {
  late final TextEditingController _playerCtrl;
  late final TextEditingController _yearCtrl;
  late final TextEditingController _cardNumCtrl;
  late final TextEditingController _setCtrl;
  late final TextEditingController _parallelCtrl;
  late final TextEditingController _gradeCtrl;
  late final TextEditingController _queryCtrl;
  late final TextEditingController _excludeCtrl;
  late final TextEditingController _targetPriceCtrl;
  late final TextEditingController _serialMaxCtrl;

  bool _isRookie = false;
  bool _isAuto = false;
  bool _isPatch = false;
  List<String> _excludeTerms = [];
  bool _queryEdited = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    final pf = widget.prefill ?? {};

    _playerCtrl     = TextEditingController(text: e?.player ?? pf['player'] ?? '');
    _yearCtrl       = TextEditingController(text: e?.year != null ? '${e!.year}' : (pf['year'] != null ? '${pf['year']}' : ''));
    _cardNumCtrl    = TextEditingController(text: e?.cardNumber ?? pf['cardNumber'] ?? pf['card_number'] ?? '');
    _setCtrl        = TextEditingController(text: e?.setName ?? pf['setName'] ?? pf['set_name'] ?? '');
    _parallelCtrl   = TextEditingController(text: e?.parallel ?? pf['parallel'] ?? '');
    _gradeCtrl      = TextEditingController(text: e?.grade ?? pf['grade'] ?? '');
    _queryCtrl      = TextEditingController(text: e?.ebayQuery ?? '');
    _excludeCtrl    = TextEditingController();
    _targetPriceCtrl = TextEditingController(
      text: e?.targetPrice != null ? e!.targetPrice!.toStringAsFixed(2) : '',
    );
    _serialMaxCtrl  = TextEditingController(
      text: e?.serialMax != null ? '${e!.serialMax}' : (pf['serialMax'] != null ? '${pf['serialMax']}' : ''),
    );
    _isRookie     = e?.isRookie ?? (pf['isRookie'] as bool? ?? false);
    _isAuto       = e?.isAuto ?? (pf['isAuto'] as bool? ?? false);
    _isPatch      = e?.isPatch ?? (pf['isPatch'] as bool? ?? false);
    _excludeTerms = [...(e?.excludeTerms ?? [])];
    if (e?.ebayQuery?.isEmpty != false) _rebuildQuery();
  }

  @override
  void dispose() {
    _playerCtrl.dispose();
    _yearCtrl.dispose();
    _cardNumCtrl.dispose();
    _setCtrl.dispose();
    _parallelCtrl.dispose();
    _gradeCtrl.dispose();
    _queryCtrl.dispose();
    _excludeCtrl.dispose();
    _targetPriceCtrl.dispose();
    _serialMaxCtrl.dispose();
    super.dispose();
  }

  void _rebuildQuery() {
    if (_queryEdited) return;
    _queryCtrl.text = buildEbayQuery(
      player:    _playerCtrl.text,
      year:      int.tryParse(_yearCtrl.text),
      setName:   _setCtrl.text,
      parallel:  _parallelCtrl.text,
      cardNumber: _cardNumCtrl.text,
      grade:     _gradeCtrl.text,
      serialMax: int.tryParse(_serialMaxCtrl.text),
      isRookie:  _isRookie,
      isAuto:    _isAuto,
      isPatch:   _isPatch,
    );
  }

  void _addExcludeTerm() {
    final term = _excludeCtrl.text.trim();
    if (term.isNotEmpty && !_excludeTerms.contains(term)) {
      setState(() => _excludeTerms.add(term));
    }
    _excludeCtrl.clear();
  }

  Future<void> _save() async {
    final player = _playerCtrl.text.trim();
    if (player.isEmpty) {
      setState(() => _error = 'Player name is required.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    String? str(String v) => v.trim().isEmpty ? null : v.trim();
    final data = {
      'player':        player,
      'year':          int.tryParse(_yearCtrl.text),
      'set_name':      str(_setCtrl.text),
      'parallel':      str(_parallelCtrl.text),
      'card_number':   str(_cardNumCtrl.text),
      'is_rookie':     _isRookie,
      'is_auto':       _isAuto,
      'is_patch':      _isPatch,
      'serial_max':    int.tryParse(_serialMaxCtrl.text),
      'grade':         str(_gradeCtrl.text),
      'ebay_query':    str(_queryCtrl.text),
      'exclude_terms': _excludeTerms,
      'target_price':  double.tryParse(_targetPriceCtrl.text),
    };
    final error = await widget.onSave(data);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      setState(() => _error = error);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isEditing = widget.editing != null;
    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: colors.outline.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
              child: Row(
                children: [
                  Text(
                    isEditing ? 'Edit Wishlist Item' : 'Add to Wishlist',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colors.onSurface),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.outline.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.close, size: 16, color: colors.onSurface.withValues(alpha: 0.5)),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.outline.withValues(alpha: 0.2)),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: colors.error.withValues(alpha: 0.1),
                          border: Border.all(color: colors.error.withValues(alpha: 0.3)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(children: [
                          Icon(Icons.error_outline, size: 14, color: colors.error),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error!, style: TextStyle(fontSize: 13, color: colors.error))),
                        ]),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _label('Player', required: true),
                    _field(_playerCtrl, colors: colors, hint: 'e.g. Connor Bedard', onChanged: (_) { setState(() {}); _rebuildQuery(); }),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Year'),
                        _field(_yearCtrl, colors: colors, hint: '2024', numeric: true, onChanged: (_) { setState(() {}); _rebuildQuery(); }),
                      ])),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Card #'),
                        _field(_cardNumCtrl, colors: colors, hint: 'e.g. 201', onChanged: (_) { setState(() {}); _rebuildQuery(); }),
                      ])),
                    ]),
                    const SizedBox(height: 16),
                    _label('Set'),
                    _field(_setCtrl, colors: colors, hint: 'e.g. Upper Deck Series 1', onChanged: (_) { setState(() {}); _rebuildQuery(); }),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Parallel'),
                        _field(_parallelCtrl, colors: colors, hint: 'e.g. Silver', onChanged: (_) { setState(() {}); _rebuildQuery(); }),
                      ])),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Grade'),
                        _field(_gradeCtrl, colors: colors, hint: 'e.g. PSA 10', onChanged: (_) { setState(() {}); _rebuildQuery(); }),
                      ])),
                    ]),
                    const SizedBox(height: 16),
                    _label('Attributes'),
                    Row(children: [
                      _attrChip('RC', _isRookie, const Color(0xFF2563EB),
                          () => setState(() { _isRookie = !_isRookie; _rebuildQuery(); })),
                      const SizedBox(width: 8),
                      _attrChip('AUTO', _isAuto, const Color(0xFF7C3AED),
                          () => setState(() { _isAuto = !_isAuto; _rebuildQuery(); })),
                      const SizedBox(width: 8),
                      _attrChip('PATCH', _isPatch, const Color(0xFFF59E0B),
                          () => setState(() { _isPatch = !_isPatch; _rebuildQuery(); })),
                      const Spacer(),
                      Text('/', style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.4), fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      SizedBox(width: 64, child: _field(_serialMaxCtrl, colors: colors, hint: '99', numeric: true,
                          onChanged: (_) { setState(() {}); _rebuildQuery(); })),
                    ]),
                    const SizedBox(height: 16),
                    Row(children: [
                      Text('EBAY SEARCH QUERY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.onSurface.withValues(alpha: 0.4), letterSpacing: 0.5)),
                      const SizedBox(width: 6),
                      Text('auto-built · editable', style: TextStyle(fontSize: 11, color: colors.onSurface.withValues(alpha: 0.3))),
                    ]),
                    const SizedBox(height: 6),
                    _field(_queryCtrl, colors: colors, hint: 'e.g. Connor Bedard RC PSA 10',
                        onChanged: (_) => setState(() => _queryEdited = true)),
                    const SizedBox(height: 16),
                    Row(children: [
                      Text('EXCLUDE TERMS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.onSurface.withValues(alpha: 0.4), letterSpacing: 0.5)),
                      const SizedBox(width: 6),
                      Text('press Enter to add', style: TextStyle(fontSize: 11, color: colors.onSurface.withValues(alpha: 0.3))),
                    ]),
                    const SizedBox(height: 6),
                    Container(
                      constraints: const BoxConstraints(minHeight: 42),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.outline.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Wrap(
                        spacing: 6, runSpacing: 6,
                        children: [
                          for (final term in _excludeTerms)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: colors.error.withValues(alpha: 0.1),
                                border: Border.all(color: colors.error.withValues(alpha: 0.3)),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(term, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.error)),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () => setState(() => _excludeTerms.remove(term)),
                                  child: Icon(Icons.close, size: 12, color: colors.error.withValues(alpha: 0.6)),
                                ),
                              ]),
                            ),
                          SizedBox(
                            width: double.infinity,
                            child: TextField(
                              controller: _excludeCtrl,
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: _excludeTerms.isEmpty ? 'e.g. draft picks' : '',
                                hintStyle: TextStyle(fontSize: 13, color: colors.onSurface.withValues(alpha: 0.3)),
                                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                              ),
                              style: TextStyle(fontSize: 13, color: colors.onSurface),
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _addExcludeTerm(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _label('Target Price'),
                    TextField(
                      controller: _targetPriceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        hintText: '0.00',
                        prefixText: '\$ ',
                        hintStyle: TextStyle(color: colors.onSurface.withValues(alpha: 0.3), fontSize: 14),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colors.outline.withValues(alpha: 0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colors.primary, width: 1.5),
                        ),
                        isDense: true,
                      ),
                      style: TextStyle(fontSize: 14, color: colors.onSurface),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: colors.outline.withValues(alpha: 0.2)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.outline.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(child: Text('Cancel',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.onSurface.withValues(alpha: 0.6)))),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _saving ? null : _save,
                    child: Opacity(
                      opacity: _saving ? 0.5 : 1.0,
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: _saving
                              ? SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: colors.onPrimary))
                              : Text(isEditing ? 'Save Changes' : 'Add to Wishlist',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.onPrimary)),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text, {bool required = false}) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Text(text.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.onSurface.withValues(alpha: 0.4), letterSpacing: 0.5)),
        if (required) Text(' *', style: TextStyle(fontSize: 11, color: colors.error)),
      ]),
    );
  }

  Widget _field(TextEditingController ctrl, {ColorScheme? colors, String? hint, bool numeric = false, void Function(String)? onChanged}) {
    final colorScheme = colors ?? Theme.of(context).colorScheme;
    return TextField(
      controller: ctrl,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.3), fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        isDense: true,
      ),
      style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
    );
  }

  Widget _attrChip(String label, bool active, Color activeColor, VoidCallback onTap) {
    final colors = Theme.of(context).colorScheme;
    final bg = active ? activeColor : colors.outline.withValues(alpha: 0.1);
    final fg = active ? Colors.white : colors.onSurface.withValues(alpha: 0.6);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: fg)),
      ),
    );
  }
}
