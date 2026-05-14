import 'package:card_vault/core/theme/fonts.dart';
import 'package:card_vault/core/utils/platform_utils.dart';
import 'package:card_vault/core/widgets/adaptive_list_card.dart';
import 'package:card_vault/core/widgets/card_thumbnail.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart' as animate;
import 'package:go_router/go_router.dart';
import '../../../core/models/user_card.dart';
import '../../../core/utils/currency_format.dart';
import '../../../core/widgets/card_info_section.dart';

class ListItemCard extends StatefulWidget {
  const ListItemCard({
    super.key,
    required this.stack,
    this.onDelete,
    this.index = 0,
  });
  final CardStack stack;
  final void Function(String cardId)? onDelete;
  final int index;

  @override
  State<ListItemCard> createState() => _ListItemCardState();
}

class _ListItemCardState extends State<ListItemCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

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

    final info = Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 6, 12),
      child: CardInfoSection(
        player: stack.player,
        cardNumber: stack.cardNumber,
        year: stack.year,
        releaseName: stack.set,
        setName: stack.checklist,
        parallelName: stack.parallel,
        serialMax: stack.serialMax,
        sport: stack.sport,
        rookie: stack.rookie,
        autograph: stack.autograph,
        memorabilia: stack.memorabilia,
        ssp: stack.ssp,
        isGraded: stack.isGraded,
        gradeLabel: stack.gradeLabel,
      ),
    );

    final tappableInfo = isIOS
        ? CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: onHeaderTap,
            child: Align(alignment: Alignment.centerLeft, child: info),
          )
        : InkWell(
            onTap: onHeaderTap,
            borderRadius: BorderRadius.circular(12),
            child: info,
          );

    final header = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardThumbnail(imageUrl: stack.imageUrl, sport: stack.sport),
          const SizedBox(width: 10),
          Expanded(child: tappableInfo),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 12, 12),
            child: _buildValue(colors, stack),
          ),
        ],
      ),
    );

    return AdaptiveListCard(
      child: Column(
        children: [
          header
              .animate(delay: staggerDelay)
              .fadeIn(duration: const Duration(milliseconds: 200))
              .slideY(
                begin: 0.08,
                end: 0,
                duration: const Duration(milliseconds: 200),
              ),
          if (_expanded) ...[
            Divider(height: 1, color: colors.outlineVariant),
            ...stack.cards.map(
              (c) => _IndividualCardRow(card: c, onDelete: widget.onDelete),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildValue(ColorScheme colors, CardStack stack) {
    final hasAnyValue = stack.cards.any((c) => c.displayValue != null);
    return DefaultTextStyle(
      style: TextStyle(
        color: colors.onSurface,
        fontFamily: AppFonts.fontFamily,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasAnyValue && stack.valueTrend != 0)
                Icon(
                  stack.valueTrend > 0
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 13,
                  color: stack.valueTrend > 0 ? Colors.green : Colors.red,
                ),
              Text(
                hasAnyValue ? formatUsd(stack.totalValue) : 'N/A',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          if (!hasAnyValue)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 12,
                  color: colors.onSurface.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 4),
                Text(
                  'No guide price',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          if (hasAnyValue && stack.qty > 1)
            Text(
              '${formatUsd(stack.totalValue / stack.qty)}/card',
              style: TextStyle(
                fontSize: 11,
                color: colors.onSurface.withValues(alpha: 0.5),
              ),
            ),
          if (hasAnyValue && stack.totalCost > 0)
            Text(
              '${stack.pl >= 0 ? '+' : ''}${stack.plPct.toStringAsFixed(2)}%',
              style: TextStyle(
                fontSize: 12,
                color: _plColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (stack.qty > 1)
            Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: colors.onSurface.withValues(alpha: 0.4),
            ),
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
                    Text(
                      'Copy #${card.serialNumber}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  if (card.pricePaid != null)
                    Text(
                      'Paid ${formatUsd(card.pricePaid!)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
            ),
            Text(
              card.displayValue != null ? formatUsd(card.displayValue!) : 'N/A',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
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
