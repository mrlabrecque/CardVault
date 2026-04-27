import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/models/comp.dart';
import '../../../core/services/comps_service.dart';
import '../../../core/widgets/info_box.dart';

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
      print('[CardCompsSection] Initial fetch: ${comps.length} comps for ${widget.masterCardId} / ${widget.parallelName}');
      if (comps.isEmpty) {
        print('[CardCompsSection] No comps found, refreshing...');
        await ref.read(compsServiceProvider).refreshMasterCardComps(
              widget.masterCardId,
              widget.parallelName,
            );
        comps = await ref.read(compsServiceProvider).getMasterCardComps(
              widget.masterCardId,
              widget.parallelName,
            );
        print('[CardCompsSection] After refresh: ${comps.length} comps');
      }
      print('[CardCompsSection] About to setState with ${comps.length} comps, mounted=$mounted');
      if (mounted) {
        setState(() {
          _allComps = comps;
          final grades = _allComps.map((c) => c.grade).toSet();
          print('[CardCompsSection] setState complete, _allComps.length=${_allComps.length}, grades=$grades, selectedGrade=$_selectedGrade');
          final filtered = _allComps.where((c) => c.grade == _selectedGrade).length;
          print('[CardCompsSection] Filtered by $_selectedGrade: $filtered comps');
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load comps: $e'), backgroundColor: Colors.red),
        );
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
    final comps = _allComps.where((c) => (c.grade ?? 'Raw') == grade).toList();
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
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_allComps.isEmpty) {
      return InfoBox(
        color: const Color(0xFFF59E0B),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No comps found',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'No recent eBay sales data available for this card.',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Date range filter
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: colors.outline.withValues(alpha: 0.3), width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    _DateRangeButton(
                      label: '7d',
                      isSelected: _selectedDays == 7,
                      onTap: () => setState(() => _selectedDays = 7),
                      isFirst: true,
                    ),
                    Container(
                      width: 1,
                      height: 32,
                      color: colors.outline.withValues(alpha: 0.2),
                    ),
                    _DateRangeButton(
                      label: '30d',
                      isSelected: _selectedDays == 30,
                      onTap: () => setState(() => _selectedDays = 30),
                    ),
                    Container(
                      width: 1,
                      height: 32,
                      color: colors.outline.withValues(alpha: 0.2),
                    ),
                    _DateRangeButton(
                      label: 'All',
                      isSelected: _selectedDays == 0,
                      onTap: () => setState(() => _selectedDays = 0),
                      isLast: true,
                    ),
                  ],
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
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF3F4F6)),
              ),
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                height: 120,
                child: _PriceChart(data: _getChartData()),
              ),
            ),
          ),
        ],

        // Filtered comps list
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${_filteredComps.length} ${_filteredComps.length == 1 ? 'listing' : 'listings'}',
              style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.5)),
            ),
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _filteredComps.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF3F4F6)),
            ),
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
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF800020) : Colors.white,
            border: Border.all(
              color: isSelected ? const Color(0xFF800020) : colors.outline.withValues(alpha: 0.3),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : colors.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                price != null ? '\$${price!.toStringAsFixed(2)}' : '—',
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected ? Colors.white70 : colors.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Date range button ──────────────────────────────────────────────────────

class _DateRangeButton extends StatelessWidget {
  const _DateRangeButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.isFirst = false,
    this.isLast = false,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF800020) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(isFirst ? 7 : 0),
            bottomLeft: Radius.circular(isFirst ? 7 : 0),
            topRight: Radius.circular(isLast ? 7 : 0),
            bottomRight: Radius.circular(isLast ? 7 : 0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : colors.onSurface,
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
                return Text('\$${value.toStringAsFixed(0)}', style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w500));
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
                  child: Text('$month/$day', style: const TextStyle(fontSize: 9, color: Color(0xFF9CA3AF))),
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
                  const TextStyle(color: Color(0xFF1F2937), fontWeight: FontWeight.w600, fontSize: 12),
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

    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(

          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left: title + date
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comp.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    comp.soldAt != null ? _formatDate(comp.soldAt!) : '—',
                    style: TextStyle(fontSize: 11, color: colors.onSurface.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Right: price + badge + link icon
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${comp.price.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (comp.saleType == SaleType.auction)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Auction', style: TextStyle(fontSize: 10, color: Color(0xFF3B82F6))),
                      )
                    else if (comp.saleType == SaleType.bestOffer)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF97316).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Best Offer', style: TextStyle(fontSize: 10, color: Color(0xFFF97316))),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.outline.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Buy It Now', style: TextStyle(fontSize: 10)),
                      ),
                    const SizedBox(width: 6),
                    if (comp.url != null)
                      Icon(Icons.open_in_new, size: 12, color: colors.onSurface.withValues(alpha: 0.5)),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
  }
}
