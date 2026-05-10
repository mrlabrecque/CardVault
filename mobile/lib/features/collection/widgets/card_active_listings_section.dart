import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/comp.dart';
import '../../../core/services/comps_service.dart';
import '../../../core/widgets/adaptive_list_card.dart';
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
  static const List<String> _loadingStatusSteps = [
    'Refreshing active listings...',
    'Scanning current auctions and BIN posts...',
    'Matching active items to this card...',
  ];

  List<ActiveListing>? _items;
  bool _loading = true;
  String? _error;
  int _loadingStatusIndex = 0;
  Timer? _loadingStatusTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _syncLoadingTicker();
  }

  @override
  void dispose() {
    _loadingStatusTimer?.cancel();
    super.dispose();
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
    _syncLoadingTicker();
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
        _syncLoadingTicker();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
        _syncLoadingTicker();
      }
    }
  }

  String get _loadingStatusText {
    final idx = _loadingStatusIndex.clamp(0, _loadingStatusSteps.length - 1);
    return _loadingStatusSteps[idx];
  }

  void _syncLoadingTicker() {
    if (!_loading) {
      _loadingStatusTimer?.cancel();
      _loadingStatusTimer = null;
      _loadingStatusIndex = 0;
      return;
    }
    if (_loadingStatusTimer != null) return;
    _loadingStatusIndex = 0;
    _loadingStatusTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() {
        _loadingStatusIndex = (_loadingStatusIndex + 1) % _loadingStatusSteps.length;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 450),
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: Text(
                    _loadingStatusText,
                    key: ValueKey(_loadingStatusText),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurface.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w500,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const _ActiveListingSkeletonWave(),
            const SizedBox(height: 8),
            const _ActiveListingSkeletonWave(),
            const SizedBox(height: 8),
            const _ActiveListingSkeletonWave(),
          ],
        ),
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

class _ActiveListingSkeletonWave extends StatelessWidget {
  const _ActiveListingSkeletonWave();

  @override
  Widget build(BuildContext context) {
    return AdaptiveListCard(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const _WaveSkeletonBox(
              width: 56,
              height: 56,
              radius: 10,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _WaveSkeletonBox(
                    height: 12,
                    width: double.infinity,
                    radius: 8,
                  ),
                  SizedBox(height: 8),
                  _WaveSkeletonBox(
                    height: 11,
                    width: 150,
                    radius: 8,
                  ),
                  SizedBox(height: 8),
                  _WaveSkeletonBox(
                    height: 20,
                    width: 94,
                    radius: 20,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const _WaveSkeletonBox(
              height: 14,
              width: 56,
              radius: 8,
            ),
          ],
        ),
      ),
    );
  }
}

class _WaveSkeletonBox extends StatefulWidget {
  const _WaveSkeletonBox({
    required this.width,
    required this.height,
    this.radius = 8,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<_WaveSkeletonBox> createState() => _WaveSkeletonBoxState();
}

class _WaveSkeletonBoxState extends State<_WaveSkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final base = colors.surfaceContainerHighest.withValues(alpha: 0.72);
    final glow = colors.surface.withValues(alpha: 0.75);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final shift = (_controller.value * 2) - 1;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1.6 + shift, 0),
              end: Alignment(-0.4 + shift, 0),
              colors: [base, glow, base],
              stops: const [0.1, 0.45, 0.9],
            ),
          ),
        );
      },
    );
  }
}
