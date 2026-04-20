import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/user_card.dart';
import '../../../core/widgets/serial_tag.dart';
import '../../../core/widgets/attr_tag.dart';
import '../item_detail_screen.dart';

class CardStackTile extends StatefulWidget {
  const CardStackTile({super.key, required this.stack, this.onDelete});
  final CardStack stack;
  final void Function(String cardId)? onDelete;

  @override
  State<CardStackTile> createState() => _CardStackTileState();
}

class _CardStackTileState extends State<CardStackTile> {
  bool _expanded = false;

  String get _sportEmoji => switch (widget.stack.sport.toLowerCase()) {
    'basketball' => '🏀',
    'baseball'   => '⚾',
    'football'   => '🏈',
    'hockey'     => '🏒',
    'soccer'     => '⚽',
    _            => '🃏',
  };

  Color get _plColor => widget.stack.pl >= 0 ? Colors.green : Colors.red;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final stack = widget.stack;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          InkWell(
            onTap: stack.qty > 1
                ? () => setState(() => _expanded = !_expanded)
                : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemDetailScreen(card: stack.cards.first))),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _buildImage(),
                  const SizedBox(width: 12),
                  Expanded(child: _buildInfo(colors, stack)),
                  _buildValue(colors, stack),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            ...stack.cards.map((c) => _IndividualCardRow(card: c, onDelete: widget.onDelete)),
          ],
        ],
      ),
    );
  }

  Widget _buildImage() {
    if (widget.stack.imageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: widget.stack.imageUrl!,
          width: 44,
          height: 60,
          fit: BoxFit.cover,
          placeholder: (ctx, url) => _imagePlaceholder(),
          errorWidget: (ctx, url, err) => _imagePlaceholder(),
        ),
      );
    }
    return _imagePlaceholder();
  }

  Widget _imagePlaceholder() => Container(
        width: 44,
        height: 60,
        decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
        child: Center(child: Text(_sportEmoji, style: const TextStyle(fontSize: 20))),
      );

  Widget _buildInfo(ColorScheme colors, CardStack stack) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: stack.player, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            if (stack.cardNumber != null)
              TextSpan(text: '  #${stack.cardNumber}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: colors.onSurface.withValues(alpha: 0.5))),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        if (stack.set != null || stack.checklist != null)
          Text(
            [if (stack.year != null) '${stack.year}', if (stack.set != null) stack.set!, if (stack.checklist != null) stack.checklist!].join(' · '),
            style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.6)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        if (stack.parallel != 'Base')
          Text(stack.parallel, style: TextStyle(fontSize: 12, color: colors.primary)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            if (stack.rookie)      AttrTag('RC', color: const Color(0xFF16A34A)),
            if (stack.autograph)   AttrTag('AUTO', color: const Color(0xFF7C3AED)),
            if (stack.memorabilia) AttrTag('PATCH', color: const Color(0xFF0369A1)),
            if (stack.ssp)         AttrTag('SSP', color: const Color(0xFFB45309)),
            if (stack.isGraded)    AttrTag(stack.gradeLabel),
            SerialTag(serialMax: stack.serialMax),
          ],
        ),
      ],
    );
  }

  Widget _buildValue(ColorScheme colors, CardStack stack) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('\$${stack.totalValue.toFixed2()}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        if (stack.qty > 1) Text('\$${(stack.totalValue / stack.qty).toFixed2()}/card', style: TextStyle(fontSize: 11, color: colors.onSurface.withValues(alpha: 0.5))),
        if (stack.totalCost > 0)
          Text('${stack.pl >= 0 ? '+' : ''}${stack.plPct.toFixed2()}%', style: TextStyle(fontSize: 12, color: _plColor, fontWeight: FontWeight.w600)),
        if (stack.qty > 1)
          Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: colors.onSurface.withValues(alpha: 0.4)),
      ],
    );
  }
}

class _IndividualCardRow extends StatelessWidget {
  const _IndividualCardRow({required this.card, this.onDelete});
  final UserCard card;
  final void Function(String)? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemDetailScreen(card: card))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (card.serialNumber != null)
                    Text('Copy #${card.serialNumber}', style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.6))),
                  if (card.pricePaid != null)
                    Text('Paid \$${card.pricePaid!.toFixed2()}', style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.6))),
                ],
              ),
            ),
            Text('\$${(card.currentValue ?? 0).toFixed2()}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 18, color: colors.error),
              onPressed: () => onDelete?.call(card.id),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}

extension on CardStack {
  bool get isGraded => cards.any((c) => c.isGraded);
  String get gradeLabel {
    final c = cards.firstWhere((c) => c.isGraded, orElse: () => cards.first);
    return '${c.grader ?? 'PSA'} ${c.gradeValue ?? c.grade ?? ''}';
  }
}

extension on double {
  String toFixed2() => toStringAsFixed(2);
}
