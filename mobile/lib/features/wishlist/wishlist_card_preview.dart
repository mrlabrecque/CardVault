import 'package:card_vault/core/widgets/adaptive_list_card.dart';
import 'package:flutter/material.dart';
import '../../core/services/cards_service.dart';
import '../../core/widgets/card_attributes_wrap.dart';

class WishlistCardPreview extends StatelessWidget {
  const WishlistCardPreview({
    super.key,
    required this.card,
    required this.setName,
    required this.releaseName,
    this.parallelName,
    this.parallelSerialMax,
    this.parallelIsAuto = false,
  });

  final MasterCard? card;
  final String? setName;
  final String? releaseName;
  final String? parallelName;
  final int? parallelSerialMax;
  final bool parallelIsAuto;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AdaptiveListCard(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: card?.player ?? 'Unknown',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              if (card?.cardNumber != null)
                TextSpan(
                  text: '  #${card!.cardNumber}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: colors.onSurface.withValues(alpha: 0.5)),
                ),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          if (setName != null || releaseName != null)
            Text(
              [
                if (releaseName != null) releaseName,
                if (setName != null) setName,
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.6)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (parallelName != null && parallelName!.trim().isNotEmpty && parallelName!.trim().toLowerCase() != 'base')
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                parallelName!.trim(),
                style: TextStyle(fontSize: 12, color: colors.primary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(height: 8),
          CardAttributesWrap(
            rookie: card?.isRookie ?? false,
            autograph: (card?.isAuto ?? false) || parallelIsAuto,
            memorabilia: card?.isPatch ?? false,
            ssp: card?.isSSP ?? false,
            serialMax: parallelSerialMax ?? card?.serialMax,
          ),
          ],
        ),
      ),
    );
  }
}
