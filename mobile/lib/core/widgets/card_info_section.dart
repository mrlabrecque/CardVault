import 'package:flutter/material.dart';
import '../theme/fonts.dart';
import 'attr_tag.dart';
import 'serial_tag.dart';

class CardInfoSection extends StatelessWidget {
  const CardInfoSection({
    super.key,
    required this.player,
    required this.cardNumber,
    required this.year,
    required this.set,
    required this.parallel,
    required this.serialMax,
    this.sport = 'Unknown',
    this.rookie = false,
    this.autograph = false,
    this.memorabilia = false,
    this.ssp = false,
    this.isGraded = false,
    this.gradeLabel,
  });

  final String player;
  final String? cardNumber;
  final int? year;
  final String? set;
  final String? parallel;
  final int? serialMax;
  final String sport;
  final bool rookie;
  final bool autograph;
  final bool memorabilia;
  final bool ssp;
  final bool isGraded;
  final String? gradeLabel;


  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(text: player, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, fontFamily: AppFonts.fontFamily)),
              if (cardNumber != null)
                TextSpan(
                  text: '  #$cardNumber',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: colors.onSurface.withValues(alpha: 0.5),
                    fontFamily: AppFonts.fontFamily,
                  ),
                ),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          if (year != null || set != null)
            Text(
              [if (year != null) '$year', if (set != null) set].join(' · '),
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurface.withValues(alpha: 0.6),
                fontFamily: AppFonts.fontFamily,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (parallel != null && parallel != 'Base')
            Text(
              parallel!,
              style: TextStyle(
                fontSize: 12,
                color: colors.primary,
                fontFamily: AppFonts.fontFamily,
              ),
            ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              if (rookie) AttrTag('RC', color: const Color(0xFF16A34A)),
              if (autograph) AttrTag('AUTO', color: const Color(0xFF7C3AED)),
              if (memorabilia) AttrTag('PATCH', color: const Color(0xFF0369A1)),
              if (ssp) AttrTag('SSP', color: const Color(0xFFB45309)),
              if (isGraded && gradeLabel != null) AttrTag(gradeLabel!, color: const Color(0xFF9CA3AF)),
              if (serialMax != null) SerialTag(serialMax: serialMax),
            ],
          ),
        ],
    );
  }
}
