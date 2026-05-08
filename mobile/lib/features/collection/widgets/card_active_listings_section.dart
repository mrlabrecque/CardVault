import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/comp.dart';
import '../../../core/services/comps_service.dart';
import '../../../core/widgets/adaptive_list_card.dart';
import '../../../core/widgets/card_fan_loader.dart';
import 'market_listing_row.dart';

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
        child: Center(child: CardFanLoader()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Text(
          _error!,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.error),
        ),
      );
    }

    final items = _items ?? [];
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDBB726)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.storefront_outlined, size: 20, color: Color(0xFFF59E0B)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No active listings',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFB45309),
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No matching Buy It Now or auction listings found right now.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurface.withValues(alpha: 0.60),
                          height: 1.35,
                        ),
                  ),
                ],
              ),
            ),
          ],
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.60),
                  ),
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
            child: Builder(
              builder: (context) {
                final listing = items[i];
                final chipBg = listing.isAuction
                    ? const Color(0xFF3B82F6).withValues(alpha: 0.15)
                    : const Color(0xFF16A34A).withValues(alpha: 0.15);
                final chipFg = listing.isAuction
                    ? const Color(0xFF2563EB)
                    : const Color(0xFF15803D);
                return MarketListingRow(
                  title: listing.title,
                  price: listing.price,
                  chipLabel: listing.isAuction ? 'Auction' : 'Buy It Now',
                  chipBackground: chipBg,
                  chipForeground: chipFg,
                  imageUrl: listing.imageUrl,
                  url: listing.url,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
