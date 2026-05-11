import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/models/comp.dart';
import '../../../core/utils/currency_format.dart';
import '../../../core/widgets/adaptive_list_card.dart';
import '../../../core/widgets/app_segmented_control.dart';
import '../../../core/widgets/inline_notice_container.dart';
import '../../../core/services/comps_service.dart';
import 'market_listing_row.dart';

class CardCompsSection extends ConsumerStatefulWidget {
  const CardCompsSection({
    super.key,
    required this.masterCardId,
    required this.parallelName,
    this.initialGrade = 'Raw',
    this.refreshVersion = 0,
    this.externalLoading = false,
  });

  final String masterCardId;
  final String parallelName;
  final String initialGrade;
  final int refreshVersion;
  final bool externalLoading;

  @override
  ConsumerState<CardCompsSection> createState() => _CardCompsSectionState();
}

class _CardCompsSectionState extends ConsumerState<CardCompsSection> {
  static const List<String> _loadingStatusSteps = [
    'Refreshing sold comps...',
    'Pulling recent sold listings...',
    'Matching sales to this card...',
    'Finalizing market averages...',
  ];

  late List<Comp> _allComps = [];
  late bool _loading = true;
  late String _selectedGrade = widget.initialGrade;
  late int _selectedDays = 0; // 0 = all, 7 = 7 days, 30 = 30 days
  bool _fetchInProgress = false;
  bool _autoRefreshAttempted = false;
  int _loadingStatusIndex = 0;
  Timer? _loadingStatusTimer;

  @override
  void initState() {
    super.initState();
    _fetchComps();
    _syncLoadingTicker();
  }

  @override
  void didUpdateWidget(CardCompsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.externalLoading != widget.externalLoading) {
      _syncLoadingTicker();
    }
    if (oldWidget.masterCardId != widget.masterCardId ||
        oldWidget.parallelName != widget.parallelName) {
      _selectedGrade = widget.initialGrade;
      _fetchComps();
      return;
    }
    if (oldWidget.refreshVersion != widget.refreshVersion) {
      _fetchComps();
    }
  }

  @override
  void dispose() {
    _loadingStatusTimer?.cancel();
    super.dispose();
  }

  bool get _isRefreshingUi => _loading || widget.externalLoading;

  String get _loadingStatusText {
    final idx = _loadingStatusIndex.clamp(0, _loadingStatusSteps.length - 1);
    return _loadingStatusSteps[idx];
  }

  void _syncLoadingTicker() {
    if (!_isRefreshingUi) {
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

  Future<void> _fetchComps() async {
    if (_fetchInProgress) return;
    _fetchInProgress = true;
    setState(() => _loading = true);
    _syncLoadingTicker();
    try {
      var comps = await ref.read(compsServiceProvider).getMasterCardComps(
            widget.masterCardId,
            widget.parallelName,
          );
      if (comps.isEmpty && !_autoRefreshAttempted && !widget.externalLoading) {
        _autoRefreshAttempted = true;
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
      _fetchInProgress = false;
      if (mounted) {
        setState(() => _loading = false);
        _syncLoadingTicker();
      }
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

  String _formatCompDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final compDay = DateTime(dt.year, dt.month, dt.day);

    if (compDay == today) return 'Today';
    if (compDay == yesterday) return 'Yesterday';
    return '${dt.month}/${dt.day}/${dt.year}';
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

    if (_isRefreshingUi && _allComps.isEmpty) {
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
            const _CompCardSkeletonWave(),
            const SizedBox(height: 8),
            const _CompCardSkeletonWave(),
            const SizedBox(height: 8),
            const _CompCardSkeletonWave(),
          ],
        ),
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
        if (_isRefreshingUi)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Center(
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
                ),
              ),
            ),
          ),
        // Date range filter
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              const Spacer(),
              SizedBox(
                width: 182,
                child: AppSegmentedControl(
                  preset: AppSegmentedControlPreset.compact,
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
              child: Builder(
                builder: (context) {
                  final comp = _filteredComps[i];
                  final chipBg = switch (comp.saleType) {
                    SaleType.auction => const Color(0xFF3B82F6).withValues(alpha: 0.15),
                    SaleType.bestOffer => const Color(0xFFF97316).withValues(alpha: 0.2),
                    _ => const Color(0xFF16A34A).withValues(alpha: 0.15),
                  };
                  final chipFg = switch (comp.saleType) {
                    SaleType.auction => const Color(0xFF2563EB),
                    SaleType.bestOffer => const Color(0xFFF97316),
                    _ => const Color(0xFF15803D),
                  };
                  final chipLabel = switch (comp.saleType) {
                    SaleType.auction => 'Auction',
                    SaleType.bestOffer => 'Best Offer',
                    _ => 'Buy It Now',
                  };
                  final subtitle = comp.soldAt != null ? _formatCompDate(comp.soldAt!) : '—';
                  return MarketListingRow(
                    title: comp.title,
                    price: comp.price,
                    chipLabel: chipLabel,
                    chipBackground: chipBg,
                    chipForeground: chipFg,
                    subtitle: subtitle,
                    imageUrl: comp.imageUrl,
                    url: comp.url,
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _CompCardSkeletonWave extends StatelessWidget {
  const _CompCardSkeletonWave();

  @override
  Widget build(BuildContext context) {
    return AdaptiveListCard(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _WaveSkeletonBox(
              width: 56,
              height: 56,
              radius: 10,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _WaveSkeletonBox(
                    height: 12,
                    width: double.infinity,
                    radius: 8,
                  ),
                  const SizedBox(height: 8),
                  const _WaveSkeletonBox(
                    height: 11,
                    width: 140,
                    radius: 8,
                  ),
                  const SizedBox(height: 8),
                  const _WaveSkeletonBox(
                    height: 20,
                    width: 88,
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
                      price != null ? formatUsd(price!) : 'N/A',
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
                return Text(formatUsd(value), style: axisLabelStyle);
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
                  formatUsd(spot.y),
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

