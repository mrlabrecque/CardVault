import 'package:flutter/material.dart';
import '../../../core/utils/adaptive_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart' as animate;
import '../../../core/models/user_card.dart';
import '../../../core/widgets/card_info_section.dart';
import '../../../core/theme/fonts.dart';
import '../item_detail_screen.dart';

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
    'baseball'   => '⚾',
    'football'   => '🏈',
    'hockey'     => '🏒',
    'soccer'     => '⚽',
    _            => '🏀',
  };

  void _openDetail(BuildContext context) {
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
    final staggerDelay = Duration(milliseconds: index.clamp(0, 8) * 60);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF3F4F6)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetail(context),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildImage(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 6, 12),
                  child: CardInfoSection(
                    player: card.player,
                    cardNumber: card.cardNumber,
                    year: card.year,
                    set: card.set,
                    parallel: card.parallel,
                    serialMax: card.serialMax,
                    sport: card.sport,
                    rookie: card.rookie,
                    autograph: card.autograph,
                    memorabilia: card.memorabilia,
                    ssp: card.ssp,
                    isGraded: card.isGraded,
                    gradeLabel: card.isGraded ? '${card.grader ?? 'PSA'} ${card.gradeValue ?? card.grade ?? ''}' : null,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 8, 12, 12),
                child: _buildValue(colors),
              ),
            ],
          ),
        ),
      ),
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
      style: TextStyle(color: Colors.black87, fontFamily: AppFonts.fontFamily),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('\$${(card.currentValue ?? 0).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
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
            GestureDetector(
              onTap: () => onDelete?.call(card.id),
              child: Icon(Icons.delete_outline, size: 18, color: colors.error),
            ),
          ],
        ],
      ),
    );
  }
}
