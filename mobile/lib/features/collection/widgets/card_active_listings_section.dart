import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/comp.dart';
import '../../../core/services/comps_service.dart';
import '../../../core/widgets/adaptive_list_card.dart';

/// Active eBay listings for a master card + parallel (from Edge Function).
class CardActiveListingsSection extends ConsumerStatefulWidget {
  const CardActiveListingsSection({
    super.key,
    required this.masterCardId,
    required this.parallelName,
  });

  final String masterCardId;
  final String parallelName;

  @override
  ConsumerState<CardActiveListingsSection> createState() => _CardActiveListingsSectionState();
}

class _CardActiveListingsSectionState extends ConsumerState<CardActiveListingsSection> {
  List<ActiveListing>? _items;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CardActiveListingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.masterCardId != widget.masterCardId ||
        oldWidget.parallelName != widget.parallelName) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref.read(compsServiceProvider).getActiveListings(
            widget.masterCardId,
            widget.parallelName,
          );
      if (mounted) {
        setState(() {
          _items = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Text(
          _error!,
          style: TextStyle(fontSize: 13, color: colors.error),
        ),
      );
    }

    final items = _items ?? [];
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDBB726)),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.black87),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.storefront_outlined, size: 18, color: Color(0xFFF59E0B)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'No active listings',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFB45309)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'No matching Buy It Now or auction listings found right now.',
                      style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.45)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${items.length} listing${items.length == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.5)),
            ),
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) => AdaptiveListCard(
            margin: EdgeInsets.zero,
            child: _ActiveListingRow(listing: items[i]),
          ),
        ),
      ],
    );
  }
}

class _ActiveListingRow extends StatelessWidget {
  const _ActiveListingRow({required this.listing});

  final ActiveListing listing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final thumb = listing.imageUrl;

    return InkWell(
      onTap: listing.url != null && listing.url!.isNotEmpty
          ? () => launchUrl(Uri.parse(listing.url!), mode: LaunchMode.externalApplication)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (thumb != null && thumb.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: thumb,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => const SizedBox(width: 48, height: 48),
                ),
              )
            else
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.image_not_supported_outlined, size: 22, color: colors.outline),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '\$${listing.price.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: listing.isAuction
                              ? const Color(0xFF3B82F6).withValues(alpha: 0.15)
                              : colors.outline.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          listing.isAuction ? 'Auction' : 'Buy It Now',
                          style: TextStyle(
                            fontSize: 10,
                            color: listing.isAuction ? const Color(0xFF2563EB) : colors.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (listing.url != null && listing.url!.isNotEmpty)
              Icon(Icons.open_in_new, size: 14, color: colors.onSurface.withValues(alpha: 0.45)),
          ],
        ),
      ),
    );
  }
}
