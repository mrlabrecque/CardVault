import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/currency_format.dart';
import '../../../core/ui/price_guide_copy.dart';
import '../../../core/utils/guide_grade_prices.dart';
import '../../../core/widgets/adaptive_list_card.dart';
import '../../../core/widgets/inline_notice_container.dart';

/// Short date for sold / listing-end meta lines (Today, Yesterday, M/D/YYYY).
String formatMarketListingMetaDate(DateTime dt) {
  final local = dt.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final day = DateTime(local.year, local.month, local.day);

  if (day == today) return 'Today';
  if (day == yesterday) return 'Yesterday';
  return '${local.month}/${local.day}/${local.year}';
}

/// Neutral grade pill on a market listing row (Raw, PSA 10, etc.).
class MarketListingGradeTag extends StatelessWidget {
  const MarketListingGradeTag({
    super.key,
    required this.label,
    this.muted = false,
  });

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = label.trim().isEmpty ? 'Raw' : label.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(
          alpha: muted ? 0.35 : 0.65,
        ),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: colors.outline.withValues(alpha: muted ? 0.22 : 0.45),
        ),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.onSurface.withValues(alpha: muted ? 0.38 : 0.78),
            ),
      ),
    );
  }
}

/// One sold-comp or active-listing row (catalog + owned).
class MarketListingRow extends StatelessWidget {
  const MarketListingRow({
    super.key,
    required this.title,
    required this.price,
    required this.chipLabel,
    required this.chipBackground,
    required this.chipForeground,
    this.metaLine,
    this.imageUrl,
    this.url,
    this.excludedFromStats = false,
    this.gradeTag,
    this.vsGuideDealTier,
    this.vsGuideLabel,
    this.vsGuideForeground,
    this.vsGuideCompareGrade,
    this.vsGuidePriceMissing = false,
  });

  final String title;
  final double price;
  final String chipLabel;
  final Color chipBackground;
  final Color chipForeground;
  /// e.g. `Sold on: 5/16/2026` or `Listing ends: Today` — baseline-aligned with tags.
  final String? metaLine;
  final String? imageUrl;
  final String? url;
  final bool excludedFromStats;
  /// Grade pill on the meta row (not part of [title]).
  final String? gradeTag;
  final ActiveListingGuideDealTier? vsGuideDealTier;
  final String? vsGuideLabel;
  final Color? vsGuideForeground;
  final String? vsGuideCompareGrade;
  final bool vsGuidePriceMissing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final hasUrl = url != null && url!.isNotEmpty;
    final thumb = imageUrl;
    final muted = excludedFromStats;
    final titleColor = muted
        ? colors.onSurface.withValues(alpha: 0.30)
        : colors.onSurface;
    final metaColor = muted
        ? colors.onSurface.withValues(alpha: 0.28)
        : colors.onSurface.withValues(alpha: 0.60);
    final metaStyle = theme.textTheme.labelSmall?.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      height: 1.2,
      color: metaColor,
    );
    final priceColor = muted
        ? colors.onSurface.withValues(alpha: 0.28)
        : colors.onSurface;

    void openListing() {
      if (!hasUrl) return;
      launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication);
    }

    const thumbWidth = 48.0;
    const thumbHeight = 56.0;
    const thumbGap = 12.0;
    final hasMetaLine = metaLine != null && metaLine!.trim().isNotEmpty;

    Widget thumbnail() {
      Widget thumbChild;
      if (thumb != null && thumb.isNotEmpty) {
        thumbChild = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: thumb,
            width: thumbWidth,
            height: thumbHeight,
            fit: BoxFit.cover,
            errorWidget: (context, url, error) =>
                SizedBox(width: thumbWidth, height: thumbHeight),
          ),
        );
      } else {
        thumbChild = Container(
          width: thumbWidth,
          height: thumbHeight,
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.image_not_supported_outlined,
            size: 22,
            color: colors.outline.withValues(alpha: muted ? 0.35 : 1),
          ),
        );
      }
      if (!muted) return thumbChild;
      return Opacity(opacity: 0.45, child: thumbChild);
    }

    final showDealGlyph =
        !muted && vsGuideDealTier != null && vsGuideForeground != null;
    final showNoGuideGlyph = !muted && vsGuidePriceMissing && !showDealGlyph;
    final gradeLabel = gradeTag?.trim();
    final showGradeTag = gradeLabel != null && gradeLabel.isNotEmpty;
    final noGuideSemantic = [
      PriceGuideCopy.noPriceGuide,
      if (showGradeTag) 'for $gradeLabel',
    ].join(' ');

    Widget metaAndTagsRow() {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: hasMetaLine
                ? Text(metaLine!.trim(), style: metaStyle)
                : const SizedBox.shrink(),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showGradeTag) ...[
                MarketListingGradeTag(label: gradeLabel, muted: muted),
                const SizedBox(width: 6),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: muted
                      ? colors.surfaceContainerHighest.withValues(alpha: 0.5)
                      : chipBackground,
                  borderRadius: BorderRadius.circular(4),
                  border: muted
                      ? Border.all(
                          color: colors.outline.withValues(alpha: 0.2),
                        )
                      : null,
                ),
                child: Text(
                  chipLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    color: muted
                        ? colors.onSurface.withValues(alpha: 0.32)
                        : chipForeground,
                  ),
                ),
              ),
              if (hasUrl) ...[
                const SizedBox(width: 4),
                Semantics(
                  button: true,
                  label: 'Open listing',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: openListing,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                        child: Icon(
                          Icons.open_in_new,
                          size: 18,
                          color: colors.onSurface.withValues(
                            alpha: muted ? 0.32 : 0.60,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      );
    }

    Widget content() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              thumbnail(),
              const SizedBox(width: thumbGap),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: titleColor,
                  ),
                ),
              ),
              const SizedBox(width: thumbGap),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showDealGlyph) ...[
                    Semantics(
                      label: [
                        vsGuideLabel ?? PriceGuideCopy.listingVsPriceGuide,
                        if (vsGuideCompareGrade != null &&
                            vsGuideCompareGrade!.trim().isNotEmpty)
                          PriceGuideCopy.vsPriceGuideGrade(vsGuideCompareGrade!.trim()),
                      ].join(' — '),
                      child: Icon(
                        dealTierCupertinoIcon(vsGuideDealTier!),
                        size: 22,
                        color: vsGuideForeground,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else if (showNoGuideGlyph) ...[
                    Semantics(
                      label: noGuideSemantic,
                      child: Icon(
                        CupertinoIcons.slash_circle,
                        size: 22,
                        color: colors.onSurface.withValues(alpha: 0.42),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    formatUsd(price),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: priceColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          metaAndTagsRow(),
          if (muted) ...[
            const SizedBox(height: 6),
            Text(
              'Excluded from chart & average',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurface.withValues(alpha: 0.32),
                fontWeight: FontWeight.w500,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      );
    }

    final body = Padding(
      padding: const EdgeInsets.all(12),
      child: hasUrl
          ? InkWell(
              onTap: openListing,
              borderRadius: BorderRadius.circular(8),
              excludeFromSemantics: true,
              child: content(),
            )
          : content(),
    );

    if (!muted) return body;

    return Opacity(
      opacity: 0.72,
      child: body,
    );
  }
}

/// Shared count header + separated listing cards for Sold Comps and For Sale.
class MarketListingsList extends StatelessWidget {
  const MarketListingsList({
    super.key,
    required this.countLabel,
    required this.rows,
    this.headerTrailing,
    this.countPadding = const EdgeInsets.symmetric(vertical: 8),
  });

  final String countLabel;
  final List<MarketListingRow> rows;
  final Widget? headerTrailing;
  final EdgeInsets countPadding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: countPadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  countLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.60),
                      ),
                ),
              ),
              ?headerTrailing,
            ],
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) => AdaptiveListCard(
            margin: EdgeInsets.zero,
            child: rows[i],
          ),
        ),
      ],
    );
  }
}

/// iOS-style callout for empty/error states in market analysis (comps, for sale).
class MarketSectionNotice extends StatelessWidget {
  const MarketSectionNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.highlightBorderColor,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color? highlightBorderColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        );
    final bodyStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          height: 1.35,
          color: colors.onSurface.withValues(alpha: 0.72),
        );

    return InlineNoticeContainer(
      icon: Icon(icon, size: 20, color: colors.onSurface.withValues(alpha: 0.55)),
      highlightBorderColor: highlightBorderColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: titleStyle),
          const SizedBox(height: 4),
          Text(message, style: bodyStyle),
        ],
      ),
    );
  }
}
