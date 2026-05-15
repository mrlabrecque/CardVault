import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart' hide showAdaptiveDialog;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/user_card.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/adaptive_dropdown.dart';
import '../../core/widgets/adaptive_list_card.dart';
import '../../core/widgets/card_attributes_wrap.dart';
import '../../core/widgets/inline_notice_container.dart';
import '../../core/widgets/modal_sheet_scaffold.dart';
import '../../core/services/cards_service.dart';
import '../../core/utils/adaptive_ui.dart';
import '../../core/utils/currency_format.dart';
import '../../core/utils/usd_field.dart';
import 'widgets/full_bleed_card_hero.dart';
import 'widgets/market_analysis_section.dart';

// Bottom scroll padding when this route is shown inside [AppShell] so the last
// section clears the floating tab bar (matches collection / wishlist lists).
const double _kShellTabBarScrollInset = 100;

// ── HIG-oriented helpers (semantic color + scalable type) ───────────────────

Color _detailProfitColor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF4ADE80)
      : const Color(0xFF15803D);
}

TextStyle? _detailMetaLabelStyle(BuildContext context) {
  final t = Theme.of(context).textTheme;
  final c = Theme.of(context).colorScheme;
  return t.labelMedium?.copyWith(
    color: c.onSurface.withValues(alpha: 0.60),
    letterSpacing: 0.5,
    fontWeight: FontWeight.w500,
  );
}

TextStyle? _detailValueEmphasisStyle(BuildContext context) {
  final t = Theme.of(context).textTheme;
  final c = Theme.of(context).colorScheme;
  return t.titleLarge?.copyWith(
    fontWeight: FontWeight.w700,
    color: c.onSurface,
    height: 1.2,
  );
}

TextStyle? _detailCopyValueStyle(BuildContext context) {
  final t = Theme.of(context).textTheme;
  final c = Theme.of(context).colorScheme;
  return t.titleSmall?.copyWith(
    fontWeight: FontWeight.w600,
    color: c.onSurface,
  );
}

class ItemDetailScreen extends ConsumerStatefulWidget {
  const ItemDetailScreen({super.key, required this.card});

  final UserCard card;

  @override
  ConsumerState<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<ItemDetailScreen> {
  final ScrollController _scrollController = ScrollController();

  /// Scroll offset (px) at which the hero gradient is fully behind the AppBar.
  /// Re-measured from the rendered hero on every frame.
  double _heroSwitchThreshold = 320;
  bool _scrolledPastHero = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    final c = widget.card;
    if (c.masterCardId != null && (c.displayValue ?? 0) <= 0) {
      Future.microtask(() {
        if (mounted) ref.invalidate(userCardsProvider);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final past = _scrollController.offset > _heroSwitchThreshold;
    if (past != _scrolledPastHero) {
      setState(() => _scrolledPastHero = past);
    }
  }

  UserCard _resolvedCard() {
    final async = ref.watch(userCardsProvider);
    final list = async.asData?.value;
    if (list != null) {
      for (final c in list) {
        if (c.id == widget.card.id) return c;
      }
    }
    return widget.card;
  }

  String _missingCatalogValueNotice(UserCard card) {
    if (card.masterCardId == null) {
      return 'This copy is not linked to the catalog, so no guide price is available.';
    }
    final hasCh = card.embeddedMasterGuideCardId != null && card.embeddedMasterGuideCardId!.trim().isNotEmpty;
    if (!hasCh) {
      return 'This variant has no catalog match yet — no guide price in the app. Try again from the catalog card page.';
    }
    return 'No guide price for this slab yet. Pull to refresh on Collection or reopen this card in a moment.';
  }

  void _close(BuildContext context) {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    GoRouter.maybeOf(context)?.go('/collection');
  }

  String _resolveDefaultGrade(UserCard card) {
    if (!card.isGraded) return 'Raw';
    final grade = card.grade ?? '';
    if (grade == '10' || grade == '10.0') return 'PSA 10';
    if (grade == '9' || grade == '9.0') return 'PSA 9';
    return 'Raw';
  }

  String _relativeRefreshed(DateTime t) {
    final now = DateTime.now();
    final d = now.difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${t.month}/${t.day}/${t.year}';
  }

  static const _graders = ['PSA', 'BGS', 'SGC', 'CGC', 'CSG'];

  Future<void> _openEditSheet(UserCard card) async {
    final usdPaidFmt = createUsdCurrencyInputFormatter();
    final pricePaidCtrl = TextEditingController(
      text: card.pricePaid != null ? usdPaidFmt.formatDouble(card.pricePaid!) : '',
    );
    final serialCtrl = TextEditingController(text: card.serialNumber ?? '');
    final graderCtrl = TextEditingController(text: card.grader ?? 'PSA');
    final gradeCtrl = TextEditingController(text: card.grade ?? '');
    final otherParallelCtrl = TextEditingController();
    var isGraded = card.isGraded;
    var selectedParallelId = card.parallelId;
    var saving = false;

    List<SetParallel> parallels = const [];
    if (card.setId != null) {
      try {
        parallels = await ref.read(cardsServiceProvider).getParallels(card.setId!);
      } catch (e, st) {
        debugPrint('ItemDetail getParallels: $e\n$st');
        parallels = const [];
      }
    }
    if (!mounted) return;

    await showAdaptiveSheet(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final colors = Theme.of(sheetContext).colorScheme;
            final isOtherParallel = selectedParallelId == '__other__';

            Future<void> saveFromSheet() async {
              setSheetState(() => saving = true);
              try {
                final selectedParallelName = selectedParallelId == null
                    ? null
                    : parallels
                        .where((p) => p.id == selectedParallelId)
                        .map((p) => p.name.trim())
                        .where((name) => name.isNotEmpty)
                        .firstOrNull;
                final parallelName = isOtherParallel
                    ? (otherParallelCtrl.text.trim().isEmpty ? 'Base' : otherParallelCtrl.text.trim())
                    : (selectedParallelId == null ? 'Base' : (selectedParallelName ?? card.parallel));
                await ref.read(cardsServiceProvider).updateCard(card.id, {
                  'price_paid': parseUsdInput(pricePaidCtrl.text),
                  'serial_number': serialCtrl.text.isEmpty ? null : serialCtrl.text,
                  'is_graded': isGraded,
                  'grader': isGraded ? graderCtrl.text : null,
                  'grade_value': isGraded ? gradeCtrl.text : null,
                  'parallel_id': isOtherParallel ? null : selectedParallelId,
                  'parallel_name': parallelName,
                });
                ref.invalidate(userCardsProvider);
                if (!mounted || !sheetContext.mounted) return;
                Navigator.of(sheetContext).pop();
                if (!mounted) return;
                AdaptiveSnackBar.show(context, message: 'Card updated.', type: AdaptiveSnackBarType.success);
              } catch (e) {
                if (!mounted) return;
                AdaptiveSnackBar.show(context, message: 'Error: $e', type: AdaptiveSnackBarType.error);
              } finally {
                if (mounted) {
                  setSheetState(() => saving = false);
                }
              }
            }

            return ModalSheetScaffold(
              title: 'Edit your copy',
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: _EditCardPreview(card: card),
                  ),
                  const SizedBox(height: 16),
                  _SheetFieldLabel('Parallel'),
                  if (parallels.isNotEmpty)
                    AdaptiveDropdown<String?>(
                      value: selectedParallelId,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Base')),
                        ...parallels.map((p) => DropdownMenuItem(
                              value: p.id,
                              child: Text('${p.name}${p.serialMax != null ? ' /${p.serialMax}' : ''}'),
                            )),
                        const DropdownMenuItem(value: '__other__', child: Text('Other…')),
                      ],
                      onChanged: (id) => setSheetState(() {
                        selectedParallelId = id;
                        otherParallelCtrl.text = '';
                      }),
                    )
                  else
                    AdaptiveTextField(
                      controller: otherParallelCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      placeholder: 'Base',
                      cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(sheetContext),
                      decoration: InputDecoration(
                        hintText: 'Base',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                    ),
                  if (isOtherParallel) ...[
                    const SizedBox(height: 12),
                    _SheetFieldLabel('Parallel name'),
                    AdaptiveTextField(
                      controller: otherParallelCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      placeholder: 'e.g. Pink Refractor',
                      cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(sheetContext),
                      decoration: InputDecoration(
                        hintText: 'e.g. Pink Refractor',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _SheetFieldLabel('Price Paid'),
                  AdaptiveTextField(
                    controller: pricePaidCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [usdPaidFmt],
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    placeholder: '\$0.00',
                    cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(sheetContext),
                    decoration: InputDecoration(
                      hintText: '\$0.00',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                  ),
                  if (card.serialMax != null) ...[
                    const SizedBox(height: 16),
                    _SheetFieldLabel('Serial # (your copy, e.g. 34 of /${card.serialMax})'),
                    AdaptiveTextField(
                      controller: serialCtrl,
                      keyboardType: TextInputType.number,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      placeholder: 'e.g. 34',
                      cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(sheetContext),
                      decoration: InputDecoration(
                        hintText: 'e.g. 34',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: _SheetFieldLabel.inline('Graded copy'),
                          ),
                        ),
                        AdaptiveSwitch(
                          value: isGraded,
                          onChanged: (v) => setSheetState(() => isGraded = v),
                          activeColor: AppTheme.primary,
                        ),
                      ],
                    ),
                  ),
                  if (isGraded) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: AdaptiveDropdown<String>(
                            value: graderCtrl.text.isEmpty ? 'PSA' : graderCtrl.text,
                            decoration: InputDecoration(
                              labelText: 'Grader',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              isDense: true,
                            ),
                            items: _graders.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                            onChanged: (v) => setSheetState(() => graderCtrl.text = v ?? 'PSA'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AdaptiveTextField(
                            controller: gradeCtrl,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            placeholder: '10',
                            cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(sheetContext),
                            decoration: InputDecoration(
                              labelText: 'Grade',
                              hintText: '10',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Divider(height: 1, color: colors.outline.withValues(alpha: 0.2)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: AdaptiveButton.child(
                      onPressed: saving ? null : saveFromSheet,
                      style: AdaptiveButtonStyle.filled,
                      color: AppTheme.primary,
                      child: saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'Save',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    pricePaidCtrl.dispose();
    serialCtrl.dispose();
    graderCtrl.dispose();
    gradeCtrl.dispose();
    otherParallelCtrl.dispose();
  }

  Future<void> _delete(UserCard card) async {
    final confirm = await showAdaptiveDialog<bool>(
      context: context,
      title: 'Delete Card',
      content: 'Remove this card from your collection?',
      cancelLabel: 'Cancel',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (confirm == true) {
      await ref.read(cardsServiceProvider).deleteCard(card.id);
      ref.invalidate(userCardsProvider);
      if (mounted) _close(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = _resolvedCard();
    final colors = Theme.of(context).colorScheme;
    final hasValue = card.displayValue != null;
    final pl = hasValue ? card.pl : null;
    final plPct = (hasValue && card.pricePaid != null && card.pricePaid! > 0) ? card.plPct : null;

    final padding = MediaQuery.paddingOf(context);
    final bottomPad = padding.bottom;
    final topInset = padding.top;

    final onLight = _scrolledPastHero;
    final iconTint = onLight ? colors.onSurface : Colors.white;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        forceMaterialTransparency: true,
        foregroundColor: iconTint,
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        iconTheme: IconThemeData(color: iconTint),
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: GlassCircleIconButton(
              icon: Icons.arrow_back_ios_new,
              onPressed: () => _close(context),
              tooltip: 'Back',
              iconSize: 17,
              onDarkSurface: !onLight,
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: AdaptivePopupMenuButton.icon<String>(
                icon: 'ellipsis',
                tint: iconTint,
                size: 44,
                buttonStyle: PopupButtonStyle.glass,
                items: const [
                  AdaptivePopupMenuItem<String>(
                    label: 'Edit',
                    icon: 'pencil',
                    value: 'edit',
                  ),
                  AdaptivePopupMenuItem<String>(
                    label: 'Delete',
                    icon: 'trash',
                    value: 'delete',
                  ),
                ],
                onSelected: (_, entry) {
                  switch (entry.value) {
                    case 'edit':
                      _openEditSheet(card);
                      break;
                    case 'delete':
                      _delete(card);
                      break;
                  }
                },
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          FullBleedHero(
            topInset: topInset,
            details: HeroDetails(
              player: card.player,
              sport: card.sport,
              cardNumber: card.cardNumber,
              imageUrl: card.imageUrl,
              parallel: card.parallel,
              year: card.year,
              releaseName: card.set,
              setName: card.checklist,
              serialNumber: card.serialNumber,
              serialMax: card.serialMax,
              rookie: card.rookie,
              autograph: card.autograph,
              memorabilia: card.memorabilia,
              ssp: card.ssp,
              isGraded: card.isGraded,
              grader: card.grader,
              grade: card.grade,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, _kShellTabBarScrollInset + bottomPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  container: true,
                  label: 'Value and profit or loss',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          'Value',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _InfoBox(
                              label: 'Current Value',
                              value: hasValue ? formatUsd(card.displayValue!) : 'N/A',
                              trend: hasValue ? card.valueTrendForDisplay : 0,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _PlCard(pl: pl, plPct: plPct),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (hasValue)
                  _ValueRefreshNotice(
                    refreshedAt: card.displayValueRefreshedAt,
                    relativeRefreshed: _relativeRefreshed,
                    marketGuideHeadline: card.headlineValueUsesGuidePrices,
                  )
                else
                  InlineNoticeContainer(
                    icon: Icon(Icons.info_outline, size: 20, color: colors.onSurface.withValues(alpha: 0.60)),
                    child: Text(
                      _missingCatalogValueNotice(card),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            height: 1.35,
                            color: colors.onSurface.withValues(alpha: 0.75),
                          ),
                    ),
                  ),
                const SizedBox(height: 24),
                Semantics(
                  container: true,
                  label: 'Your copy of this card',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          'Your copy',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _CopyTile(label: 'Parallel', value: card.parallel),
                      const SizedBox(height: 8),
                      _CopyTile(label: 'Price paid', value: formatUsd(card.pricePaid ?? 0)),
                      if (card.serialNumber != null || card.serialMax != null) ...[
                        const SizedBox(height: 8),
                        _CopyTile(
                          label: 'Serial #',
                          value: card.serialNumber != null && card.serialMax != null
                              ? '${card.serialNumber}/${card.serialMax}'
                              : card.serialMax != null
                                  ? '/${card.serialMax}'
                                  : card.serialNumber!,
                        ),
                      ],
                      if (card.isGraded) ...[
                        const SizedBox(height: 8),
                        _CopyTile(label: 'Grade', value: '${card.grader ?? 'PSA'} ${card.grade ?? ''}'.trim()),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                if (card.masterCardId != null)
                  MarketAnalysisSection(
                    masterCardId: card.masterCardId!,
                    initialGrade: _resolveDefaultGrade(card),
                    segmentColor: colors.primary,
                    titleGain: card.masterDefinitionGain,
                    guidePriceCardId: card.embeddedMasterGuideCardId,
                    guideRecentPrices: card.hasUsableGuideGradePricesForMarket
                        ? card.guideGradePricesForMarketSection
                        : null,
                    skipScraperSoldComps: card.hasUsableGuideGradePricesForMarket,
                    showDbSoldCompsWhenAvailable: card.hasUsableGuideGradePricesForMarket,
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No catalog link — market data unavailable.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.onSurface.withValues(alpha: 0.60),
                          ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlCard extends StatelessWidget {
  const _PlCard({required this.pl, required this.plPct});

  final double? pl;
  final double? plPct;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasValue = pl != null && plPct != null;
    final positive = hasValue ? pl! >= 0 : true;
    final accent = positive ? _detailProfitColor(context) : colors.error;

    return AdaptiveListCard(
      margin: EdgeInsets.zero,
      cornerRadius: 12,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('P/L', style: _detailMetaLabelStyle(context)),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  hasValue ? formatUsdSigned(pl!) : 'N/A',
                  style: _detailValueEmphasisStyle(context)?.copyWith(color: accent),
                ),
                Text(
                  hasValue ? '${plPct!.toStringAsFixed(1)}%' : 'N/A',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ValueRefreshNotice extends StatelessWidget {
  const _ValueRefreshNotice({
    required this.refreshedAt,
    required this.relativeRefreshed,
    this.marketGuideHeadline = false,
  });

  final DateTime? refreshedAt;
  final String Function(DateTime) relativeRefreshed;
  /// When true, [refreshedAt] reflects guide-price / `current_prices`, not sold-comps refresh.
  final bool marketGuideHeadline;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final t = refreshedAt;
    final text = t != null
        ? (marketGuideHeadline
            ? 'Market guide last updated ${relativeRefreshed(t)} · ${_fmtClock(t)}'
            : 'Sold comps value last refreshed ${relativeRefreshed(t)} · ${_fmtClock(t)}')
        : (marketGuideHeadline
            ? 'No market guide timestamp yet — it updates when catalog prices are fetched.'
            : 'Value has not been refreshed yet — open Edit or pull collection refresh when available.');

    final theme = Theme.of(context);
    return Semantics(
      label: text,
      child: InlineNoticeContainer(
        icon: Icon(Icons.schedule, size: 20, color: colors.onSurface.withValues(alpha: 0.60)),
        child: Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            height: 1.35,
            color: colors.onSurface.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }

  String _fmtClock(DateTime t) {
    final l = t.toLocal();
    final h = l.hour > 12 ? l.hour - 12 : (l.hour == 0 ? 12 : l.hour);
    final am = l.hour >= 12 ? 'PM' : 'AM';
    return '${l.month}/${l.day}/${l.year} $h:${l.minute.toString().padLeft(2, '0')} $am';
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.label, required this.value, this.trend = 0});
  final String label;
  final String value;
  final int trend;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AdaptiveListCard(
      margin: EdgeInsets.zero,
      cornerRadius: 12,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: _detailMetaLabelStyle(context)),
            const SizedBox(height: 4),
            Row(
              children: [
                if (trend != 0) ...[
                  Icon(
                    trend > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 16,
                    semanticLabel: trend > 0 ? 'Trending up' : 'Trending down',
                    color: trend > 0 ? _detailProfitColor(context) : colors.error,
                  ),
                  const SizedBox(width: 2),
                ],
                Text(value, style: _detailValueEmphasisStyle(context)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CopyTile extends StatelessWidget {
  const _CopyTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: AdaptiveListCard(
        margin: EdgeInsets.zero,
        cornerRadius: 12,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: _detailMetaLabelStyle(context)),
              const SizedBox(height: 2),
              Text(value, style: _detailCopyValueStyle(context)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Edit-sheet helpers (mirrors the catalog Add-to-Collection sheet) ────────

class _SheetFieldLabel extends StatelessWidget {
  const _SheetFieldLabel(this.label) : _inline = false;
  const _SheetFieldLabel.inline(this.label) : _inline = true;

  final String label;
  final bool _inline;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final inputTheme = Theme.of(context).inputDecorationTheme;
    final baseStyle = inputTheme.labelStyle ?? textTheme.bodySmall ?? const TextStyle(fontSize: 12);
    final style = baseStyle.copyWith(
      color: colors.onSurface.withValues(alpha: 0.65),
      fontWeight: FontWeight.w600,
    );
    if (_inline) {
      return Text(label, style: style);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(label, style: style),
    );
  }
}

class _EditCardPreview extends StatelessWidget {
  const _EditCardPreview({required this.card});

  final UserCard card;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AdaptiveListCard(
      margin: EdgeInsets.zero,
      cornerRadius: 12,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: card.player,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                if (card.cardNumber != null)
                  TextSpan(
                    text: '  #${card.cardNumber}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: colors.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            if (card.year != null || card.set != null || card.checklist != null)
              Text(
                [
                  if (card.year != null) '${card.year}',
                  if (card.set != null) card.set,
                  if (card.checklist != null && card.checklist != card.set) card.checklist,
                ].join(' · '),
                style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.6)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (card.parallel != 'Base')
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  card.parallel,
                  style: TextStyle(fontSize: 12, color: colors.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 8),
            CardAttributesWrap(
              rookie: card.rookie,
              autograph: card.autograph,
              memorabilia: card.memorabilia,
              ssp: card.ssp,
              serialMax: card.serialMax,
            ),
          ],
        ),
      ),
    );
  }
}

