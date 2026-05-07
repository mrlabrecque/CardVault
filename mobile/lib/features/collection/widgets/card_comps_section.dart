import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/models/comp.dart';
import '../../../core/widgets/adaptive_list_card.dart';
import '../../../core/widgets/card_fan_loader.dart';
import '../../../core/widgets/inline_notice_container.dart';
import '../../../core/services/comps_service.dart';

class CardCompsSection extends ConsumerStatefulWidget {
  const CardCompsSection({
    super.key,
    required this.masterCardId,
    required this.parallelName,
    this.initialGrade = 'Raw',
  });

  final String masterCardId;
  final String parallelName;
  final String initialGrade;

  @override
  ConsumerState<CardCompsSection> createState() => _CardCompsSectionState();
}

class _CardCompsSectionState extends ConsumerState<CardCompsSection> {
  late List<Comp> _allComps = [];
  late bool _loading = true;
  late String _selectedGrade = widget.initialGrade;
  late int _selectedDays = 0; // 0 = all, 7 = 7 days, 30 = 30 days

  @override
  void initState() {
    super.initState();
    _fetchComps();
  }

  @override
  void didUpdateWidget(CardCompsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.masterCardId != widget.masterCardId ||
        oldWidget.parallelName != widget.parallelName) {
      _selectedGrade = widget.initialGrade;
      _fetchComps();
    }
  }

  Future<void> _fetchComps() async {
    setState(() => _loading = true);
    try {
      var comps = await ref.read(compsServiceProvider).getMasterCardComps(
            widget.masterCardId,
            widget.parallelName,
          );
      if (comps.isEmpty) {
        await ref.read(compsServiceProvider).refreshMasterCardComps(
              widget.masterCardId,
              widget.parallelName,
            );
        comps = await ref.read(compsServiceProvider).getMasterCardComps(
              widget.masterCardId,
              widget.parallelName,
            );
      }
      if (mounted) {
        setState(() {
          _allComps = comps;
        });
      }
    } catch (e) {
      if (mounted) {
        AdaptiveSnackBar.show(context, message: 'Failed to load comps: $e', type: AdaptiveSnackBarType.error);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isWithinDateRange(DateTime? soldAt) {
    if (_selectedDays == 0) return true; // 'All' selected
    if (soldAt == null) return false;
    final cutoff = DateTime.now().subtract(Duration(days: _selectedDays));
    return soldAt.isAfter(cutoff);
  }

  List<Comp> get _filteredComps {
    final normalizedGrade = _selectedGrade;
    return _allComps.where((c) {
      final compGrade = c.grade ?? 'Raw'; // Default null grades to 'Raw'
      return compGrade == normalizedGrade && _isWithinDateRange(c.soldAt);
    }).toList();
  }

  double? _getGradeAverage(String grade) {
    final comps = _allComps
        .where((c) => (c.grade ?? 'Raw') == grade && _isWithinDateRange(c.soldAt))
        .toList();
    if (comps.isEmpty) return null;
    final total = comps.fold<double>(0, (s, c) => s + c.price);
    return total / comps.length;
  }

  Map<DateTime, double> _getChartData() {
    final filtered = _filteredComps;
    if (filtered.isEmpty) return {};

    final grouped = <DateTime, List<double>>{};
    for (final comp in filtered) {
      if (comp.soldAt != null) {
        final day = DateTime(comp.soldAt!.year, comp.soldAt!.month, comp.soldAt!.day);
        grouped.putIfAbsent(day, () => []).add(comp.price);
      }
    }

    final result = <DateTime, double>{};
    for (final entry in grouped.entries) {
      final avg = entry.value.fold<double>(0, (s, p) => s + p) / entry.value.length;
      result[entry.key] = avg;
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Center(child: CardFanLoader()),
      );
    }

    if (_allComps.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDBB726)),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_off, size: 20, color: Color(0xFFF59E0B)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No comps found',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFB45309),
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No recent eBay sales data available for this card.',
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
        // Date range filter
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              const Spacer(),
              SizedBox(
                width: 182,
                child: AdaptiveSegmentedControl(
                  labels: const ['7d', '30d', 'All'],
                  selectedIndex: switch (_selectedDays) {
                    7 => 0,
                    30 => 1,
                    _ => 2,
                  },
                  onValueChanged: (index) {
                    setState(() {
                      _selectedDays = switch (index) {
                        0 => 7,
                        1 => 30,
                        _ => 0,
                      };
                    });
                  },
                  color: colors.primary,
                ),
              ),
            ],
          ),
        ),

        // Grade pills
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              _GradePill(
                label: 'Raw',
                price: _getGradeAverage('Raw'),
                isSelected: _selectedGrade == 'Raw',
                onTap: () => setState(() => _selectedGrade = 'Raw'),
              ),
              const SizedBox(width: 8),
              _GradePill(
                label: 'PSA 10',
                price: _getGradeAverage('PSA 10'),
                isSelected: _selectedGrade == 'PSA 10',
                onTap: () => setState(() => _selectedGrade = 'PSA 10'),
              ),
              const SizedBox(width: 8),
              _GradePill(
                label: 'PSA 9',
                price: _getGradeAverage('PSA 9'),
                isSelected: _selectedGrade == 'PSA 9',
                onTap: () => setState(() => _selectedGrade = 'PSA 9'),
              ),
            ],
          ),
        ),

        // Chart (if enough data)
        if (_getChartData().length >= 2) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
            child: AdaptiveListCard(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 20, 8),
                child: SizedBox(
                  height: 120,
                  child: _PriceChart(data: _getChartData()),
                ),
              ),
            ),
          ),
        ],

        // Filtered comps list
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${_filteredComps.length} ${_filteredComps.length == 1 ? 'listing' : 'listings'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.60),
                  ),
            ),
          ),
        ),
        if (_filteredComps.isEmpty)
          InlineNoticeContainer(
            icon: Icon(Icons.info_outline, size: 20, color: colors.onSurface.withValues(alpha: 0.60)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No recent sales',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                ),
                Text(
                  'No recent eBay sales found at $_selectedGrade grade.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.60),
                      ),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _filteredComps.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => AdaptiveListCard(
              margin: EdgeInsets.zero,
              child: _CompRow(comp: _filteredComps[i]),
            ),
          ),
      ],
    );
  }
}

// ── Grade pill ─────────────────────────────────────────────────────────────

class _GradePill extends StatelessWidget {
  const _GradePill({
    required this.label,
    required this.price,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final double? price;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Expanded(
      child: AdaptiveListCard(
        margin: EdgeInsets.zero,
        cornerRadius: 10,
        highlightBorderColor: isSelected ? colors.primary : null,
        child: Material(
          color: isSelected
              ? Color.alphaBlend(
                  colors.primary.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.10),
                  colors.surface,
                )
              : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
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
                            color: isSelected ? colors.primary : colors.onSurface,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      price != null ? '\$${price!.toStringAsFixed(2)}' : 'N/A',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: isSelected
                                ? colors.primary.withValues(alpha: 0.88)
                                : colors.onSurface.withValues(alpha: 0.62),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Price chart ────────────────────────────────────────────────────────────

class _PriceChart extends StatelessWidget {
  const _PriceChart({required this.data});

  final Map<DateTime, double> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final base = theme.textTheme.labelSmall ?? const TextStyle(fontSize: 12);
    final axisLabelStyle = base.copyWith(
      color: colors.onSurface.withValues(alpha: 0.55),
      fontWeight: FontWeight.w500,
      fontSize: 11,
    );

    final sortedDates = data.keys.toList()..sort();
    final minPrice = data.values.reduce((a, b) => a < b ? a : b);
    final maxPrice = data.values.reduce((a, b) => a > b ? a : b);
    final priceRange = maxPrice - minPrice;

    final spots = <FlSpot>[];
    for (int i = 0; i < sortedDates.length; i++) {
      final price = data[sortedDates[i]]!;
      // Round to 2 decimal places
      final roundedPrice = double.parse(price.toStringAsFixed(2));
      spots.add(FlSpot(i.toDouble(), roundedPrice));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawHorizontalLine: true,
          drawVerticalLine: false,
          horizontalInterval: (maxPrice - minPrice) / 4,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: const Color(0xFFF3F4F6),
              strokeWidth: 1,
              dashArray: [4, 2],
            );
          },
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                return Text('\$${value.toStringAsFixed(0)}', style: axisLabelStyle);
              },
              reservedSize: 40,
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= sortedDates.length) return const SizedBox.shrink();
                final date = sortedDates[index];
                final month = date.month.toString().padLeft(2, '0');
                final day = date.day.toString().padLeft(2, '0');
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '$month/$day',
                    style: axisLabelStyle,
                  ),
                );
              },
              reservedSize: 30,
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(
          show: true,
          border: const Border(
            left: BorderSide(color: Color(0xFFF3F4F6), width: 1),
            bottom: BorderSide(color: Color(0xFFF3F4F6), width: 1),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (touchedSpot) => Colors.white,
            tooltipBorder: const BorderSide(color: Color(0xFFF3F4F6)),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                return LineTooltipItem(
                  '\$${spot.y.toStringAsFixed(2)}',
                  TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: theme.textTheme.bodySmall?.fontSize ?? 12,
                  ),
                );
              }).toList();
            },
          ),
        ),
        minY: minPrice - priceRange * 0.1,
        maxY: maxPrice + priceRange * 0.1,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: const Color(0xFF800020),
            barWidth: 2.5,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 4,
                  color: const Color(0xFF800020),
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0xFF800020).withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Comp row ───────────────────────────────────────────────────────────────

class _CompRow extends StatelessWidget {
  const _CompRow({required this.comp});

  final Comp comp;

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final compDay = DateTime(dt.year, dt.month, dt.day);

    if (compDay == today) return 'Today';
    if (compDay == yesterday) return 'Yesterday';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final hasUrl = comp.url != null && comp.url!.isNotEmpty;

    void openUrl() {
      if (!hasUrl) return;
      launchUrl(Uri.parse(comp.url!), mode: LaunchMode.externalApplication);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comp.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text(
                  comp.soldAt != null ? _formatDate(comp.soldAt!) : '—',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.60),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${comp.price.toStringAsFixed(2)}',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (comp.saleType == SaleType.auction)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Auction',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF3B82F6),
                        ),
                      ),
                    )
                  else if (comp.saleType == SaleType.bestOffer)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF97316).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Best Offer',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFF97316),
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.outline.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Buy It Now',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                  if (hasUrl) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: openUrl,
                      icon: Icon(Icons.open_in_new, size: 18, color: colors.onSurface.withValues(alpha: 0.60)),
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(44, 44),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
    );
  }
}
