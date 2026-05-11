import 'package:card_vault/core/theme/fonts.dart';
import 'package:card_vault/core/utils/platform_utils.dart';
import 'package:card_vault/core/widgets/adaptive_list_card.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart' as animate;
import 'package:go_router/go_router.dart';
import '../../../core/models/user_card.dart';
import '../../../core/widgets/card_info_section.dart';
import '../../../core/widgets/list_item_usd_text.dart';

class SingleItemCard extends StatelessWidget {
  const SingleItemCard({
    super.key,
    required this.card,
    this.onDelete,
    this.onRefresh,
    this.isRefreshing = false,
    this.index = 0,
  });

  final UserCard card;
  final void Function(String cardId)? onDelete;
  final void Function(UserCard)? onRefresh;
  final bool isRefreshing;
  final int index;

  String get _sportEmoji => switch (card.sport.toLowerCase()) {
        'basketball' => '🏀',
        'baseball' => '⚾',
        'football' => '🏈',
        'hockey' => '🏒',
        'soccer' => '⚽',
        _ => '🏀',
      };

  void _openDetail(BuildContext context) {
    context.go('/collection/card', extra: card);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final staggerDelay = Duration(milliseconds: index.clamp(0, 8) * 60);

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildImage(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 12),
            child: CardInfoSection.fromUserCard(card),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 12, 12),
          child: _buildValue(colors),
        ),
      ],
    );

    final tappable = isIOS
        ? CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: () => _openDetail(context),
            child: row,
          )
        : InkWell(
            onTap: () => _openDetail(context),
            borderRadius: BorderRadius.circular(12),
            child: row,
          );

    return AdaptiveListCard(
      child: tappable,
    )
        .animate(delay: staggerDelay)
        .fadeIn(duration: const Duration(milliseconds: 200))
        .slideY(begin: 0.08, end: 0, duration: const Duration(milliseconds: 200));
  }

  Widget _buildImage() {
    if (card.imageUrl != null) {
      return ClipRRect(
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(6), bottomLeft: Radius.circular(6)),
        child: CachedNetworkImage(
          imageUrl: card.imageUrl!,
          width: 60,
          fit: BoxFit.fill,
          placeholder: (ctx, url) => _imagePlaceholder(),
          errorWidget: (ctx, url, err) => _imagePlaceholder(),
        ),
      );
    }
    return _imagePlaceholder();
  }

  Widget _imagePlaceholder() => Container(
        width: 60,
        height: 85,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.15),
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(6), bottomLeft: Radius.circular(6)),
        ),
        child: Center(child: Text(_sportEmoji, style: const TextStyle(fontSize: 40))),
      );

  Widget _buildValue(ColorScheme colors) {
    return DefaultTextStyle(
      style: TextStyle(color: colors.onSurface, fontFamily: AppFonts.fontFamily),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          ListItemUsdText(
            value: card.currentValue,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          if (card.pricePaid != null && card.pricePaid! > 0) ...[
            const SizedBox(height: 2),
            Text(
              '${((card.currentValue ?? 0) - (card.pricePaid ?? 0)) >= 0 ? '+' : ''}${(((card.currentValue ?? 0) - (card.pricePaid ?? 0)) / (card.pricePaid ?? 1) * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 12,
                color: ((card.currentValue ?? 0) - (card.pricePaid ?? 0)) >= 0 ? Colors.green : Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (onDelete != null) ...[
            const SizedBox(height: 4),
            IconButton(
              onPressed: () => onDelete?.call(card.id),
              icon: Icon(Icons.delete_outline, size: 20, color: colors.error),
              style: IconButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.all(10),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
