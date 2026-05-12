import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/comps_service.dart';
import '../../../core/utils/currency_format.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/widgets/adaptive_list_card.dart';
import '../../../core/widgets/app_segmented_control.dart';
import 'card_active_listings_section.dart';
import 'card_comps_section.dart';

/// Segmented "Sold Comps" vs "For Sale" market block for item detail.
class MarketAnalysisSection extends ConsumerStatefulWidget {
  const MarketAnalysisSection({
    super.key,
    required this.masterCardId,
    required this.initialGrade,
    required this.segmentColor,
    this.refreshVersion = 0,
    this.externalLoading = false,
    this.cardHedgeGradeAverages,
    this.skipScraperSoldComps = false,
    this.showDbSoldCompsWhenAvailable = false,
    this.cardhedgeId,
    this.titleGain,
  });

  final String masterCardId;
  final String initialGrade;
  final Color segmentColor;
  final int refreshVersion;
  final bool externalLoading;
  /// Keys [Raw], [PSA 10], [PSA 9]; null values render as N/A (same as scraper comps).
  final Map<String, double?>? cardHedgeGradeAverages;
  final bool skipScraperSoldComps;
  /// When [skipScraperSoldComps] / CardHedge sold path is active, probe [card_sold_comps] for
  /// [initialGrade] and mount [CardCompsSection] without requiring a grade pill tap.
  final bool showDbSoldCompsWhenAvailable;
  /// When set, sold-comps grade pills fetch CardHedge `/v1/cards/comps` for that grade.
  final String? cardhedgeId;
  /// CardHedge `gain` on `master_card_definitions` — shown next to the section title (↑/↓).
  final double? titleGain;

  @override
  ConsumerState<MarketAnalysisSection> createState() => _MarketAnalysisSectionState();
}

class _MarketAnalysisSectionState extends ConsumerState<MarketAnalysisSection> {
  int _segment = 0;
  int _cardHedgeCompsNonce = 0;
  bool _cardHedgeCompsLoading = false;
  /// Grade whose comps are being fetched (spinner on pill before list mounts).
  String? _cardHedgeCompsFetchingGrade;
  /// Shown after [CompsService.ensureCardHedgeGradeComps] succeeds — avoids reading DB before rows exist.
  String? _cardHedgeCompsGrade;
  /// When [showDbSoldCompsWhenAvailable], set if [card_sold_comps] already has rows for [initialGrade].
  String? _autoDbCompsGrade;
  int _dbCompsProbeGen = 0;

  bool get _useCardHedgeSoldComps {
    if (widget.skipScraperSoldComps) return true;
    final avgs = widget.cardHedgeGradeAverages;
    if (avgs == null) return false;
    return avgs.values.any((v) => v != null && v > 0);
  }

  bool get _cardHedgePillsTappable =>
      widget.cardhedgeId != null && widget.cardhedgeId!.trim().isNotEmpty;

  /// Grade for the sold-comps list: explicit selection, in-flight tap target, then DB auto.
  String? get _listedCompsGrade =>
      _cardHedgeCompsGrade ??
      (_cardHedgeCompsLoading ? _cardHedgeCompsFetchingGrade : null) ??
      _autoDbCompsGrade;

  @override
  void initState() {
    super.initState();
    Future.microtask(_tryAutoShowDbComps);
  }

  @override
  void didUpdateWidget(covariant MarketAnalysisSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.masterCardId != widget.masterCardId ||
        oldWidget.initialGrade != widget.initialGrade ||
        oldWidget.showDbSoldCompsWhenAvailable != widget.showDbSoldCompsWhenAvailable ||
        oldWidget.skipScraperSoldComps != widget.skipScraperSoldComps ||
        oldWidget.refreshVersion != widget.refreshVersion ||
        oldWidget.cardHedgeGradeAverages != widget.cardHedgeGradeAverages) {
      Future.microtask(_tryAutoShowDbComps);
    }
  }

  Future<void> _tryAutoShowDbComps() async {
    if (!widget.showDbSoldCompsWhenAvailable || !_useCardHedgeSoldComps) {
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
    setState(() => _autoDbCompsGrade = has ? g : null);
  }

  Future<void> _onCardHedgeGradeTap(String grade) async {
    if (!_cardHedgePillsTappable) return;
    final hid = widget.cardhedgeId!.trim();
    setState(() {
      _cardHedgeCompsLoading = true;
      _cardHedgeCompsFetchingGrade = grade;
      _cardHedgeCompsGrade = null;
    });
    final n = await ref.read(compsServiceProvider).ensureCardHedgeGradeComps(
          masterVariantId: widget.masterCardId,
          cardhedgeId: hid,
          grade: grade,
        );
    if (!mounted) return;
    setState(() {
      _cardHedgeCompsLoading = false;
      _cardHedgeCompsFetchingGrade = null;
      if (n != null) {
        _cardHedgeCompsGrade = grade;
        _cardHedgeCompsNonce++;
      }
    });
    if (n == null && mounted) {
      AdaptiveSnackBar.show(
        context,
        message: 'Could not load CardHedge comps for $grade.',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  static const double _kGainNoiseEps = 0.01;

  String _titleSemanticsLabel() {
    final g = widget.titleGain;
    if (g == null || g.abs() < _kGainNoiseEps) return 'Market Analysis';
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
    final showGain = g != null && g.abs() >= _kGainNoiseEps;
    final positive = (g ?? 0) > 0;
    final accent = positive ? const Color(0xFF2E7D32) : colors.error;

    return Semantics(
      header: true,
      label: _titleSemanticsLabel(),
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('Market Analysis', style: baseStyle),
          if (showGain) ...[
            const SizedBox(width: 8),
            Icon(
              positive ? Icons.trending_up : Icons.trending_down,
              size: 22,
              color: accent,
            ),
            const SizedBox(width: 4),
            Text(
              '${positive ? '+' : ''}${g.toStringAsFixed(1)}%',
              style: baseStyle?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
                fontSize: (baseStyle.fontSize ?? 22) * 0.92,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTitle(context),
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
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CardHedgeCompsSummary(
                      gradeAverages:
                          widget.cardHedgeGradeAverages ?? const <String, double?>{},
                      pillsTappable: _cardHedgePillsTappable,
                      loadingGrade: _cardHedgeCompsLoading
                          ? (_cardHedgeCompsFetchingGrade ?? _cardHedgeCompsGrade)
                          : null,
                      selectedGrade: _listedCompsGrade,
                      onGradeTap: _onCardHedgeGradeTap,
                    ),
                    if (_listedCompsGrade != null) ...[
                      const SizedBox(height: 12),
                      CardCompsSection(
                        key: ValueKey(
                          'market-comps-${widget.masterCardId}-$_listedCompsGrade-'
                          '$_cardHedgeCompsNonce-${_cardHedgeCompsGrade != null}',
                        ),
                        masterCardId: widget.masterCardId,
                        initialGrade: _listedCompsGrade!,
                        refreshVersion:
                            _cardHedgeCompsGrade != null ? _cardHedgeCompsNonce : widget.refreshVersion,
                        externalLoading: widget.externalLoading,
                        embeddedCardHedgeComps: true,
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
          ),
      ],
    );
  }
}

class _CardHedgeCompsSummary extends StatelessWidget {
  const _CardHedgeCompsSummary({
    required this.gradeAverages,
    required this.pillsTappable,
    required this.onGradeTap,
    this.loadingGrade,
    this.selectedGrade,
  });

  final Map<String, double?> gradeAverages;
  final bool pillsTappable;
  final Future<void> Function(String grade) onGradeTap;
  final String? loadingGrade;
  final String? selectedGrade;

  double? _price(String key) => gradeAverages[key];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              _CardHedgeGradePill(
                label: 'Raw',
                price: _price('Raw'),
                selected: selectedGrade == 'Raw',
                loading: loadingGrade == 'Raw',
                onTap: pillsTappable ? () => onGradeTap('Raw') : null,
              ),
              const SizedBox(width: 8),
              _CardHedgeGradePill(
                label: 'PSA 10',
                price: _price('PSA 10'),
                selected: selectedGrade == 'PSA 10',
                loading: loadingGrade == 'PSA 10',
                onTap: pillsTappable ? () => onGradeTap('PSA 10') : null,
              ),
              const SizedBox(width: 8),
              _CardHedgeGradePill(
                label: 'PSA 9',
                price: _price('PSA 9'),
                selected: selectedGrade == 'PSA 9',
                loading: loadingGrade == 'PSA 9',
                onTap: pillsTappable ? () => onGradeTap('PSA 9') : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Same layout as sold-comps grade pills in [CardCompsSection].
class _CardHedgeGradePill extends StatelessWidget {
  const _CardHedgeGradePill({
    required this.label,
    required this.price,
    this.onTap,
    this.selected = false,
    this.loading = false,
  });

  final String label;
  final double? price;
  final VoidCallback? onTap;
  final bool selected;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final p = price;
    final interactive = onTap != null;

    final inner = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                  ),
                ),
                if (loading) ...[
                  const SizedBox(width: 6),
                  if (isIOS)
                    const CupertinoActivityIndicator(radius: 6)
                  else
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.primary,
                      ),
                    ),
                ],
              ],
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
    );

    final borderRadius = BorderRadius.circular(10);
    final framed = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(
          color: selected ? colors.primary.withValues(alpha: 0.85) : Colors.transparent,
          width: selected ? 2 : 0,
        ),
      ),
      child: inner,
    );

    Widget wrapInteractive(Widget child) {
      if (!interactive) return child;
      if (isIOS) {
        return CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          pressedOpacity: 0.72,
          borderRadius: borderRadius,
          onPressed: loading ? null : onTap,
          child: child,
        );
      }
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: borderRadius,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          child: child,
        ),
      );
    }

    return Expanded(
      child: AdaptiveListCard(
        margin: EdgeInsets.zero,
        cornerRadius: 10,
        child: interactive ? wrapInteractive(framed) : framed,
      ),
    );
  }
}
