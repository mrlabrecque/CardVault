import 'package:cached_network_image/cached_network_image.dart';
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
  });

  final String title;
  final double price;
  final String chipLabel;
  final Color chipBackground;
  final Color chipForeground;
  final String? subtitle;
  final String? imageUrl;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final hasUrl = url != null && url!.isNotEmpty;
    final thumb = imageUrl;

    void openListing() {
      if (!hasUrl) return;
      launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication);
    }

    Widget thumbnail() {
      if (thumb != null && thumb.isNotEmpty) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: thumb,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorWidget: (context, url, error) => const SizedBox(width: 48, height: 48),
          ),
        );
      }
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.image_not_supported_outlined, size: 22, color: colors.outline),
      );
    }

    Widget content() {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          thumbnail(),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurface.withValues(alpha: 0.60),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '\$${price.toStringAsFixed(2)}',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: chipBackground,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            chipLabel,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: chipForeground,
                            ),
                          ),
                        ),
                        if (hasUrl) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: openListing,
                            icon: Icon(Icons.open_in_new, size: 18, color: colors.onSurface.withValues(alpha: 0.60)),
                            visualDensity: VisualDensity.compact,
                            style: IconButton.styleFrom(
                              minimumSize: const Size(44, 44),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                            ),
                            tooltip: 'Open listing',
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: hasUrl
          ? InkWell(
              onTap: openListing,
              borderRadius: BorderRadius.circular(8),
              child: content(),
            )
          : content(),
    );
  }
}
