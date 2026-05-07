import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';

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
  });

  final String masterCardId;
  final String parallelName;
  final String initialGrade;
  final Color segmentColor;

  @override
  State<MarketAnalysisSection> createState() => _MarketAnalysisSectionState();
}

class _MarketAnalysisSectionState extends State<MarketAnalysisSection> {
  int _segment = 0;

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
        AdaptiveSegmentedControl(
          labels: const ['Sold Comps', 'For Sale'],
          selectedIndex: _segment,
          onValueChanged: (index) => setState(() => _segment = index),
          color: widget.segmentColor,
        ),
        const SizedBox(height: 16),
        if (_segment == 0)
          CardCompsSection(
            masterCardId: widget.masterCardId,
            parallelName: widget.parallelName,
            initialGrade: widget.initialGrade,
          )
        else
          CardActiveListingsSection(
            masterCardId: widget.masterCardId,
            parallelName: widget.parallelName,
          ),
      ],
    );
  }
}
