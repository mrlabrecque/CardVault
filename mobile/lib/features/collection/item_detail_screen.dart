import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/models/user_card.dart';
import '../../core/models/comp.dart';
import '../../core/services/cards_service.dart';
import '../../core/auth/auth_service.dart';
import '../../core/services/comps_service.dart';
import '../../core/widgets/serial_tag.dart';
import '../../core/widgets/attr_tag.dart';

class ItemDetailScreen extends ConsumerStatefulWidget {
  const ItemDetailScreen({super.key, required this.card});
  final UserCard card;

  @override
  ConsumerState<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<ItemDetailScreen> with SingleTickerProviderStateMixin {
  late final _pricePaidCtrl = TextEditingController(text: widget.card.pricePaid?.toStringAsFixed(2) ?? '');
  late final _serialCtrl = TextEditingController(text: widget.card.serialNumber ?? '');
  late final _graderCtrl = TextEditingController(text: widget.card.grader ?? 'PSA');
  late final _gradeCtrl = TextEditingController(text: widget.card.grade ?? '');
  late final _otherParallelCtrl = TextEditingController();
  bool _editing = false;
  bool _saving = false;
  late bool _weeklyPriceCheck = widget.card.weeklyPriceCheck;
  late bool _isGraded = widget.card.isGraded;
  String? _selectedParallelId;   // null = Base, '__other__' = custom
  late String _selectedParallelName = widget.card.parallel;
  bool get _isOtherParallel => _selectedParallelId == '__other__';

  List<Comp>? _comps;
  bool _compsLoading = false;
  bool _refreshing = false;
  String? _compsError;
  int _compsWindow = 90;
  double? _currentValue;
  int _valueTrend = 0; // 1 up, -1 down, 0 flat

  late final AnimationController _spinCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void initState() {
    super.initState();
    _currentValue = widget.card.currentValue;
    _valueTrend = widget.card.valueTrend;
    _fetchComps();
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchComps({bool refresh = false}) async {
    setState(() {
      _compsLoading = true;
      _compsError = null;
      if (refresh) {
        _refreshing = true;
        _spinCtrl.repeat();
      }
    });
    try {
      final svc = ref.read(compsServiceProvider);
      if (refresh) {
        await svc.refreshCardValue(widget.card.id);
        final data = await ref.read(supabaseProvider)
            .from('user_cards')
            .select('current_value, previous_value')
            .eq('id', widget.card.id)
            .single();
        if (mounted) {
          final newValue = (data['current_value'] as num?)?.toDouble();
          final prevValue = (data['previous_value'] as num?)?.toDouble();
          setState(() {
            _currentValue = newValue;
            if (prevValue != null && newValue != null && newValue != prevValue) {
              _valueTrend = newValue > prevValue ? 1 : -1;
            }
          });
          ref.invalidate(userCardsProvider);
        }
      }
      final results = await svc.getCardComps(widget.card.id);
      if (mounted) { setState(() => _comps = results); }
    } catch (e) {
      if (mounted) { setState(() => _compsError = e.toString()); }
    } finally {
      if (mounted) setState(() {
        _compsLoading = false;
        _refreshing = false;
        _spinCtrl.stop();
        _spinCtrl.reset();
      });
    }
  }

  void _startEdit() => setState(() {
    _editing = true;
    _selectedParallelId = widget.card.parallelId;
    _selectedParallelName = widget.card.parallel;
  });

  void _cancelEdit() {
    _pricePaidCtrl.text = widget.card.pricePaid?.toStringAsFixed(2) ?? '';
    _serialCtrl.text = widget.card.serialNumber ?? '';
    _graderCtrl.text = widget.card.grader ?? 'PSA';
    _gradeCtrl.text = widget.card.grade ?? '';
    _otherParallelCtrl.text = '';
    setState(() {
      _editing = false;
      _isGraded = widget.card.isGraded;
      _selectedParallelId = widget.card.parallelId;
      _selectedParallelName = widget.card.parallel;
    });
  }

  void _onParallelChanged(String? id, List<SetParallel> parallels) {
    setState(() {
      _selectedParallelId = id;
      _otherParallelCtrl.text = '';
      if (id == null) {
        _selectedParallelName = 'Base';
      } else if (id != '__other__') {
        _selectedParallelName = parallels.firstWhere((p) => p.id == id).name;
      }
    });
  }

  String get _sportEmoji => switch (widget.card.sport.toLowerCase()) {
    'basketball' => '🏀',
    'baseball'   => '⚾',
    'football'   => '🏈',
    'hockey'     => '🏒',
    'soccer'     => '⚽',
    _            => '🃏',
  };

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final parallelName = _isOtherParallel
          ? (_otherParallelCtrl.text.trim().isEmpty ? 'Base' : _otherParallelCtrl.text.trim())
          : (_selectedParallelId == null ? 'Base' : null);
      await ref.read(cardsServiceProvider).updateCard(widget.card.id, {
        'price_paid': double.tryParse(_pricePaidCtrl.text),
        'serial_number': _serialCtrl.text.isEmpty ? null : _serialCtrl.text,
        'is_graded': _isGraded,
        'grader': _isGraded ? _graderCtrl.text : null,
        'grade_value': _isGraded ? _gradeCtrl.text : null,
        'parallel_id': _isOtherParallel ? null : _selectedParallelId,
        'parallel_name': parallelName,
      });
      ref.invalidate(userCardsProvider);
      if (mounted) {
        setState(() => _editing = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Card updated.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static const _graders = ['PSA', 'BGS', 'SGC', 'CGC', 'CSG'];

  Widget _parallelFallback() => TextField(
    controller: _otherParallelCtrl,
    decoration: const InputDecoration(labelText: 'Parallel', border: OutlineInputBorder()),
    onChanged: (v) => setState(() => _selectedParallelName = v.trim().isEmpty ? 'Base' : v.trim()),
  );

  Widget _parallelDropdown(List<SetParallel> parallels) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DropdownButtonFormField<String?>(
        key: ValueKey(_selectedParallelId),
        initialValue: _selectedParallelId,
        decoration: const InputDecoration(labelText: 'Parallel', border: OutlineInputBorder()),
        items: [
          const DropdownMenuItem(value: null, child: Text('Base')),
          ...parallels.map((p) => DropdownMenuItem(
            value: p.id,
            child: Text('${p.name}${p.serialMax != null ? ' /${p.serialMax}' : ''}'),
          )),
          const DropdownMenuItem(value: '__other__', child: Text('Other…')),
        ],
        onChanged: (id) => _onParallelChanged(id, parallels),
      ),
      if (_isOtherParallel) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _otherParallelCtrl,
          decoration: const InputDecoration(labelText: 'Parallel name', border: OutlineInputBorder()),
          onChanged: (v) => setState(() => _selectedParallelName = v.trim().isEmpty ? 'Base' : v.trim()),
        ),
      ],
    ],
  );

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Card'),
        content: const Text('Remove this card from your collection?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(cardsServiceProvider).deleteCard(widget.card.id);
      ref.invalidate(userCardsProvider);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final colors = Theme.of(context).colorScheme;
    final pl = (card.currentValue ?? 0) - (card.pricePaid ?? 0);
    final plPct = card.pricePaid != null && card.pricePaid! > 0 ? (pl / card.pricePaid!) * 100 : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(card.player),
        actions: [
          IconButton(icon: Icon(Icons.delete_outline, color: colors.error), onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Maroon gradient hero
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF800020), Color(0xFF3D0010)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Card image
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: card.imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: card.imageUrl!,
                          width: 72, height: 100,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 72, height: 100,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(child: Text(_sportEmoji, style: const TextStyle(fontSize: 32))),
                        ),
                ),
                const SizedBox(width: 16),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(
                            text: card.player,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          if (card.cardNumber != null)
                            TextSpan(
                              text: '  #${card.cardNumber}',
                              style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w400),
                            ),
                        ]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (card.year != null) '${card.year}',
                          if (card.set != null) card.set!,
                          if (card.checklist != null) card.checklist!,
                        ].join(' · '),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (card.parallel != 'Base') ...[
                        const SizedBox(height: 2),
                        Text(
                          card.parallel,
                          style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (card.rookie)      AttrTag('RC', color: const Color(0xFF16A34A)),
                          if (card.autograph)   AttrTag('AUTO', color: const Color(0xFF7C3AED)),
                          if (card.memorabilia) AttrTag('PATCH', color: const Color(0xFF0369A1)),
                          if (card.ssp)         AttrTag('SSP', color: const Color(0xFFB45309)),
                          if (card.isGraded)    AttrTag('${card.grader ?? 'PSA'} ${card.grade ?? ''}'),
                          SerialTag(serialNumber: card.serialNumber, serialMax: card.serialMax),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),

          // P/L summary + refresh tier
          Row(
            children: [
              Expanded(child: _InfoBox(
                label: 'Current Value',
                value: '\$${(_currentValue ?? 0).toStringAsFixed(2)}',
                trend: _valueTrend,
              )),
              const SizedBox(width: 8),
              Expanded(child: _InfoBox(
                label: 'P/L',
                value: '${pl >= 0 ? '+' : ''}\$${pl.toStringAsFixed(2)}',
                subtitle: '${plPct.toStringAsFixed(1)}%',
                valueColor: pl >= 0 ? Colors.green : colors.error,
              )),
            ],
          ),
          const SizedBox(height: 8),
          if (ref.watch(dailyTierCardIdsProvider).contains(card.id))
            _DailyRefreshBadge()
          else
            _PriceCheckToggle(
              enabled: _weeklyPriceCheck,
              onChanged: (val) async {
                setState(() => _weeklyPriceCheck = val);
                await ref.read(cardsServiceProvider).setWeeklyPriceCheck(card.id, val);
                ref.invalidate(userCardsProvider);
              },
            ),

          const SizedBox(height: 20),

          // Your Copy header
          Row(
            children: [
              Expanded(
                child: Text('Your Copy', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (!_editing)
                TextButton.icon(
                  onPressed: _startEdit,
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('Edit'),
                  style: TextButton.styleFrom(foregroundColor: colors.onSurface.withValues(alpha: 0.5), visualDensity: VisualDensity.compact),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (_editing) ...[
            // Parallel dropdown
            if (card.setId != null)
              ref.watch(parallelsProvider(card.setId!)).when(
                loading: () => const SizedBox(height: 56, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                error: (_, _) => _parallelFallback(),
                data: (parallels) => _parallelDropdown(parallels),
              )
            else
              _parallelFallback(),
            const SizedBox(height: 12),
            // Edit form
            TextField(
              controller: _pricePaidCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Price Paid', prefixText: '\$', border: OutlineInputBorder()),
            ),
            if (card.serialMax != null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _serialCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Serial # (your copy, e.g. 34 of /${card.serialMax})', border: const OutlineInputBorder()),
              ),
            ],
            const SizedBox(height: 12),
            // Graded toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Graded', style: TextStyle(color: colors.onSurface.withValues(alpha: 0.6))),
                GestureDetector(
                  onTap: () => setState(() => _isGraded = !_isGraded),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44, height: 24,
                    decoration: BoxDecoration(
                      color: _isGraded ? const Color(0xFF800020) : colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 200),
                      alignment: _isGraded ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.all(3),
                        width: 18, height: 18,
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
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
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(_graderCtrl.text),
                      initialValue: _graderCtrl.text.isEmpty ? 'PSA' : _graderCtrl.text,
                      decoration: const InputDecoration(labelText: 'Grader', border: OutlineInputBorder()),
                      items: _graders.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                      onChanged: (v) => _graderCtrl.text = v ?? 'PSA',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _gradeCtrl,
                      decoration: const InputDecoration(labelText: 'Grade', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancelEdit,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF800020)),
                    child: _saving
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          ] else ...[
            // View tiles
            _CopyTile(label: 'Parallel', value: card.parallel),
            if (card.serialNumber != null || card.serialMax != null) ...[
              const SizedBox(height: 8),
              _CopyTile(
                label: 'Serial #',
                value: card.serialNumber != null && card.serialMax != null
                    ? '${card.serialNumber}/${card.serialMax}'
                    : card.serialMax != null
                        ? '/${card.serialMax}'
                        : card.serialNumber!,
              ),
            ],
            const SizedBox(height: 8),
            _CopyTile(label: 'Price Paid', value: '\$${(card.pricePaid ?? 0).toStringAsFixed(2)}'),
            if (card.isGraded) ...[
              const SizedBox(height: 8),
              _CopyTile(label: 'Grade', value: '${card.grader ?? 'PSA'} ${card.grade ?? ''}'.trim()),
            ],
          ],

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          // Sold Comps header + 30/90 toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent eBay Sales', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              Row(
                children: [
                  // 30d / 90d toggle
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Row(
                      children: [30, 90].map((days) {
                        final active = _compsWindow == days;
                        return GestureDetector(
                          onTap: () => setState(() => _compsWindow = days),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            color: active ? const Color(0xFF800020) : Colors.transparent,
                            child: Text(
                              '${days}d',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: active ? Colors.white : colors.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  RotationTransition(
                    turns: _spinCtrl,
                    child: IconButton(
                      icon: Icon(Icons.refresh, size: 18,
                          color: _refreshing
                              ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8)
                              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
                      onPressed: _compsLoading ? null : () => _fetchComps(refresh: true),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (_compsLoading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(strokeWidth: 2)))
          else if (_compsError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_compsError!, style: TextStyle(color: colors.error, fontSize: 13)),
            )
          else if (_comps == null || _comps!.isEmpty)
            _CompsEmptyState(message: 'No comps yet — tap refresh to fetch sales data.', icon: Icons.show_chart)
          else ...[
            Builder(builder: (context) {
              final cutoff = _compsWindow == 30
                  ? DateTime.now().subtract(const Duration(days: 30))
                  : null;
              final filtered = cutoff == null
                  ? _comps!
                  : _comps!.where((c) => c.soldAt == null || c.soldAt!.isAfter(cutoff)).toList();

              if (filtered.isEmpty) {
                return _CompsEmptyState(message: 'No sales in the last $_compsWindow days.', icon: Icons.calendar_today);
              }

              final hasBestOffer = filtered.any((c) => c.saleType == SaleType.bestOffer);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Best offer caveat
                  if (hasBestOffer)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        border: Border.all(color: const Color(0xFFFCD34D)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, size: 13, color: Color(0xFFB45309)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Best Offer prices shown are the listing ask, not the accepted offer — actual sold price may differ.',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF92400E), height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Comp rows
                  Container(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: filtered.indexed.map(((int, Comp) entry) {
                        final (i, comp) = entry;
                        return Column(
                          children: [
                            if (i > 0) Divider(height: 1, color: colors.outlineVariant.withValues(alpha: 0.3)),
                            _CompRow(comp: comp),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              );
            }),
          ],

          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

class _CompsEmptyState extends StatelessWidget {
  const _CompsEmptyState({required this.message, required this.icon});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: colors.onSurface.withValues(alpha: 0.3)),
          const SizedBox(height: 8),
          Text(message, style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.45)), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _CompRow extends StatelessWidget {
  const _CompRow({required this.comp});
  final Comp comp;

  String _dateLabel() {
    if (comp.soldAt == null) return '';
    final daysAgo = DateTime.now().difference(comp.soldAt!).inDays;
    if (daysAgo == 0) return 'Today';
    if (daysAgo == 1) return 'Yesterday';
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[comp.soldAt!.month - 1]} ${comp.soldAt!.day}, ${comp.soldAt!.year}';
  }

  (String label, Color bg, Color fg) _saleTypeBadge() => switch (comp.saleType) {
    SaleType.auction    => ('Auction',    const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
    SaleType.bestOffer  => ('Best Offer', const Color(0xFFFFFBEB), const Color(0xFFB45309)),
    SaleType.fixedPrice => ('Buy It Now', const Color(0xFFF0FDF4), const Color(0xFF15803D)),
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (label, bg, fg) = _saleTypeBadge();
    final dateLabel = _dateLabel();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(comp.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, height: 1.3)),
                if (dateLabel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(dateLabel, style: TextStyle(fontSize: 10, color: colors.onSurface.withValues(alpha: 0.45))),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('\$${comp.price.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
                    child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: fg)),
                  ),
                  if (comp.url != null) ...[
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => launchUrl(Uri.parse(comp.url!), mode: LaunchMode.externalApplication),
                      child: Icon(Icons.open_in_new, size: 12, color: colors.onSurface.withValues(alpha: 0.4)),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.label, required this.value, this.subtitle, this.valueColor, this.trend = 0});
  final String label;
  final String value;
  final String? subtitle;
  final Color? valueColor;
  final int trend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF3F4F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF), letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Row(
            children: [
              if (trend != 0) ...[
                Icon(
                  trend > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 13,
                  color: trend > 0 ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 2),
              ],
              Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20, color: valueColor ?? const Color(0xFF111827))),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: valueColor?.withValues(alpha: 0.75) ?? const Color(0xFF6B7280))),
          ],
        ],
      ),
    );
  }
}

class _DailyRefreshBadge extends StatelessWidget {
  const _DailyRefreshBadge();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt, size: 16, color: Color(0xFF2563EB)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Auto-refreshed Daily',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1D4ED8))),
                Text('Top 50 by value — updated every 24 hours automatically',
                    style: TextStyle(fontSize: 11, color: colors.onSurface.withValues(alpha: 0.45))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceCheckToggle extends StatelessWidget {
  const _PriceCheckToggle({required this.enabled, required this.onChanged});
  final bool enabled;
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFFF0FDF4) : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: enabled ? const Color(0xFF86EFAC) : Colors.transparent),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 16, color: enabled ? const Color(0xFF16A34A) : colors.onSurface.withValues(alpha: 0.4)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Weekly Price Check',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: enabled ? const Color(0xFF15803D) : colors.onSurface.withValues(alpha: 0.7))),
                Text('Auto-refresh value every 7 days',
                    style: TextStyle(fontSize: 11, color: colors.onSurface.withValues(alpha: 0.45))),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => onChanged(!enabled),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44, height: 24,
              decoration: BoxDecoration(
                color: enabled ? const Color(0xFF16A34A) : colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: enabled ? const Color(0xFF16A34A) : colors.outline.withValues(alpha: 0.3)),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.all(3),
                  width: 18, height: 18,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyTile extends StatelessWidget {
  const _CopyTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF3F4F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF), letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1F2937))),
        ],
      ),
    );
  }
}
