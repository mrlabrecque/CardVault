import 'package:flutter/material.dart';

import '../../../core/utils/currency_format.dart';
import '../../../core/widgets/adaptive_list_card.dart';
import '../../../core/widgets/inline_notice_container.dart';
import '../../../core/widgets/app_segmented_control.dart';
import 'card_active_listings_section.dart';
import 'card_comps_section.dart';

/// Segmented "Sold Comps" vs "For Sale" market block for item detail.
class MarketAnalysisSection extends StatefulWidget {
  const MarketAnalysisSection({
    super.key,
    required this.masterCardId,
    required this.parallelName,
    required this.initialGrade,
    required this.segmentColor,
    this.refreshVersion = 0,
    this.externalLoading = false,
    this.cardHedgeGradeAverages,
    this.soldCompsSourceLabel,
    this.skipScraperSoldComps = false,
  });

  final String masterCardId;
  final String parallelName;
  final String initialGrade;
  final Color segmentColor;
  final int refreshVersion;
  final bool externalLoading;
  /// Keys [Raw], [PSA 10], [PSA 9]; null values render as N/A (same as scraper comps).
  final Map<String, double?>? cardHedgeGradeAverages;
  final String? soldCompsSourceLabel;
  final bool skipScraperSoldComps;

  @override
  State<MarketAnalysisSection> createState() => _MarketAnalysisSectionState();
}

class _MarketAnalysisSectionState extends State<MarketAnalysisSection> {
  int _segment = 0;

  bool get _useCardHedgeSoldComps {
    if (widget.skipScraperSoldComps) return true;
    final avgs = widget.cardHedgeGradeAverages;
    if (avgs == null) return false;
    return avgs.values.any((v) => v != null && v > 0);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Market Analysis',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
          ),
        ),
        const SizedBox(height: 16),
        AppSegmentedControl(
          labels: const ['Sold Comps', 'For Sale'],
          selectedIndex: _segment,
          onValueChanged: (index) => setState(() => _segment = index),
          color: widget.segmentColor,
        ),
        const SizedBox(height: 16),
        if (_segment == 0)
          (_useCardHedgeSoldComps
              ? _CardHedgeCompsSummary(
                  gradeAverages:
                      widget.cardHedgeGradeAverages ?? const <String, double?>{},
                  sourceLabel: widget.soldCompsSourceLabel ?? 'CardHedge',
                  skipScraperSoldComps: widget.skipScraperSoldComps,
                )
              : CardCompsSection(
                  masterCardId: widget.masterCardId,
                  parallelName: widget.parallelName,
                  initialGrade: widget.initialGrade,
                  refreshVersion: widget.refreshVersion,
                  externalLoading: widget.externalLoading,
                ))
        else
          CardActiveListingsSection(
            masterCardId: widget.masterCardId,
            parallelName: widget.parallelName,
          ),
      ],
    );
  }
}

class _CardHedgeCompsSummary extends StatelessWidget {
  const _CardHedgeCompsSummary({
    required this.gradeAverages,
    required this.sourceLabel,
    required this.skipScraperSoldComps,
  });

  final Map<String, double?> gradeAverages;
  final String sourceLabel;
  final bool skipScraperSoldComps;

  double? _price(String key) => gradeAverages[key];

  bool get _anyPrice =>
      gradeAverages.values.any((v) => v != null && v > 0);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InlineNoticeContainer(
          icon: Icon(Icons.auto_graph, size: 20, color: colors.primary),
          highlightBorderColor: colors.primary.withValues(alpha: 0.35),
          child: Text(
            'Using $sourceLabel grade averages (scraper skipped).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (skipScraperSoldComps && !_anyPrice) ...[
          const SizedBox(height: 10),
          InlineNoticeContainer(
            icon: Icon(Icons.info_outline, size: 20, color: colors.onSurface.withValues(alpha: 0.60)),
            child: Text(
              'No CardHedge grade prices were returned.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.75),
                  ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              _CardHedgeGradePill(label: 'Raw', price: _price('Raw')),
              const SizedBox(width: 8),
              _CardHedgeGradePill(label: 'PSA 10', price: _price('PSA 10')),
              const SizedBox(width: 8),
              _CardHedgeGradePill(label: 'PSA 9', price: _price('PSA 9')),
            ],
          ),
        ),
      ],
    );
  }
}

/// Same layout as sold-comps grade pills in [CardCompsSection] (read-only).
class _CardHedgeGradePill extends StatelessWidget {
  const _CardHedgeGradePill({
    required this.label,
    required this.price,
  });

  final String label;
  final double? price;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final p = price;

    return Expanded(
      child: AdaptiveListCard(
        margin: EdgeInsets.zero,
        cornerRadius: 10,
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    p != null && p > 0 ? formatUsd(p) : 'N/A',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onSurface.withValues(alpha: 0.62),
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
