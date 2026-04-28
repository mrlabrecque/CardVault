import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/user_card.dart';
import '../../core/services/cards_service.dart';
import 'widgets/card_detail_view.dart';
import 'widgets/card_comps_section.dart';

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
    _            => '🏀',
  };

  String _resolveDefaultGrade() {
    if (!widget.card.isGraded) return 'Raw';
    final grade = widget.card.grade ?? '';
    if (grade == '10' || grade == '10.0') return 'PSA 10';
    if (grade == '9' || grade == '9.0') return 'PSA 9';
    return 'Raw';
  }

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
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
          CardDetailView(
            userCard: card,
            sections: const [CardDetailSection.hero],
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),

          // P/L summary + refresh tier
          Row(
            children: [
              Expanded(child: _InfoBox(
                label: 'Current Value',
                value: '\$${(widget.card.currentValue ?? 0).toStringAsFixed(2)}',
                trend: widget.card.valueTrend,
              )),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFF3F4F6)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('P/L', style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF), letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${pl >= 0 ? '+' : ''}\$${pl.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20, color: pl >= 0 ? Colors.green : colors.error)),
                          Text('${plPct.toStringAsFixed(1)}%', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: pl >= 0 ? Colors.green : colors.error)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
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
              decoration: const InputDecoration(
                labelText: 'Price Paid',
                prefixText: '\$',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            if (card.serialMax != null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _serialCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Serial # (your copy, e.g. 34 of /${card.serialMax})',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
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
                      color: _isGraded ? const Color(0xFF800020) : Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _isGraded ? const Color(0xFF800020) : colors.outline),
                    ),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 200),
                      alignment: _isGraded ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.all(3),
                        width: 18, height: 18,
                        decoration: BoxDecoration(
                          color: _isGraded ? Colors.white : colors.outline,
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
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(_graderCtrl.text),
                      initialValue: _graderCtrl.text.isEmpty ? 'PSA' : _graderCtrl.text,
                      decoration: const InputDecoration(
                        labelText: 'Grader',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: _graders.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                      onChanged: (v) => _graderCtrl.text = v ?? 'PSA',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _gradeCtrl,
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
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancelEdit,
                    style: OutlinedButton.styleFrom(backgroundColor: Colors.white),
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

          // Comps section
          if (widget.card.masterCardId != null)
            CardCompsSection(
              masterCardId: widget.card.masterCardId!,
              parallelName: widget.card.parallel,
              initialGrade: _resolveDefaultGrade(),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'No master card info available',
                style: TextStyle(fontSize: 13, color: colors.onSurface.withValues(alpha: 0.5)),
              ),
            ),

          const SizedBox(height: 100),
              ],
            ),
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
