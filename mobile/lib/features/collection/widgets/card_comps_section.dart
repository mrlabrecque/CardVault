import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/models/comp.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/comps_outlier_utils.dart';
import '../../../core/utils/currency_format.dart';
import '../../../core/widgets/adaptive_list_card.dart';
import '../../../core/widgets/card_fan_loader.dart';
import '../../../core/widgets/inline_notice_container.dart';
import '../../../core/services/comps_service.dart';
import 'comps_market_filters.dart';
import 'market_listings_list.dart' show MarketListingRow, MarketListingsList, formatMarketListingMetaDate;

class CardCompsSection extends ConsumerStatefulWidget {
  const CardCompsSection({
    super.key,
    required this.masterCardId,
    this.initialGrade = 'Raw',
    this.refreshVersion = 0,
    this.externalLoading = false,
    /// When true (embedded guide sold-comps): no duplicate grade pills, no scraper loading
    /// copy, no auto Bright Data refresh when the table is empty.
    this.embeddedGuideSoldComps = false,
    /// When set with [onSelectedDaysChanged], the date filter is rendered by the parent.
    this.selectedDays,
    this.onSelectedDaysChanged,
    this.suppressFilterChrome = false,
  });

  final String masterCardId;
  final String initialGrade;
  final int refreshVersion;
  final bool externalLoading;
  final bool embeddedGuideSoldComps;
  final int? selectedDays;
  final ValueChanged<int>? onSelectedDaysChanged;
  /// Hides the date-range row (e.g. catalog detail after load).
  final bool suppressFilterChrome;

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
  /// When [refreshVersion] bumps while a fetch is in flight (e.g. upstream edge
  /// finishes after the first empty read), the follow-up [_fetchComps] must not
  /// be dropped — otherwise the UI stays empty forever.
  bool _compsFetchQueued = false;
  bool _autoRefreshAttempted = false;
  int _loadingStatusIndex = 0;
  Timer? _loadingStatusTimer;

  @override
  void initState() {
    super.initState();
    // Parent [MarketAnalysisSection] already fetched guide comps; read DB quietly.
    _loading = !widget.embeddedGuideSoldComps;
    _fetchComps(silent: widget.embeddedGuideSoldComps);
    _syncLoadingTicker();
  }

  @override
  void didUpdateWidget(CardCompsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialGrade != widget.initialGrade) {
      _selectedGrade = widget.initialGrade;
    }
    if (oldWidget.externalLoading != widget.externalLoading) {
      _syncLoadingTicker();
    }
    if (oldWidget.masterCardId != widget.masterCardId) {
      _selectedGrade = widget.initialGrade;
      _fetchComps();
      return;
    }
    if (oldWidget.refreshVersion != widget.refreshVersion) {
      _fetchComps(
        silent: widget.embeddedGuideSoldComps && _allComps.isNotEmpty,
      );
    }
  }

  @override
  void dispose() {
    _loadingStatusTimer?.cancel();
    super.dispose();
  }

  bool get _isRefreshingUi => _loading || widget.externalLoading;

  bool get _dateFilterRenderedByParent => widget.onSelectedDaysChanged != null;

  int get _effectiveSelectedDays => widget.selectedDays ?? _selectedDays;

  void _setSelectedDays(int days) {
    if (widget.onSelectedDaysChanged != null) {
      widget.onSelectedDaysChanged!(days);
    } else {
      setState(() => _selectedDays = days);
    }
  }

  String get _loadingStatusText {
    final idx = _loadingStatusIndex.clamp(0, _loadingStatusSteps.length - 1);
    return _loadingStatusSteps[idx];
  }

  void _syncLoadingTicker() {
    if (widget.embeddedGuideSoldComps || !_isRefreshingUi) {
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

  Future<void> _fetchComps({bool silent = false}) async {
    if (_fetchInProgress) {
      _compsFetchQueued = true;
      return;
    }
    _fetchInProgress = true;
    if (!silent) {
      setState(() => _loading = true);
      _syncLoadingTicker();
    }
    try {
      var comps = await ref.read(compsServiceProvider).getMasterCardComps(
            widget.masterCardId,
          );
      if (comps.isEmpty &&
          !_autoRefreshAttempted &&
          !widget.externalLoading &&
          !widget.embeddedGuideSoldComps) {
        _autoRefreshAttempted = true;
        await ref.read(compsServiceProvider).refreshMasterCardComps(
              widget.masterCardId,
            );
        comps = await ref.read(compsServiceProvider).getMasterCardComps(
              widget.masterCardId,
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
      final runAgain = _compsFetchQueued;
      _compsFetchQueued = false;
      if (mounted) {
        setState(() => _loading = false);
        _syncLoadingTicker();
        if (runAgain) {
          unawaited(_fetchComps(silent: widget.embeddedGuideSoldComps && _allComps.isNotEmpty));
        }
      }
    }
  }

  bool _isWithinDateRange(DateTime? soldAt) {
    if (_effectiveSelectedDays == 0) return true; // 'All' selected
    if (soldAt == null) return false;
    final cutoff = DateTime.now().subtract(Duration(days: _effectiveSelectedDays));
    return soldAt.isAfter(cutoff);
  }

  List<Comp> get _filteredComps {
    final normalizedGrade = _selectedGrade;
    return _allComps.where((c) {
      final compGrade = c.grade ?? 'Raw'; // Default null grades to 'Raw'
      return compGrade == normalizedGrade && _isWithinDateRange(c.soldAt);
    }).toList();
  }

  CompsOutlierStats get _outlierStats => CompsOutlierStats.fromComps(_filteredComps);

  List<Comp> get _compsForStats => CompsOutlierStats.includedComps(_filteredComps);

  double? _getGradeAverage(String grade) {
    final comps = _allComps
        .where((c) => (c.grade ?? 'Raw') == grade && _isWithinDateRange(c.soldAt))
        .toList();
    return CompsOutlierStats.averagePrice(comps);
  }

  /// One chart point per included sold listing (chronological); outliers omitted.
  List<_CompChartPoint> _getChartPoints() {
    final withDates = _compsForStats.where((c) => c.soldAt != null).toList()
      ..sort((a, b) => a.soldAt!.compareTo(b.soldAt!));
    return [
      for (final c in withDates)
        _CompChartPoint(soldAt: c.soldAt!, price: c.price),
    ];
  }

  /// Mean sold price for listings included in chart/stats (outliers excluded).
  double? _listingsAverageInFilter() => CompsOutlierStats.averagePrice(_filteredComps);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (widget.embeddedGuideSoldComps && _loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 24),
        child: Center(child: CardFanLoader(size: 72)),
      );
    }

    if (_isRefreshingUi && _allComps.isEmpty) {
      if (widget.embeddedGuideSoldComps) {
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 24),
          child: Center(child: CardFanLoader(size: 72)),
        );
      }
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
      if (widget.embeddedGuideSoldComps) {
        if (_fetchInProgress) {
          return const SizedBox.shrink();
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.outline.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 20, color: colors.onSurface.withValues(alpha: 0.55)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No guide sales returned for $_selectedGrade.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.72),
                        height: 1.35,
                      ),
                ),
              ),
            ],
          ),
        );
      }
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

    final chartPoints = _getChartPoints();
    final periodAvg = _listingsAverageInFilter();
    final outlierStats = _outlierStats;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isRefreshingUi && !widget.embeddedGuideSoldComps)
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
        if (!_dateFilterRenderedByParent && !widget.suppressFilterChrome)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Spacer(),
                CompsDateRangeFilter(
                  selectedDays: _effectiveSelectedDays,
                  onChanged: _setSelectedDays,
                  color: colors.primary,
                ),
              ],
            ),
          ),

        // Grade pills (hidden when parent owns grade selection, e.g. embedded guide path)
        if (!widget.embeddedGuideSoldComps)
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

        if (chartPoints.length >= 2) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(
              0,
              widget.embeddedGuideSoldComps ? 0 : 8,
              0,
              8,
            ),
            child: AdaptiveListCard(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  widget.embeddedGuideSoldComps ? 8 : 12,
                  12,
                  8,
                ),
                child: SizedBox(
                  height: 148,
                  child: _PriceChart(
                    points: chartPoints,
                    listingsAverage: periodAvg,
                  ),
                ),
              ),
            ),
          ),
        ],

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
                  widget.embeddedGuideSoldComps
                      ? 'No guide sales in the selected date range at $_selectedGrade.'
                      : 'No recent eBay sales found at $_selectedGrade grade.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.60),
                      ),
                ),
              ],
            ),
          )
        else
          MarketListingsList(
            countLabel: _listingsCountLabel(outlierStats),
            rows: [
              for (var i = 0; i < _filteredComps.length; i++)
                _compListingRow(_filteredComps[i], outlierStats.isOutlier(i)),
            ],
          ),
      ],
    );
  }

  MarketListingRow _compListingRow(Comp comp, bool excluded) {
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
    final grade = (comp.grade ?? _selectedGrade).trim();
    final metaLine = comp.soldAt != null
        ? 'Sold on: ${formatMarketListingMetaDate(comp.soldAt!)}'
        : null;

    return MarketListingRow(
      title: comp.title,
      price: comp.price,
      chipLabel: chipLabel,
      chipBackground: chipBg,
      chipForeground: chipFg,
      metaLine: metaLine,
      imageUrl: comp.imageUrl,
      url: comp.url,
      excludedFromStats: excluded,
      gradeTag: grade.isEmpty ? 'Raw' : grade,
    );
  }

  String _listingsCountLabel(CompsOutlierStats stats) {
    final total = _filteredComps.length;
    final noun = total == 1 ? 'listing' : 'listings';
    if (!stats.hasOutliers) return '$total $noun';
    final excluded = stats.outlierIndices.length;
    final included = stats.includedCount;
    return '$total $noun · $included in chart'
        ' · $excluded outlier${excluded == 1 ? '' : 's'} excluded';
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

class _CompChartPoint {
  const _CompChartPoint({required this.soldAt, required this.price});

  final DateTime soldAt;
  final double price;
}

bool _isSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Pill badge drawn at the period-average point (right end of the avg segment).
class _AvgPillDotPainter extends FlDotPainter {
  const _AvgPillDotPainter({
    required this.fillColor,
    required this.textColor,
    required this.label,
  });

  final Color fillColor;
  final Color textColor;
  final String label;

  static const double _height = 22;
  static const double _padH = 10;

  Size _pillSizeFor(TextPainter tp) {
    final w = (tp.width + _padH * 2).clamp(44.0, 120.0);
    return Size(w, _height);
  }

  @override
  void draw(Canvas canvas, FlSpot spot, Offset c) {
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final sz = _pillSizeFor(tp);
    // Sit below the average line so the pill isn't clipped at the chart top.
    final center = Offset(c.dx, c.dy + sz.height / 2 + 4);
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: sz.width, height: sz.height),
      Radius.circular(sz.height / 2),
    );
    canvas.drawRRect(rrect, Paint()..color = fillColor);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = textColor.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }

  @override
  Size getSize(FlSpot spot) {
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return _pillSizeFor(tp);
  }

  @override
  Color get mainColor => fillColor;

  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) {
    if (a is _AvgPillDotPainter && b is _AvgPillDotPainter) {
      return t < 0.5 ? a : b;
    }
    return b;
  }

  @override
  List<Object?> get props => [fillColor, textColor, label];

  @override
  bool hitTest(FlSpot spot, Offset touched, Offset center, double extraThreshold) {
    final sz = getSize(spot);
    final pillCenter = Offset(center.dx, center.dy + sz.height / 2 + 4);
    final r = Rect.fromCenter(
      center: pillCenter,
      width: sz.width,
      height: sz.height,
    ).inflate(extraThreshold);
    return r.contains(touched);
  }
}

class _PriceChart extends StatelessWidget {
  const _PriceChart({
    required this.points,
    this.listingsAverage,
  });

  final List<_CompChartPoint> points;
  /// Mean price of all sold comps in the selected grade + date window (listings, not daily points).
  final double? listingsAverage;

  /// One x-axis label per calendar day (first point of each day in the series).
  bool _showBottomDateLabel(int index) {
    if (index == 0) return true;
    return !_isSameCalendarDay(points[index].soldAt, points[index - 1].soldAt);
  }

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
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

    var minPrice = points.map((p) => p.price).reduce((a, b) => a < b ? a : b);
    var maxPrice = points.map((p) => p.price).reduce((a, b) => a > b ? a : b);
    final avg = listingsAverage;
    if (avg != null) {
      if (avg < minPrice) minPrice = avg;
      if (avg > maxPrice) maxPrice = avg;
    }
    var axisSpan = maxPrice - minPrice;
    if (axisSpan < 1e-6) {
      axisSpan = (minPrice.abs() * 0.05) + 1;
    }

    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(
          i.toDouble(),
          double.parse(points[i].price.toStringAsFixed(2)),
        ),
    ];

    final lastX = (points.length - 1).toDouble();
    final pillCenterX = lastX / 2.0;

    const lineColor = AppTheme.primary;

    final lineBars = <LineChartBarData>[
      LineChartBarData(
        spots: spots,
        isCurved: true,
        color: lineColor,
        barWidth: 2.5,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, barData, index) {
            return FlDotCirclePainter(
              radius: 4,
              color: lineColor,
              strokeWidth: 2,
              strokeColor: colors.surface,
            );
          },
        ),
        belowBarData: BarAreaData(
          show: true,
          color: lineColor.withValues(alpha: 0.1),
        ),
      ),
    ];

    if (avg != null) {
      lineBars.add(
        LineChartBarData(
          spots: [FlSpot(0, avg), FlSpot(lastX, avg)],
          isCurved: false,
          color: colors.primary.withValues(alpha: 0.42),
          barWidth: 2,
          dashArray: [6, 4],
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
      );
      lineBars.add(
        LineChartBarData(
          spots: [FlSpot(pillCenterX, avg)],
          isCurved: false,
          color: Colors.transparent,
          barWidth: 0,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) {
              return _AvgPillDotPainter(
                fillColor: colors.primary,
                textColor: colors.onPrimary,
                label: formatUsd(avg),
              );
            },
          ),
          belowBarData: BarAreaData(show: false),
        ),
      );
    }

    return LineChart(
      LineChartData(
        extraLinesData: const ExtraLinesData(),
        gridData: FlGridData(
          show: true,
          drawHorizontalLine: true,
          drawVerticalLine: false,
          horizontalInterval: axisSpan / 4,
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
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= points.length) return const SizedBox.shrink();
                if (!_showBottomDateLabel(index)) return const SizedBox.shrink();
                final date = points[index].soldAt;
                final month = date.month.toString().padLeft(2, '0');
                final day = date.day.toString().padLeft(2, '0');
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '$month/$day',
                    style: axisLabelStyle,
                  ),
                );
              },
              reservedSize: 26,
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
          touchSpotThreshold: 22,
          getTouchedSpotIndicator: (barData, spotIndexes) {
            if (barData.barWidth == 0) {
              return List.filled(spotIndexes.length, null);
            }
            return defaultTouchedIndicators(barData, spotIndexes);
          },
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            tooltipMargin: 6,
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            maxContentWidth: 140,
            getTooltipColor: (_) => colors.surface,
            tooltipBorder: BorderSide(
              color: colors.outline.withValues(alpha: 0.35),
            ),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                if (spot.barIndex != 0) return null;
                final index = spot.spotIndex;
                final date = index >= 0 && index < points.length
                    ? points[index].soldAt
                    : null;
                final dateLine = date != null
                    ? '${date.month}/${date.day}/${date.year}'
                    : null;
                final priceStyle = TextStyle(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: -0.2,
                );
                final dateStyle = TextStyle(
                  color: colors.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500,
                  fontSize: 11,
                );
                if (dateLine == null) {
                  return LineTooltipItem(formatUsd(spot.y), priceStyle);
                }
                return LineTooltipItem(
                  formatUsd(spot.y),
                  priceStyle,
                  textAlign: TextAlign.center,
                  children: [
                    TextSpan(text: '\n$dateLine', style: dateStyle),
                  ],
                );
              }).toList();
            },
          ),
        ),
        minY: minPrice - axisSpan * 0.08,
        maxY: maxPrice + axisSpan * 0.22,
        lineBarsData: lineBars,
      ),
    );
  }
}

