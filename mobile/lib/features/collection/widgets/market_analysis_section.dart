import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/services/comps_service.dart';
import '../../../core/utils/currency_format.dart';
import '../../../core/utils/comps_outlier_utils.dart';
import '../../../core/utils/guide_grade_prices.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/widgets/adaptive_list_card.dart';
import '../../../core/widgets/card_fan_loader.dart';
import '../../../core/widgets/app_segmented_control.dart';
import 'card_active_listings_section.dart';
import 'card_comps_section.dart';
import 'comps_market_filters.dart';

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

  bool get _useGuideSoldCompsPath {
    if (widget.skipScraperSoldComps) return true;
    final avgs = widget.guideRecentPrices;
    if (avgs == null) return false;
    return avgs.values.any((v) => v != null && v > 0);
  }

  /// Grade passed to [CardCompsSection] — omitted while a fetch runs so the child
  /// does not race the edge write and flash the empty-state info box.
  String? get _mountedCompsGrade =>
      _guideSoldCompsLoading ? null : (_guideSoldCompsGrade ?? _autoDbCompsGrade);

  String _defaultCompsGrade() {
    final g = widget.initialGrade.trim();
    return g.isEmpty ? 'Raw' : g;
  }

  @override
  void initState() {
    super.initState();
    _compsGradeSelection = _defaultCompsGrade();
    Future.microtask(() async {
      await _refreshCachedCompsGrades();
      if (mounted) await _tryAutoShowDbComps();
    });
  }

  Future<void> _refreshCachedCompsGrades() async {
    final id = widget.masterCardId.trim();
    if (id.isEmpty) return;
    final grades = await ref.read(compsServiceProvider).listCachedCompsGradesForMaster(id);
    if (mounted) setState(() => _cachedCompsGrades = grades);
  }

  @override
  void didUpdateWidget(covariant MarketAnalysisSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.masterCardId != widget.masterCardId ||
        oldWidget.initialGrade != widget.initialGrade ||
        oldWidget.showDbSoldCompsWhenAvailable != widget.showDbSoldCompsWhenAvailable ||
        oldWidget.skipScraperSoldComps != widget.skipScraperSoldComps ||
        oldWidget.refreshVersion != widget.refreshVersion ||
        oldWidget.guideRecentPrices != widget.guideRecentPrices) {
      _compsGradeSelection = _defaultCompsGrade();
      Future.microtask(() async {
        await _refreshCachedCompsGrades();
        if (mounted) await _tryAutoShowDbComps();
      });
    }
  }

  Future<void> _tryAutoShowDbComps() async {
    if (!widget.showDbSoldCompsWhenAvailable || !_useGuideSoldCompsPath) {
      if (mounted && _autoDbCompsGrade != null) {
        setState(() => _autoDbCompsGrade = null);
      }
      return;
    }
    final id = widget.masterCardId.trim();
    if (id.isEmpty) return;
    final g = widget.initialGrade.trim().isEmpty ? 'Raw' : widget.initialGrade.trim();
    final gen = ++_dbCompsProbeGen;
    final has = await ref.read(compsServiceProvider).hasSoldCompsForGrade(id, g);
    if (!mounted || gen != _dbCompsProbeGen) return;
    if (!has) {
      setState(() {
        _autoDbCompsGrade = null;
        _compsGradeLow = null;
        _compsGradeHigh = null;
      });
      return;
    }
    await _applyTrimmedCompsRangeForGrade(g, gen: gen);
  }

  Future<void> _loadCompsForGrade(String grade) async {
    if (!_guideGradeMenuEnabled) return;
    final hid = widget.guidePriceCardId!.trim();
    final g = grade.trim().isEmpty ? 'Raw' : grade.trim();
    setState(() {
      _compsGradeSelection = g;
      _guideSoldCompsLoading = true;
      _guideSoldCompsFetchingGrade = g;
      _guideSoldCompsGrade = null;
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
    setState(() {
      _guideSoldCompsLoading = false;
      _guideSoldCompsFetchingGrade = null;
      if (result != null) {
        _guideSoldCompsGrade = g;
        _guideSoldCompsNonce++;
        if (result.saleCount > 0) {
          unawaited(_applyTrimmedCompsRangeForGrade(g));
        }
      }
    });
    if (result == null && mounted) {
      AdaptiveSnackBar.show(
        context,
        message: 'Could not load sold comps for $g.',
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
    unawaited(_loadCompsForGrade(picked));
  }

  bool get _guideGradeMenuEnabled =>
      widget.guidePriceCardId != null && widget.guidePriceCardId!.trim().isNotEmpty;

  bool get _hoistCompsDateFilter => _useGuideSoldCompsPath && _guideGradeMenuEnabled;

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
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('Market Analysis', style: baseStyle),
          const SizedBox(width: 8),
          Icon(
            strong ? (positive ? Icons.trending_up : Icons.trending_down) : Icons.trending_flat,
            size: 22,
            color: accent,
          ),
          const SizedBox(width: 4),
          Text(
            strong ? '${positive ? '+' : ''}${g.toStringAsFixed(1)}%' : '${g.toStringAsFixed(1)}%',
            style: baseStyle?.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
              fontSize: (baseStyle.fontSize ?? 22) * 0.92,
            ),
          ),
        ],
      ),
    );
  }

  bool get _showRecentPrices {
    final prices = widget.guideRecentPrices;
    if (prices == null) return false;
    return guideGradeMapHasAnyPrice(prices);
  }

  List<MapEntry<String, double?>> get _recentPriceSlots =>
      guideRecentPriceDisplaySlots(widget.guideRecentPrices ?? const {});

  @override
  Widget build(BuildContext context) {
    final recentSlots = _recentPriceSlots;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTitle(context),
        if (_showRecentPrices) ...[
          const SizedBox(height: 20),
          _GuideRecentPricesSection(slots: recentSlots),
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
          (_useGuideSoldCompsPath
              ? Column(
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
                        onLoadComps: _mountedCompsGrade == null && !_guideSoldCompsLoading
                            ? () => _loadCompsForGrade(_compsGradeSelection)
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_guideSoldCompsLoading &&
                        _guideSoldCompsFetchingGrade != null) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: CardFanLoader(size: 72)),
                      ),
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
                        selectedDays: _hoistCompsDateFilter ? _compsSelectedDays : null,
                        onSelectedDaysChanged: _hoistCompsDateFilter
                            ? (days) => setState(() => _compsSelectedDays = days)
                            : null,
                      ),
                    ],
                  ],
                )
              : CardCompsSection(
                  masterCardId: widget.masterCardId,
                  initialGrade: widget.initialGrade,
                  refreshVersion: widget.refreshVersion,
                  externalLoading: widget.externalLoading,
                ))
        else
          CardActiveListingsSection(
            masterCardId: widget.masterCardId,
            guideRecentPrices: widget.guideRecentPrices,
          ),
      ],
    );
  }
}

/// CardHedge / `current_prices` snapshot — three equal slots, not sold-comp averages.
class _GuideRecentPricesSection extends StatelessWidget {
  const _GuideRecentPricesSection({required this.slots});

  final List<MapEntry<String, double?>> slots;

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
              'Latest guide values from CardHedge — not sold-comp averages.',
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
    this.onLoadComps,
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
  final VoidCallback? onLoadComps;

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
        if (onLoadComps != null) ...[
          const SizedBox(height: 10),
          AdaptiveButton.child(
            onPressed: onLoadComps,
            style: AdaptiveButtonStyle.filled,
            color: AppTheme.primary,
            child: const Text(
              'Load sold comps',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ],
    );
  }
}
