import 'package:flutter/material.dart';
import '../../../core/utils/adaptive_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart' as animate;
import '../../../core/models/user_card.dart';
import '../../../core/widgets/serial_tag.dart';
import '../../../core/widgets/attr_tag.dart';
import '../item_detail_screen.dart';

class CardStackTile extends StatefulWidget {
  const CardStackTile({
    super.key,
    required this.stack,
    this.onDelete,
    this.onRefresh,
    this.isRefreshing = false,
    this.index = 0,
  });
  final CardStack stack;
  final void Function(String cardId)? onDelete;
  final void Function(CardStack)? onRefresh;
  final bool isRefreshing;
  final int index;

  @override
  State<CardStackTile> createState() => _CardStackTileState();
}

class _CardStackTileState extends State<CardStackTile> with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _spinCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void didUpdateWidget(CardStackTile old) {
    super.didUpdateWidget(old);
    if (widget.isRefreshing && !_spinCtrl.isAnimating) {
      _spinCtrl.repeat();
    } else if (!widget.isRefreshing && _spinCtrl.isAnimating) {
      _spinCtrl.stop();
      _spinCtrl.reset();
    }
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    super.dispose();
  }

  String get _sportEmoji => switch (widget.stack.sport.toLowerCase()) {
    'basketball' => '🏀',
    'baseball'   => '⚾',
    'football'   => '🏈',
    'hockey'     => '🏒',
    'soccer'     => '⚽',
    _            => '🏀',
  };

  Color get _plColor => widget.stack.pl >= 0 ? Colors.green : Colors.red;

  void _openDetail(BuildContext context, UserCard card) {
    showAdaptiveSheet(
      context: context,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height,
        child: ItemDetailScreen(card: card),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final stack = widget.stack;
    final staggerDelay = Duration(milliseconds: widget.index.clamp(0, 8) * 60);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF3F4F6)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: stack.qty > 1
                ? () => setState(() => _expanded = !_expanded)
                : () => _openDetail(context, stack.cards.first),
            borderRadius: BorderRadius.circular(14),
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
          )
              .animate(delay: staggerDelay)
              .fadeIn(duration: const Duration(milliseconds: 200))
              .slideY(begin: 0.08, end: 0, duration: const Duration(milliseconds: 200)),
          if (_expanded) ...[
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
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
    return DefaultTextStyle(
      style: const TextStyle(color: Colors.black87),
      child: Column(
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
            if (stack.isGraded)    AttrTag(stack.gradeLabel, color: const Color(0xFF9CA3AF)),
            SerialTag(serialMax: stack.serialMax),
          ],
        ),
      ],
      ),
    );
  }

  Widget _buildValue(ColorScheme colors, CardStack stack) {
    return DefaultTextStyle(
      style: const TextStyle(color: Colors.black87),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onRefresh != null)
              GestureDetector(
                onTap: widget.isRefreshing ? null : () => widget.onRefresh!(stack),
                child: Container(
                  width: 26,
                  height: 26,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: RotationTransition(
                      turns: _spinCtrl,
                      child: Icon(Icons.refresh, size: 13, color: colors.onSurface.withValues(alpha: widget.isRefreshing ? 0.8 : 0.4)),
                    ),
                  ),
                ),
              ),
            if (stack.valueTrend != 0)
              Icon(
                stack.valueTrend > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                size: 13,
                color: stack.valueTrend > 0 ? Colors.green : Colors.red,
              ),
            Text('\$${stack.totalValue.toFixed2()}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ],
        ),
        if (stack.qty > 1) Text('\$${(stack.totalValue / stack.qty).toFixed2()}/card', style: TextStyle(fontSize: 11, color: colors.onSurface.withValues(alpha: 0.5))),
        if (stack.totalCost > 0)
          Text('${stack.pl >= 0 ? '+' : ''}${stack.plPct.toFixed2()}%', style: TextStyle(fontSize: 12, color: _plColor, fontWeight: FontWeight.w600)),
        if (stack.qty > 1)
          Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: colors.onSurface.withValues(alpha: 0.4)),
      ],
      ),
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
      onTap: () => showAdaptiveSheet(
        context: context,
        builder: (_) => SizedBox(
          height: MediaQuery.of(context).size.height,
          child: ItemDetailScreen(card: card),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.black87),
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
