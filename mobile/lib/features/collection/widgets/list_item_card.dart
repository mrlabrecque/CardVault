import 'package:card_vault/core/theme/fonts.dart';
import 'package:card_vault/core/utils/platform_utils.dart';
import 'package:card_vault/core/widgets/adaptive_list_card.dart';
import 'package:card_vault/core/widgets/card_thumbnail.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart' as animate;
import 'package:go_router/go_router.dart';
import '../../../core/models/user_card.dart';
import '../../../core/widgets/card_info_section.dart';
class ListItemCard extends StatefulWidget {
  const ListItemCard({
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
  State<ListItemCard> createState() => _ListItemCardState();
}

class _ListItemCardState extends State<ListItemCard> with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _spinCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void didUpdateWidget(ListItemCard old) {
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

  Color get _plColor => widget.stack.pl >= 0 ? Colors.green : Colors.red;

  void _openDetail(BuildContext context, UserCard card) {
    context.go('/collection/card', extra: card);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final stack = widget.stack;
    final staggerDelay = Duration(milliseconds: widget.index.clamp(0, 8) * 60);

    void onHeaderTap() {
      if (stack.qty > 1) {
        setState(() => _expanded = !_expanded);
      } else {
        _openDetail(context, stack.cards.first);
      }
    }

    final header = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardThumbnail(imageUrl: stack.imageUrl, sport: stack.sport, width: 70),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 12),
              child: CardInfoSection(
                player: stack.player,
                cardNumber: stack.cardNumber,
                year: stack.year,
                set: stack.set,
                parallel: stack.parallel,
                serialMax: stack.serialMax,
                sport: stack.sport,
                rookie: stack.rookie,
                autograph: stack.autograph,
                memorabilia: stack.memorabilia,
                ssp: stack.ssp,
                isGraded: stack.isGraded,
                gradeLabel: stack.gradeLabel,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 12, 12),
            child: _buildValue(colors, stack),
          ),
        ],
      ),
    );

    final tappableHeader = isIOS
        ? CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: onHeaderTap,
            child: header,
          )
        : InkWell(
            onTap: onHeaderTap,
            borderRadius: BorderRadius.circular(12),
            child: header,
          );

    return AdaptiveListCard(
      child: Column(
        children: [
          tappableHeader
              .animate(delay: staggerDelay)
              .fadeIn(duration: const Duration(milliseconds: 200))
              .slideY(begin: 0.08, end: 0, duration: const Duration(milliseconds: 200)),
          if (_expanded) ...[
            Divider(height: 1, color: colors.outlineVariant),
            ...stack.cards.map((c) => _IndividualCardRow(card: c, onDelete: widget.onDelete)),
          ],
        ],
      ),
    );
  }



  Widget _buildValue(ColorScheme colors, CardStack stack) {
    return DefaultTextStyle(
      style: TextStyle(color: colors.onSurface, fontFamily: AppFonts.fontFamily),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onRefresh != null)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: IconButton(
                  onPressed: widget.isRefreshing ? null : () => widget.onRefresh!(stack),
                  icon: RotationTransition(
                    turns: _spinCtrl,
                    child: Icon(Icons.refresh, size: 18, color: colors.onSurface.withValues(alpha: widget.isRefreshing ? 0.8 : 0.45)),
                  ),
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(44, 44),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    side: BorderSide(color: colors.outlineVariant),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    backgroundColor: colors.surfaceContainerHighest.withValues(alpha: 0.5),
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
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DefaultTextStyle(
        style: TextStyle(color: colors.onSurface),
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
            IconButton(
              icon: Icon(Icons.delete_outline, size: 20, color: colors.error),
              onPressed: () => onDelete?.call(card.id),
              style: IconButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.all(10),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );

    if (isIOS) {
      return CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: () => context.go('/collection/card', extra: card),
        child: row,
      );
    }
    return InkWell(
      onTap: () => context.go('/collection/card', extra: card),
      child: row,
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
