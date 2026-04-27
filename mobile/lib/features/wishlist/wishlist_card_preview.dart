import 'package:flutter/material.dart';
import '../../core/services/cards_service.dart';
import '../../core/widgets/attr_tag.dart';

class WishlistCardPreview extends StatelessWidget {
  const WishlistCardPreview({
    super.key,
    required this.card,
    required this.setName,
    required this.releaseName,
  });

  final MasterCard? card;
  final String? setName;
  final String? releaseName;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF3F4F6)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2))],
      ),
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
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              if (card?.isRookie ?? false) AttrTag('RC', color: const Color(0xFF16A34A)),
              if (card?.isAuto ?? false) AttrTag('AUTO', color: const Color(0xFF7C3AED)),
              if (card?.isPatch ?? false) AttrTag('PATCH', color: const Color(0xFF0369A1)),
              if (card?.serialMax != null) AttrTag('/${card!.serialMax}', color: const Color(0xFF6366F1)),
            ],
          ),
        ],
      ),
    );
  }
}
