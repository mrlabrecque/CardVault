import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/comps_service.dart';
import '../../../core/utils/currency_format.dart';
import '../../../core/utils/comps_outlier_utils.dart';
import '../../../core/ui/price_guide_copy.dart';
import '../../../core/utils/guide_grade_prices.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/widgets/adaptive_list_card.dart';
import '../../../core/widgets/card_fan_loader.dart';
import '../../../core/widgets/app_segmented_control.dart';
import 'card_active_listings_section.dart';
import 'card_comps_section.dart';
import 'comps_market_filters.dart';
import 'market_listings_list.dart' show MarketSectionNotice;

/// Segmented "Sold Comps" vs "For Sale" market block for item detail.
class MarketAnalysisSection extends ConsumerStatefulWidget {
  const MarketAnalysisSection({
    super.key,
    required this.masterCardId,
    required this.initialGrade,
    required this.segmentColor,
    this.refreshVersion = 0,
    this.externalLoading = false,
    this.guideRecentPrices,
    this.skipScraperSoldComps = false,
    this.showDbSoldCompsWhenAvailable = false,
    this.guidePriceCardId,
    this.titleGain,
    this.soldCompsCompactPrompt = false,
  });

  final String masterCardId;
  final String initialGrade;
  final Color segmentColor;
  final int refreshVersion;
  final bool externalLoading;
  /// `current_prices` grade → price; labels are shown as returned from CardHedge / DB.
  final Map<String, double?>? guideRecentPrices;
  final bool skipScraperSoldComps;
  /// When [skipScraperSoldComps] / guide sold-comps path is active, probe [card_sold_comps] for
  /// [initialGrade] and mount [CardCompsSection] without requiring a grade pill tap.
  final bool showDbSoldCompsWhenAvailable;
  /// When set, sold-comps grade pills fetch upstream `/v1/cards/comps` for that grade.
  final String? guidePriceCardId;
  /// `gain` on `master_card_definitions` — shown next to the section title (↑/↓).
  final double? titleGain;

  /// Catalog detail: quieter comps fetch (no error snackbars); grade/range/date row still shown.
  final bool soldCompsCompactPrompt;

  @override
  ConsumerState<MarketAnalysisSection> createState() => _MarketAnalysisSectionState();
}

class _MarketAnalysisSectionState extends ConsumerState<MarketAnalysisSection> {
  int _segment = 0;
  int _guideSoldCompsNonce = 0;
  bool _guideSoldCompsLoading = false;
  /// Grade shown in the header / grade sheet (before fetch completes).
  late String _compsGradeSelection;
  /// Grade whose comps are being fetched.
  String? _guideSoldCompsFetchingGrade;
  /// Shown after [CompsService.ensureGuideGradeComps] succeeds — avoids reading DB before rows exist.
  String? _guideSoldCompsGrade;
  /// When [showDbSoldCompsWhenAvailable], set if [card_sold_comps] already has rows for [initialGrade].
  String? _autoDbCompsGrade;
  int _dbCompsProbeGen = 0;
  List<String> _cachedCompsGrades = const [];
  double? _compsGradeLow;
  double? _compsGradeHigh;
  int _compsSelectedDays = 0;
  bool _guideSoldCompsEmpty = false;

  bool get _hasUsableGuidePrices =>
      guideGradeMapHasAnyPrice(widget.guideRecentPrices ?? const {});

  /// CardHedge-linked / catalog path: no sold comps without `current_prices` (For Sale still works).
  bool get _showGuidePricesRequiredNotice {
    if (_hasUsableGuidePrices) return false;
    final linked = widget.guidePriceCardId?.trim().isNotEmpty == true;
    return linked || widget.skipScraperSoldComps;
  }

  bool get _useGuideSoldCompsPath {
    if (widget.skipScraperSoldComps) return _hasUsableGuidePrices;
    final avgs = widget.guideRecentPrices;
    if (avgs == null) return false;
    return avgs.values.any((v) => v != null && v > 0);
  }

  /// Grade passed to [CardCompsSection]. Hidden while a grade fetch is in flight.
  String? get _mountedCompsGrade {
    if (_guideSoldCompsLoading) return null;
    final selection =
        _compsGradeSelection.trim().isEmpty ? 'Raw' : _compsGradeSelection.trim();
    final mounted = _guideSoldCompsGrade ?? _autoDbCompsGrade;
    if (mounted == null) return null;
    if (!currentPricesGradeLooselyEqual(mounted, selection)) return null;
    return mounted;
  }

  String _defaultCompsGrade() {
    final g = widget.initialGrade.trim();
    return g.isEmpty ? 'Raw' : g;
  }

  /// Sold Comps when guide prices or cached DB comps exist; For Sale is the fallback.
  int _preferredInitialSegment() {
    if (_hasUsableGuidePrices) return 0;
    if (widget.guidePriceCardId?.trim().isNotEmpty == true) return 0;
    if (widget.showDbSoldCompsWhenAvailable) return 0;
    if (_showGuidePricesRequiredNotice) return 1;
    return 0;
  }

  void _syncSegmentWithAvailableData() {
    if (!mounted) return;
    final preferSoldComps = _hasUsableGuidePrices ||
        _cachedCompsGrades.isNotEmpty ||
        widget.showDbSoldCompsWhenAvailable ||
        widget.guidePriceCardId?.trim().isNotEmpty == true;
    final next = preferSoldComps ? 0 : (_showGuidePricesRequiredNotice ? 1 : 0);
    if (next != _segment) setState(() => _segment = next);
  }

  @override
  void initState() {
    super.initState();
    _compsGradeSelection = _defaultCompsGrade();
    _segment = _preferredInitialSegment();
    Future.microtask(() async {
      await _refreshCachedCompsGrades();
      if (mounted) _syncSegmentWithAvailableData();
      if (mounted) await _tryAutoShowDbComps();
      if (mounted) _syncSegmentWithAvailableData();
    });
  }

  Future<void> _refreshCachedCompsGrades() async {
    final id = widget.masterCardId.trim();
    if (id.isEmpty) return;
    final grades = await ref.read(compsServiceProvider).listCachedCompsGradesForMaster(id);
    if (mounted) {
      setState(() => _cachedCompsGrades = grades);
      _syncSegmentWithAvailableData();
    }
  }

  @override
  void didUpdateWidget(covariant MarketAnalysisSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!guideGradePriceMapsEqual(
      oldWidget.guideRecentPrices,
      widget.guideRecentPrices,
    )) {
      unawaited(_refreshCachedCompsGrades().then((_) {
        if (mounted) _syncSegmentWithAvailableData();
      }));
      final hadPrices = guideGradeMapHasAnyPrice(oldWidget.guideRecentPrices ?? const {});
      final hasPricesNow = guideGradeMapHasAnyPrice(widget.guideRecentPrices ?? const {});
      if (!hadPrices && hasPricesNow && _segment == 1) {
        setState(() => _segment = 0);
      } else if (hadPrices && !hasPricesNow && _showGuidePricesRequiredNotice && _segment == 0) {
        setState(() => _segment = 1);
      }
    }
    if (oldWidget.masterCardId != widget.masterCardId ||
        oldWidget.initialGrade != widget.initialGrade ||
        oldWidget.showDbSoldCompsWhenAvailable != widget.showDbSoldCompsWhenAvailable ||
        oldWidget.skipScraperSoldComps != widget.skipScraperSoldComps ||
        oldWidget.refreshVersion != widget.refreshVersion ||
        oldWidget.guidePriceCardId != widget.guidePriceCardId ||
        oldWidget.soldCompsCompactPrompt != widget.soldCompsCompactPrompt) {
      _compsGradeSelection = _defaultCompsGrade();
      _guideSoldCompsEmpty = false;
      _guideSoldCompsGrade = null;
      _autoDbCompsGrade = null;
      Future.microtask(() async {
        await _refreshCachedCompsGrades();
        if (mounted) await _tryAutoShowDbComps();
      });
    }
  }

  Future<void> _tryAutoShowDbComps() async {
    if (_showGuidePricesRequiredNotice) {
      if (mounted) {
        setState(() {
          _guideSoldCompsLoading = false;
          _autoDbCompsGrade = null;
          _guideSoldCompsGrade = null;
        });
      }
      return;
    }
    if (!widget.showDbSoldCompsWhenAvailable || !_useGuideSoldCompsPath) {
      if (mounted && _autoDbCompsGrade != null) {
        setState(() => _autoDbCompsGrade = null);
      }
      return;
    }
    final id = widget.masterCardId.trim();
    if (id.isEmpty) return;
    final g = widget.initialGrade.trim().isEmpty ? 'Raw' : widget.initialGrade.trim();
    final mountedGrade = _guideSoldCompsGrade ?? _autoDbCompsGrade;
    if (!_guideSoldCompsLoading &&
        mountedGrade != null &&
        currentPricesGradeLooselyEqual(mountedGrade, g)) {
      return;
    }
    final gen = ++_dbCompsProbeGen;
    final has = await ref.read(compsServiceProvider).hasSoldCompsForGrade(id, g);
    if (!mounted || gen != _dbCompsProbeGen) return;
    if (!has) {
      if (_guideGradeMenuEnabled) {
        await _loadCompsForGrade(
          g,
          showErrorSnackBar: !widget.soldCompsCompactPrompt,
        );
      } else if (mounted) {
        setState(() {
          _autoDbCompsGrade = null;
          _compsGradeLow = null;
          _compsGradeHigh = null;
        });
      }
      return;
    }
    await _applyTrimmedCompsRangeForGrade(g, gen: gen);
  }

  Future<void> _loadCompsForGrade(
    String grade, {
    bool showErrorSnackBar = true,
  }) async {
    if (!_guideGradeMenuEnabled) return;
    final hid = widget.guidePriceCardId!.trim();
    final g = grade.trim().isEmpty ? 'Raw' : grade.trim();
    if (!_guideSoldCompsLoading &&
        _guideSoldCompsGrade != null &&
        currentPricesGradeLooselyEqual(_guideSoldCompsGrade!, g)) {
      return;
    }
    setState(() {
      _compsGradeSelection = g;
      _guideSoldCompsLoading = true;
      _guideSoldCompsFetchingGrade = g;
      _guideSoldCompsGrade = null;
      _autoDbCompsGrade = null;
      _guideSoldCompsEmpty = false;
      _compsGradeLow = null;
      _compsGradeHigh = null;
    });
    final result = await ref.read(compsServiceProvider).ensureGuideGradeComps(
          masterVariantId: widget.masterCardId,
          guidePriceCardId: hid,
          grade: g,
        );
    if (!mounted) return;
    await _refreshCachedCompsGrades();
    if (!mounted) return;
    final hasSales = result != null && result.saleCount > 0;
    setState(() {
      _guideSoldCompsLoading = false;
      _guideSoldCompsFetchingGrade = null;
      if (hasSales) {
        _guideSoldCompsGrade = g;
        _guideSoldCompsEmpty = false;
        _guideSoldCompsNonce++;
        unawaited(_applyTrimmedCompsRangeForGrade(g));
      } else {
        _guideSoldCompsGrade = null;
        _guideSoldCompsEmpty = true;
      }
    });
    if (!hasSales && showErrorSnackBar && mounted) {
      AdaptiveSnackBar.show(
        context,
        message: PriceGuideCopy.noSoldCompsForGrade(g),
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Future<void> _applyTrimmedCompsRangeForGrade(String grade, {int? gen}) async {
    final id = widget.masterCardId.trim();
    if (id.isEmpty) return;
    final g = grade.trim().isEmpty ? 'Raw' : grade.trim();
    final comps = await ref.read(compsServiceProvider).getMasterCardComps(id);
    if (!mounted) return;
    if (gen != null && gen != _dbCompsProbeGen) return;
    final filtered = comps
        .where((c) => (c.grade ?? 'Raw') == g)
        .toList();
    final low = CompsOutlierStats.trimmedLow(filtered);
    final high = CompsOutlierStats.trimmedHigh(filtered);
    if (!mounted) return;
    if (gen != null && gen != _dbCompsProbeGen) return;
    setState(() {
      if (gen != null) {
        _autoDbCompsGrade = g;
        _compsGradeSelection = g;
      }
      _compsGradeLow = low;
      _compsGradeHigh = high;
    });
  }

  List<AdaptivePopupMenuEntry> get _compsGradeMenuEntries {
    final grades = mergeGuideCompsGradeOptions(
      recentPrices: widget.guideRecentPrices,
      cachedCompsGrades: _cachedCompsGrades,
    );
    return [
      for (final g in grades)
        AdaptivePopupMenuItem<String>(
          value: g,
          label: _compsGradeMenuLabel(g),
        ),
    ];
  }

  String _compsGradeMenuLabel(String grade) {
    final selected = currentPricesGradeLooselyEqual(grade, _compsGradeSelection);
    if (selected) return '✓ $grade';
    return grade;
  }

  void _onCompsGradeMenuSelected(int index, AdaptivePopupMenuItem<String> entry) {
    final picked = entry.value?.trim();
    if (picked == null || picked.isEmpty) return;
    if (currentPricesGradeLooselyEqual(picked, _compsGradeSelection) &&
        _mountedCompsGrade != null) {
      return;
    }
    unawaited(_loadCompsForGrade(picked, showErrorSnackBar: false));
  }

  bool get _guideGradeMenuEnabled =>
      widget.guidePriceCardId != null && widget.guidePriceCardId!.trim().isNotEmpty;

  bool get _hoistCompsDateFilter =>
      _useGuideSoldCompsPath && _guideGradeMenuEnabled;

  bool get _gradeFilterActive =>
      !currentPricesGradeLooselyEqual(_compsGradeSelection, _defaultCompsGrade());

  static const double _kGainNoiseEps = 0.01;

  String _titleSemanticsLabel() {
    final g = widget.titleGain;
    if (g == null) return 'Market Analysis';
    if (g.abs() < _kGainNoiseEps) return 'Market Analysis, flat';
    final dir = g > 0 ? 'up' : 'down';
    return 'Market Analysis, $dir ${g.abs().toStringAsFixed(1)} percent';
  }

  Widget _buildTitle(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final baseStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        );
    final g = widget.titleGain;
    if (g == null) {
      return Semantics(
        header: true,
        label: _titleSemanticsLabel(),
        excludeSemantics: true,
        child: Text('Market Analysis', style: baseStyle),
      );
    }

    final strong = g.abs() >= _kGainNoiseEps;
    final positive = g > 0;
    final accent = strong
        ? (positive ? const Color(0xFF2E7D32) : colors.error)
        : colors.onSurface.withValues(alpha: 0.55);

    return Semantics(
      header: true,
      label: _titleSemanticsLabel(),
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('Market Analysis', style: baseStyle),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                strong
                    ? (positive ? Icons.trending_up : Icons.trending_down)
                    : Icons.trending_flat,
                size: 22,
                color: accent,
              ),
              const SizedBox(width: 4),
              Text(
                strong
                    ? '${positive ? '+' : ''}${g.toStringAsFixed(1)}%'
                    : '${g.toStringAsFixed(1)}%',
                style: baseStyle?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  fontSize: (baseStyle.fontSize ?? 22) * 0.92,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Recent Prices card when guide prices exist or the variant is on the guide path (N/A slots).
  bool get _showRecentPricesSection =>
      _hasUsableGuidePrices || _showGuidePricesRequiredNotice;

  List<MapEntry<String, double?>> get _recentPriceSlots =>
      guideRecentPriceDisplaySlots(widget.guideRecentPrices ?? const {});

  @override
  Widget build(BuildContext context) {
    final recentSlots = _recentPriceSlots;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTitle(context),
        if (_showRecentPricesSection) ...[
          const SizedBox(height: 20),
          _GuideRecentPricesSection(
            slots: recentSlots,
            showUnavailableFootnote: _showGuidePricesRequiredNotice,
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: AppSegmentedControl(
            labels: const ['Sold Comps', 'For Sale'],
            selectedIndex: _segment,
            onValueChanged: (index) => setState(() => _segment = index),
            color: widget.segmentColor,
            preset: AppSegmentedControlPreset.compact,
          ),
        ),
        const SizedBox(height: 12),
        if (_segment == 0)
          if (_showGuidePricesRequiredNotice)
            const _GuidePricesUnavailableNotice()
          else if (_useGuideSoldCompsPath)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                    if (_guideGradeMenuEnabled) ...[
                      _GuideSoldCompsGradeBar(
                        gradeLabel: _guideSoldCompsLoading
                            ? (_guideSoldCompsFetchingGrade ?? _compsGradeSelection)
                            : _compsGradeSelection,
                        low: _compsGradeLow,
                        high: _compsGradeHigh,
                        loading: _guideSoldCompsLoading,
                        gradeMenuEntries: _compsGradeMenuEntries,
                        onGradeMenuSelected: _onCompsGradeMenuSelected,
                        isGradeFiltered: _gradeFilterActive,
                        selectedDays: _compsSelectedDays,
                        onSelectedDaysChanged: (days) =>
                            setState(() => _compsSelectedDays = days),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (_guideSoldCompsLoading) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: CardFanLoader(size: 72)),
                      ),
                    ],
                    if (_guideSoldCompsEmpty && !_guideSoldCompsLoading) ...[
                      _SoldCompsNotFoundBanner(gradeLabel: _compsGradeSelection),
                      const SizedBox(height: 12),
                    ],
                    if (_mountedCompsGrade != null) ...[
                      CardCompsSection(
                        key: ValueKey(
                          'market-comps-${widget.masterCardId}-$_mountedCompsGrade',
                        ),
                        masterCardId: widget.masterCardId,
                        initialGrade: _mountedCompsGrade!,
                        refreshVersion:
                            _guideSoldCompsGrade != null ? _guideSoldCompsNonce : widget.refreshVersion,
                        externalLoading: widget.externalLoading,
                        embeddedGuideSoldComps: true,
                        suppressFilterChrome: _hoistCompsDateFilter,
                        selectedDays: _hoistCompsDateFilter ? _compsSelectedDays : null,
                        onSelectedDaysChanged: _hoistCompsDateFilter
                            ? (days) => setState(() => _compsSelectedDays = days)
                            : null,
                      ),
                    ] else if (!_guideSoldCompsLoading && !_guideGradeMenuEnabled) ...[
                      const _GuideSoldCompsEmptyPanel(
                        message:
                            'No recent sales found',
                      ),
                    ],
              ],
            )
          else
            CardCompsSection(
              masterCardId: widget.masterCardId,
              initialGrade: widget.initialGrade,
              refreshVersion: widget.refreshVersion,
              externalLoading: widget.externalLoading,
            )
        else
          CardActiveListingsSection(
            masterCardId: widget.masterCardId,
            guideRecentPrices: widget.guideRecentPrices,
          ),
      ],
    );
  }
}

/// Sold comps tab when the variant is linked but `current_prices` has no usable grades.
class _GuidePricesUnavailableNotice extends StatelessWidget {
  const _GuidePricesUnavailableNotice();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MarketSectionNotice(
      icon: isIOS ? CupertinoIcons.chart_bar_alt_fill : Icons.insights_outlined,
      title: 'Sold comps unavailable',
      message: PriceGuideCopy.soldCompsUnavailableMessage,
      highlightBorderColor: colors.outline.withValues(alpha: 0.28),
    );
  }
}

/// CardHedge / `current_prices` snapshot — three equal slots, not sold-comp averages.
class _GuideRecentPricesSection extends StatelessWidget {
  const _GuideRecentPricesSection({
    required this.slots,
    this.showUnavailableFootnote = false,
  });

  final List<MapEntry<String, double?>> slots;
  final bool showUnavailableFootnote;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AdaptiveListCard(
      margin: EdgeInsets.zero,
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Recent Prices',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: colors.onSurface,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              'Latest sold values - not averages.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.55),
                    fontSize: 12,
                    height: 1.25,
                  ),
            ),
            const SizedBox(height: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  colors.onSurface.withValues(alpha: 0.06),
                  colors.surface,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.outline.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0)
                      Container(
                        width: 1,
                        height: 40,
                        color: colors.outline.withValues(alpha: 0.45),
                      ),
                    Expanded(
                      child: _GuideRecentPriceSlot(
                        label: slots[i].key,
                        price: slots[i].value,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showUnavailableFootnote) ...[
              const SizedBox(height: 10),
              Text(
                PriceGuideCopy.recentPricesUnavailableFootnote,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.58),
                      height: 1.35,
                      fontSize: 12,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GuideRecentPriceSlot extends StatelessWidget {
  const _GuideRecentPriceSlot({required this.label, required this.price});

  final String label;
  final double? price;

  @override
  Widget build(BuildContext context) {
    final hasPrice = price != null && price! > 0;
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface.withValues(alpha: 0.58),
                  fontSize: 11,
                  height: 1.1,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            hasPrice ? formatUsd(price!) : 'N/A',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  fontSize: 14,
                  height: 1.1,
                  color: hasPrice
                      ? colors.onSurface
                      : colors.onSurface.withValues(alpha: 0.45),
                ),
          ),
        ],
      ),
    );
  }
}

/// Shown when guide sold comps were fetched but returned no sales for the grade.
class _SoldCompsNotFoundBanner extends StatelessWidget {
  const _SoldCompsNotFoundBanner({required this.gradeLabel});

  final String gradeLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final grade = gradeLabel.trim().isEmpty ? 'Raw' : gradeLabel.trim();

    return MarketSectionNotice(
      icon: isIOS ? CupertinoIcons.info : Icons.info_outline,
      title: PriceGuideCopy.noSoldCompsTitle,
      message: PriceGuideCopy.noSoldCompsForGrade(grade),
      highlightBorderColor: colors.outline.withValues(alpha: 0.28),
    );
  }
}

/// Sold comps grade header — distinct from [Recent Prices] (menu, not a second grade row).
class _GuideSoldCompsGradeBar extends StatelessWidget {
  const _GuideSoldCompsGradeBar({
    required this.gradeLabel,
    required this.gradeMenuEntries,
    required this.onGradeMenuSelected,
    required this.isGradeFiltered,
    required this.selectedDays,
    required this.onSelectedDaysChanged,
    this.low,
    this.high,
    this.loading = false,
  });

  final String gradeLabel;
  final List<AdaptivePopupMenuEntry> gradeMenuEntries;
  final void Function(int index, AdaptivePopupMenuItem<String> entry) onGradeMenuSelected;
  final bool isGradeFiltered;
  final int selectedDays;
  final ValueChanged<int> onSelectedDaysChanged;
  final double? low;
  final double? high;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final showRange = low != null && high != null && low! > 0 && high! > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CompsGradeFilter(
              gradeLabel: gradeLabel,
              menuEntries: gradeMenuEntries,
              onSelected: onGradeMenuSelected,
              isFiltered: isGradeFiltered,
              enabled: !loading,
              color: colors.primary,
            ),
            if (showRange) ...[
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Semantics(
                    label:
                        'Sold price range ${formatUsd(low!)} low, ${formatUsd(high!)} high',
                    excludeSemantics: true,
                    child: Text(
                      '↓ ${formatUsdCompact(low!)} · ↑ ${formatUsdCompact(high!)}',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.onSurface.withValues(alpha: 0.42),
                            fontWeight: FontWeight.w500,
                            fontSize: 11,
                            height: 1.15,
                            letterSpacing: -0.15,
                          ),
                    ),
                  ),
                ),
              ),
            ] else
              const Spacer(),
            if (loading) ...[
              if (isIOS)
                const CupertinoActivityIndicator(radius: 7)
              else
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              const SizedBox(width: 8),
            ],
            CompsDateRangeFilter(
              selectedDays: selectedDays,
              onChanged: onSelectedDaysChanged,
              color: colors.primary,
            ),
          ],
        ),
      ],
    );
  }
}

class _GuideSoldCompsEmptyPanel extends StatelessWidget {
  const _GuideSoldCompsEmptyPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MarketSectionNotice(
      icon: isIOS ? CupertinoIcons.info : Icons.info_outline,
      title: PriceGuideCopy.noSoldCompsTitle,
      message: message,
      highlightBorderColor: colors.outline.withValues(alpha: 0.28),
    );
  }
}
