import 'package:flutter/material.dart';

import '../models/cardhedge_image_search.dart';
import '../models/user_card.dart';
import '../theme/fonts.dart';
import 'card_attributes_wrap.dart';

class CardInfoSection extends StatelessWidget {
  /// List-row metadata from a [UserCard] (release + set + grade line).
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
        final line =
            '${card.grader ?? 'PSA'} ${card.gradeValue ?? card.grade ?? ''}'
                .trim();
        effectiveGradeLabel = line.isEmpty ? null : line;
      }
    }
    final graded = isGraded ?? card.isGraded;
    return CardInfoSection(
      key: key,
      player: card.player,
      cardNumber: card.cardNumber,
      year: card.year,
      releaseName: card.set,
      setName: card.checklist,
      parallelName: card.parallel,
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

  /// CardHedge image-search row: release from **`set_type`** else **`set`**, with leading year and
  /// trailing **`category`** stripped for [releaseName]; derived product line → [setName]; **`variant` → [parallelName]**.
  factory CardInfoSection.fromCardHedgeHit(
    CardHedgeImageSearchHit hit, {
    Key? key,
    required String sport,
  }) {
    final player = (hit.player?.trim().isNotEmpty == true)
        ? hit.player!.trim()
        : 'Unknown player';
    final numLine = hit.number?.trim();
    final releaseName = hit.displayReleaseName;

    final setTypeTrimmed = hit.setType?.trim();
    final setLabelTrimmed = hit.setLabel?.trim();
    int? year;
    for (final src in [setTypeTrimmed, setLabelTrimmed]) {
      if (src == null || src.isEmpty) continue;
      final m = RegExp(r'\b(19|20)\d{2}\b').firstMatch(src);
      if (m != null) {
        year = int.tryParse(m.group(0)!);
        break;
      }
    }

    return CardInfoSection(
      key: key,
      player: player,
      cardNumber: (numLine != null && numLine.isNotEmpty) ? numLine : null,
      year: year,
      releaseName: releaseName,
      setName: hit.displaySetName,
      parallelName: hit.displayParallelName,
      serialMax: null,
      sport: sport,
    );
  }

  const CardInfoSection({
    super.key,
    required this.player,
    required this.cardNumber,
    required this.year,
    required this.releaseName,
    this.setName,
    this.parallelName,
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

  /// Vault **release** line (`releases` / product). CardHedge: `set_type`, or `set` if `set_type` is absent.
  final String? releaseName;

  /// Vault **set** line (`sets` / checklist product).
  final String? setName;
  final String? parallelName;
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
    final trimmedParallel = parallelName?.trim();
    final showParallel =
        trimmedParallel != null &&
        trimmedParallel.isNotEmpty &&
        trimmedParallel.toLowerCase() != 'base';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: player,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  fontFamily: AppFonts.fontFamily,
                ),
              ),
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
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        if (year != null || releaseName != null || setName != null)
          Text(
            [
              if (year != null) '$year',
              if (releaseName != null && releaseName!.trim().isNotEmpty)
                releaseName!.trim(),
              if (setName != null &&
                  setName!.trim().isNotEmpty &&
                  setName!.trim() != (releaseName?.trim() ?? ''))
                setName!.trim(),
            ].join(' • '),
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
