import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/comp.dart';
import '../../../core/services/comps_service.dart';
import '../../../core/utils/adaptive_ui.dart';
import '../../../core/ui/price_guide_copy.dart';
import '../../../core/utils/guide_grade_prices.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/widgets/card_fan_loader.dart';
import '../../../core/widgets/modal_sheet_scaffold.dart';
import 'market_listings_list.dart'
    show MarketListingRow, MarketListingsList, MarketSectionNotice, formatMarketListingMetaDate;

/// Active eBay listings for a catalog variant (`master_card_definitions.id`).
///
/// Deal math uses [guideRecentPrices] only: each listing title is scanned for
/// Raw vs slab, then the matching guide row is used (graded rows never fall back
/// to Raw for the deal icon).
class CardActiveListingsSection extends ConsumerStatefulWidget {
  const CardActiveListingsSection({
    super.key,
    required this.masterCardId,
    this.guideRecentPrices,
  });

  final String masterCardId;
  final Map<String, double?>? guideRecentPrices;

  @override
  ConsumerState<CardActiveListingsSection> createState() => _CardActiveListingsSectionState();
}

class _CardActiveListingsSectionState extends ConsumerState<CardActiveListingsSection> {
  List<ActiveListing>? _items;
  bool _loading = true;
  String? _error;
  /// When empty, all listings are shown. Otherwise any tier in the set matches (OR).
  final Set<ActiveListingGuideDealTier> _selectedDealTiers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CardActiveListingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.masterCardId != widget.masterCardId) {
      _selectedDealTiers.clear();
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

  bool get _hasGuidePrices => guideGradeMapHasAnyPrice(widget.guideRecentPrices ?? {});

  ({Color fg, Color bg}) _dealTierColors(ActiveListingGuideDealTier tier, ColorScheme colors) {
    switch (tier) {
      case ActiveListingGuideDealTier.badDeal:
        return (
          fg: const Color(0xFFB91C1C),
          bg: const Color(0xFFFEE2E2),
        );
      case ActiveListingGuideDealTier.okDeal:
        return (
          fg: const Color(0xFFC2410C),
          bg: const Color(0xFFFFEDD5),
        );
      case ActiveListingGuideDealTier.fairDeal:
        return (
          fg: colors.onSurface.withValues(alpha: 0.62),
          bg: colors.onSurface.withValues(alpha: 0.08),
        );
      case ActiveListingGuideDealTier.goodDeal:
        return (
          fg: const Color(0xFF15803D),
          bg: const Color(0xFFDCFCE7),
        );
      case ActiveListingGuideDealTier.greatDeal:
        return (
          fg: const Color(0xFF14532D),
          bg: const Color(0xFFBBF7D0),
        );
    }
  }

  static const List<ActiveListingGuideDealTier> _dealFilterTiers = [
    ActiveListingGuideDealTier.greatDeal,
    ActiveListingGuideDealTier.goodDeal,
    ActiveListingGuideDealTier.fairDeal,
    ActiveListingGuideDealTier.okDeal,
    ActiveListingGuideDealTier.badDeal,
  ];

  String _dealTierMenuTitle(ActiveListingGuideDealTier tier) {
    return switch (tier) {
      ActiveListingGuideDealTier.greatDeal => 'Great Deal',
      ActiveListingGuideDealTier.goodDeal => 'Good Deal',
      ActiveListingGuideDealTier.fairDeal => 'Fair Deal',
      ActiveListingGuideDealTier.okDeal => 'Ok Deal',
      ActiveListingGuideDealTier.badDeal => 'Bad Deal',
    };
  }

  Future<void> _showDealFilterSheet() async {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final initial = Set<ActiveListingGuideDealTier>.from(_selectedDealTiers);

    final result = await showAdaptiveSheet<Set<ActiveListingGuideDealTier>>(
      context: context,
      builder: (sheetContext) {
        final draft = Set<ActiveListingGuideDealTier>.from(initial);
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return ModalSheetScaffold(
              title: PriceGuideCopy.dealsVsPriceGuideTitle,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Show listings that match any selected deal. Uses each title’s Raw vs slab and the matching Recent Prices row. Leave all unchecked to show every listing.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.65),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._dealFilterTiers.map((tier) {
                    final pair = _dealTierColors(tier, colors);
                    final checked = draft.contains(tier);
                    void toggle() {
                      setModal(() {
                        if (draft.contains(tier)) {
                          draft.remove(tier);
                        } else {
                          draft.add(tier);
                        }
                      });
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            dealTierCupertinoIcon(tier),
                            size: 22,
                            color: pair.fg,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: toggle,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Text(
                                  _dealTierMenuTitle(tier),
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          AdaptiveCheckbox(
                            value: checked,
                            onChanged: (_) => toggle(),
                            activeColor: colors.primary,
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      AdaptiveButton(
                        onPressed: () => setModal(() => draft.clear()),
                        label: 'Clear all',
                        style: AdaptiveButtonStyle.plain,
                        color: colors.primary,
                        size: AdaptiveButtonSize.small,
                        useNative: false,
                      ),
                      const Spacer(),
                      AdaptiveButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        label: 'Cancel',
                        style: AdaptiveButtonStyle.plain,
                        color: colors.primary,
                        size: AdaptiveButtonSize.small,
                        useNative: false,
                      ),
                      const SizedBox(width: 8),
                      AdaptiveButton(
                        onPressed: () =>
                            Navigator.pop(sheetContext, Set<ActiveListingGuideDealTier>.from(draft)),
                        label: 'Apply',
                        style: AdaptiveButtonStyle.filled,
                        color: colors.primary,
                        textColor: Colors.white,
                        size: AdaptiveButtonSize.small,
                        useNative: false,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;
    setState(() {
      _selectedDealTiers
        ..clear()
        ..addAll(result);
    });
  }

  ActiveListingGuideDealTier? _tierForListing(ActiveListing listing) {
    final map = widget.guideRecentPrices;
    if (map == null || !guideGradeMapHasAnyPrice(map)) return null;
    final inferred = inferListingConditionFromTitle(listing.title);
    final guide = guidePriceForInferredListing(gradeToPrice: map, inferred: inferred);
    if (guide == null || guide <= 0) return null;
    return computeActiveListingGuideDeal(
      listingPrice: listing.price,
      guidePrice: guide,
    )?.tier;
  }

  List<ActiveListing> _filteredListings(List<ActiveListing> items) {
    if (!_hasGuidePrices || _selectedDealTiers.isEmpty) return items;
    return items
        .where((l) {
          final t = _tierForListing(l);
          return t != null && _selectedDealTiers.contains(t);
        })
        .toList();
  }

  ({InferredListingCondition inferred, ActiveListingVsGuideDelta? delta}) _vsGuideForListing(
    ActiveListing listing,
  ) {
    final map = widget.guideRecentPrices;
    final inferred = inferListingConditionFromTitle(listing.title);
    if (map == null || !guideGradeMapHasAnyPrice(map)) {
      return (inferred: inferred, delta: null);
    }
    final guide = guidePriceForInferredListing(gradeToPrice: map, inferred: inferred);
    if (guide == null || guide <= 0) {
      return (inferred: inferred, delta: null);
    }
    final delta = computeActiveListingGuideDeal(
      listingPrice: listing.price,
      guidePrice: guide,
    );
    return (inferred: inferred, delta: delta);
  }

  MarketListingRow _activeListingRow(ActiveListing listing, ColorScheme colors) {
    final (chipBg, chipFg, chipLabel) = switch (listing.listingType) {
      'AUCTION' => (
          const Color(0xFF3B82F6).withValues(alpha: 0.15),
          const Color(0xFF2563EB),
          'Auction',
        ),
      'BEST_OFFER' => (
          const Color(0xFFF97316).withValues(alpha: 0.2),
          const Color(0xFFF97316),
          'Best Offer',
        ),
      _ => (
          const Color(0xFF16A34A).withValues(alpha: 0.15),
          const Color(0xFF15803D),
          'Buy It Now',
        ),
    };

    final vs = _vsGuideForListing(listing);
    final delta = vs.delta;
    final vsPair = delta != null ? _dealTierColors(delta.tier, colors) : null;

    final ends = listing.endsAt;
    final metaLine = ends != null
        ? 'Listing ends: ${formatMarketListingMetaDate(ends)}'
        : null;

    return MarketListingRow(
      title: listing.title,
      price: listing.price,
      chipLabel: chipLabel,
      chipBackground: chipBg,
      chipForeground: chipFg,
      imageUrl: listing.imageUrl,
      url: listing.url,
      metaLine: metaLine,
      gradeTag: vs.inferred.displayTag,
      vsGuideDealTier: delta?.tier,
      vsGuideLabel: delta?.label,
      vsGuideForeground: vsPair?.fg,
      vsGuideCompareGrade: delta != null ? vs.inferred.displayTag : null,
      vsGuidePriceMissing: _hasGuidePrices && delta == null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 24),
        child: Center(child: CardFanLoader(size: 72)),
      );
    }

    if (_error != null) {
      return MarketSectionNotice(
        icon: isIOS ? CupertinoIcons.exclamationmark_circle : Icons.error_outline,
        title: 'Could not load listings',
        message: _error!,
        highlightBorderColor: colors.error.withValues(alpha: 0.35),
      );
    }

    final items = _items ?? [];
    if (items.isEmpty) {
      return MarketSectionNotice(
        icon: isIOS ? CupertinoIcons.tag : Icons.storefront_outlined,
        title: 'No active listings',
        message:
            'No matching Buy It Now or auction listings were found for this card right now.',
        highlightBorderColor: colors.outline.withValues(alpha: 0.28),
      );
    }

    final displayItems = _filteredListings(items);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_hasGuidePrices)
          Padding(
            padding: const EdgeInsets.only(bottom: 0),
            child: Text(
              'Deal icons compare each ask to the Recent Prices row that matches Raw vs slab detected in the title (no icon if that grade is missing).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.58),
                    height: 1.3,
                  ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 0),
            child: Text(
              PriceGuideCopy.forSaleNeedsPriceGuide,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.50),
                    height: 1.3,
                  ),
            ),
          ),
        if (displayItems.isEmpty && items.isNotEmpty && _hasGuidePrices)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: MarketSectionNotice(
              icon: isIOS
                  ? CupertinoIcons.line_horizontal_3_decrease_circle
                  : Icons.filter_list_outlined,
              title: 'No listings match this filter',
              message: 'Try clearing the deal filter or selecting different deal tiers.',
              highlightBorderColor: colors.outline.withValues(alpha: 0.28),
            ),
          ),
        MarketListingsList(
          countLabel: _selectedDealTiers.isNotEmpty && _hasGuidePrices
              ? '${displayItems.length} of ${items.length} listing${items.length == 1 ? '' : 's'}'
              : '${items.length} listing${items.length == 1 ? '' : 's'}',
          countPadding: EdgeInsets.zero,
          headerTrailing: _hasGuidePrices
              ? IconButton(
                  tooltip: 'Filter by deal',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  onPressed: _showDealFilterSheet,
                  icon: Icon(
                    _selectedDealTiers.isNotEmpty
                        ? CupertinoIcons.line_horizontal_3_decrease_circle_fill
                        : CupertinoIcons.line_horizontal_3_decrease_circle,
                    size: 24,
                    color: _selectedDealTiers.isNotEmpty
                        ? colors.primary
                        : colors.onSurface.withValues(alpha: 0.72),
                  ),
                )
              : null,
          rows: [
            for (final listing in displayItems) _activeListingRow(listing, colors),
          ],
        ),
      ],
    );
  }
}
