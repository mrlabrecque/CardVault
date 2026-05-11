import 'package:flutter/material.dart';
import '../models/user_card.dart';
import '../theme/fonts.dart';
import 'card_attributes_wrap.dart';

class CardInfoSection extends StatelessWidget {
  /// List-row metadata from a [UserCard] (set + checklist + grade line).
  ///
  /// Use [isGraded] / [gradeLabel] to override display (e.g. grading screen forces raw rows).
  factory CardInfoSection.fromUserCard(
    UserCard card, {
    Key? key,
    bool? isGraded,
    String? gradeLabel,
  }) {
    final explicit = gradeLabel?.trim();
    String? effectiveGradeLabel;
    if (explicit != null && explicit.isNotEmpty) {
      effectiveGradeLabel = explicit;
    } else {
      final graded = isGraded ?? card.isGraded;
      if (graded && card.isGraded) {
        final line = '${card.grader ?? 'PSA'} ${card.gradeValue ?? card.grade ?? ''}'.trim();
        effectiveGradeLabel = line.isEmpty ? null : line;
      }
    }
    final graded = isGraded ?? card.isGraded;
    return CardInfoSection(
      key: key,
      player: card.player,
      cardNumber: card.cardNumber,
      year: card.year,
      set: card.set,
      checklist: card.checklist,
      parallel: card.parallel,
      serialMax: card.serialMax,
      sport: card.sport,
      rookie: card.rookie,
      autograph: card.autograph,
      memorabilia: card.memorabilia,
      ssp: card.ssp,
      isGraded: graded,
      gradeLabel: effectiveGradeLabel,
    );
  }

  const CardInfoSection({
    super.key,
    required this.player,
    required this.cardNumber,
    required this.year,
    required this.set,
    this.checklist,
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
  final String? checklist;
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
    final trimmedParallel = parallel?.trim();
    final showParallel = trimmedParallel != null &&
        trimmedParallel.isNotEmpty &&
        trimmedParallel.toLowerCase() != 'base';
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
          if (year != null || set != null || checklist != null)
            Text(
              [
                if (year != null) '$year',
                if (set != null) set,
                if (checklist != null && checklist != set) checklist,
              ].join(' · '),
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurface.withValues(alpha: 0.6),
                fontFamily: AppFonts.fontFamily,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (showParallel)
            Text(
              trimmedParallel,
              style: TextStyle(
                fontSize: 12,
                color: colors.primary,
                fontFamily: AppFonts.fontFamily,
              ),
            ),
          const SizedBox(height: 4),
          CardAttributesWrap(
            rookie: rookie,
            autograph: autograph,
            memorabilia: memorabilia,
            ssp: ssp,
            isGraded: isGraded,
            gradeLabel: gradeLabel,
            serialMax: serialMax,
          ),
        ],
    );
  }
}
