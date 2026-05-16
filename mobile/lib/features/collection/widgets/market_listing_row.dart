import '../../../core/utils/currency_format.dart';
import '../../../core/utils/guide_grade_prices.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class MarketListingRow extends StatelessWidget {
  const MarketListingRow({
    super.key,
    required this.title,
    required this.price,
    required this.chipLabel,
    required this.chipBackground,
    required this.chipForeground,
    this.subtitle,
    this.imageUrl,
    this.url,
    this.excludedFromStats = false,
    this.vsGuideDealTier,
    this.vsGuideLabel,
    this.vsGuideForeground,
    this.vsGuideBackground,
    this.listingConditionTag,
    this.vsGuideCompareGrade,
    this.vsGuidePriceMissing = false,
  });

  final String title;
  final double price;
  final String chipLabel;
  final Color chipBackground;
  final Color chipForeground;
  final String? subtitle;
  final String? imageUrl;
  final String? url;
  /// Outlier sale — shown in list but omitted from chart and averages.
  final bool excludedFromStats;
  /// CardHedge guide tier (For Sale tab). Drives SF-style arrow icons.
  final ActiveListingGuideDealTier? vsGuideDealTier;
  /// Spoken / tooltip label for [vsGuideDealTier] (e.g. "Great Deal").
  final String? vsGuideLabel;
  final Color? vsGuideForeground;
  final Color? vsGuideBackground;
  /// Raw / slab inferred from the listing title (e.g. `PSA 10`).
  final String? listingConditionTag;
  /// Guide grade used for the deal icon, for accessibility (e.g. same as tag when matched).
  final String? vsGuideCompareGrade;
  /// When guide data exists but no matching price row for this listing (e.g. slab grade not in guide).
  final bool vsGuidePriceMissing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final hasUrl = url != null && url!.isNotEmpty;
    final thumb = imageUrl;
    final muted = excludedFromStats;
    final titleColor = muted
        ? colors.onSurface.withValues(alpha: 0.45)
        : colors.onSurface;
    final subtitleColor = muted
        ? colors.onSurface.withValues(alpha: 0.38)
        : colors.onSurface.withValues(alpha: 0.60);
    final priceColor = muted
        ? colors.onSurface.withValues(alpha: 0.42)
        : colors.onSurface;

    void openListing() {
      if (!hasUrl) return;
      launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication);
    }

    const thumbWidth = 48.0;
    const thumbHeight = 56.0;
    const thumbGap = 12.0;
    final secondRowLeftInset = thumbWidth + thumbGap;

    Widget thumbnail() {
      if (thumb != null && thumb.isNotEmpty) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: thumb,
            width: thumbWidth,
            height: thumbHeight,
            fit: BoxFit.cover,
            errorWidget: (context, url, error) => SizedBox(width: thumbWidth, height: thumbHeight),
          ),
        );
      }
      return Container(
        width: thumbWidth,
        height: thumbHeight,
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.image_not_supported_outlined, size: 22, color: colors.outline),
      );
    }

    final showDealGlyph = !muted &&
        vsGuideDealTier != null &&
        vsGuideForeground != null;
    final showNoGuideGlyph =
        !muted && vsGuidePriceMissing && !showDealGlyph;
    final noGuideSemantic = [
      'No guide price',
      if (listingConditionTag != null && listingConditionTag!.trim().isNotEmpty)
        'for ${listingConditionTag!.trim()}',
    ].join(' ');

    Widget content() {
      return Column(
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
                        vsGuideLabel ?? 'Listing vs price guide',
                        if (vsGuideCompareGrade != null && vsGuideCompareGrade!.trim().isNotEmpty)
                          'vs $vsGuideCompareGrade guide',
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: secondRowLeftInset),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: subtitleColor,
                        ),
                      ),
                    if (muted) ...[
                      if (subtitle != null && subtitle!.isNotEmpty) const SizedBox(height: 6),
                      Text(
                        'Excluded from chart & average',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurface.withValues(alpha: 0.38),
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (listingConditionTag != null && listingConditionTag!.trim().isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: colors.outline.withValues(alpha: 0.45)),
                      ),
                      child: Text(
                        listingConditionTag!.trim(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface.withValues(alpha: 0.78),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (!muted &&
                      vsGuideDealTier != null &&
                      vsGuideLabel != null &&
                      vsGuideLabel!.trim().isNotEmpty &&
                      vsGuideForeground != null &&
                      vsGuideBackground != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: vsGuideBackground,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        vsGuideLabel!.trim(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: vsGuideForeground,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: muted ? colors.surfaceContainerHighest : chipBackground,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      chipLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: muted
                            ? colors.onSurface.withValues(alpha: 0.4)
                            : chipForeground,
                      ),
                    ),
                  ),
                  if (hasUrl) ...[
                    const SizedBox(width: 2),
                    IconButton(
                      onPressed: openListing,
                      icon: Icon(Icons.open_in_new, size: 18, color: colors.onSurface.withValues(alpha: 0.60)),
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(32, 32),
                        maximumSize: const Size(32, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.all(2),
                      ),
                      tooltip: 'Open listing',
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      );
    }

    return Padding(
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
  }
}
