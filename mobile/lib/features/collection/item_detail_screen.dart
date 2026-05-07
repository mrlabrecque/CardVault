import 'dart:ui' as ui;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart' hide showAdaptiveDialog;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/user_card.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/adaptive_dropdown.dart';
import '../../core/widgets/adaptive_list_card.dart';
import '../../core/widgets/attr_tag.dart';
import '../../core/widgets/modal_sheet_scaffold.dart';
import '../../core/widgets/serial_tag.dart';
import '../../core/services/cards_service.dart';
import '../../core/utils/adaptive_ui.dart';
import 'widgets/market_analysis_section.dart';

// ── HIG-oriented helpers (semantic color + scalable type) ───────────────────

Color _detailProfitColor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF4ADE80)
      : const Color(0xFF15803D);
}

TextStyle? _detailMetaLabelStyle(BuildContext context) {
  final t = Theme.of(context).textTheme;
  final c = Theme.of(context).colorScheme;
  return t.labelSmall?.copyWith(
    color: c.onSurface.withValues(alpha: 0.45),
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
  final GlobalKey _heroKey = GlobalKey();

  /// Scroll offset (px) at which the hero gradient is fully behind the AppBar.
  /// Re-measured from the rendered hero on every frame.
  double _heroSwitchThreshold = 320;
  bool _scrolledPastHero = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
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

  void _maybeMeasureHero() {
    final ctx = _heroKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final topInset = MediaQuery.paddingOf(context).top;
    final next = box.size.height - (topInset + kToolbarHeight) - 8;
    if ((next - _heroSwitchThreshold).abs() > 1) {
      _heroSwitchThreshold = next;
      _onScroll();
    }
  }

  UserCard _resolvedCard() {
    final list = ref.watch(userCardsProvider).value;
    if (list == null) return widget.card;
    for (final c in list) {
      if (c.id == widget.card.id) return c;
    }
    return widget.card;
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
    final pricePaidCtrl = TextEditingController(text: card.pricePaid?.toStringAsFixed(2) ?? '');
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
            final isOtherParallel = selectedParallelId == '__other__';

            Future<void> saveFromSheet() async {
              setSheetState(() => saving = true);
              try {
                final parallelName = isOtherParallel
                    ? (otherParallelCtrl.text.trim().isEmpty ? 'Base' : otherParallelCtrl.text.trim())
                    : (selectedParallelId == null ? 'Base' : null);
                await ref.read(cardsServiceProvider).updateCard(card.id, {
                  'price_paid': double.tryParse(pricePaidCtrl.text),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (parallels.isNotEmpty)
                    AdaptiveDropdown<String?>(
                      value: selectedParallelId,
                      decoration: const InputDecoration(labelText: 'Parallel', border: OutlineInputBorder()),
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
                      placeholder: 'Parallel',
                      cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(sheetContext),
                      decoration: const InputDecoration(labelText: 'Parallel', border: OutlineInputBorder()),
                    ),
                  if (isOtherParallel) ...[
                    const SizedBox(height: 12),
                    AdaptiveTextField(
                      controller: otherParallelCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      placeholder: 'Parallel name',
                      cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(sheetContext),
                      decoration: const InputDecoration(labelText: 'Parallel name', border: OutlineInputBorder()),
                    ),
                  ],
                  const SizedBox(height: 12),
                  AdaptiveTextField(
                    controller: pricePaidCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    placeholder: 'Price Paid',
                    cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(sheetContext),
                    decoration: InputDecoration(
                      labelText: 'Price Paid',
                      prefixText: '\$',
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Theme.of(sheetContext).colorScheme.surface,
                    ),
                  ),
                  if (card.serialMax != null) ...[
                    const SizedBox(height: 12),
                    AdaptiveTextField(
                      controller: serialCtrl,
                      keyboardType: TextInputType.number,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      placeholder: 'Serial #',
                      cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(sheetContext),
                      decoration: InputDecoration(
                        labelText: 'Serial # (your copy, e.g. 34 of /${card.serialMax})',
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Theme.of(sheetContext).colorScheme.surface,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        'Graded',
                        style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(sheetContext).colorScheme.onSurface.withValues(alpha: 0.65),
                            ),
                      ),
                      const Spacer(),
                      AdaptiveSwitch(
                        value: isGraded,
                        onChanged: (v) => setSheetState(() => isGraded = v),
                        activeColor: const Color(0xFF800020),
                      ),
                    ],
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
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Theme.of(sheetContext).colorScheme.surface,
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
                            placeholder: 'Grade',
                            cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(sheetContext),
                            decoration: InputDecoration(
                              labelText: 'Grade',
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Theme.of(sheetContext).colorScheme.surface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: AdaptiveButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          label: 'Cancel',
                          style: AdaptiveButtonStyle.bordered,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AdaptiveButton(
                          onPressed: saving ? null : saveFromSheet,
                          label: saving ? 'Saving…' : 'Save',
                          style: AdaptiveButtonStyle.filled,
                          color: const Color(0xFF800020),
                        ),
                      ),
                    ],
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
    final pl = (card.currentValue ?? 0) - (card.pricePaid ?? 0);
    final plPct = card.pricePaid != null && card.pricePaid! > 0 ? (pl / card.pricePaid!) * 100 : 0.0;

    final padding = MediaQuery.paddingOf(context);
    final bottomPad = padding.bottom;
    final topInset = padding.top;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeMeasureHero();
    });

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
        leadingWidth: 60,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: _GlassCircleIconButton(
              icon: Icons.arrow_back_ios_new,
              onPressed: () => _close(context),
              tooltip: 'Back',
              iconSize: 16,
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
                size: 38,
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
          _FullBleedHero(key: _heroKey, card: card, topInset: topInset),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 16 + bottomPad),
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
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _InfoBox(
                              label: 'Current Value',
                              value: '\$${(card.currentValue ?? 0).toStringAsFixed(2)}',
                              trend: card.valueTrend,
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
                const SizedBox(height: 10),
                _ValueRefreshNotice(
                  refreshedAt: card.valueRefreshedAt,
                  relativeRefreshed: _relativeRefreshed,
                ),
                const SizedBox(height: 8),
                if (ref.watch(dailyTierCardIdsProvider).contains(card.id))
                  const _DailyRefreshBadge()
                else
                  _PriceCheckToggle(
                    enabled: card.weeklyPriceCheck,
                    onChanged: (val) async {
                      await ref.read(cardsServiceProvider).setWeeklyPriceCheck(card.id, val);
                      ref.invalidate(userCardsProvider);
                    },
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
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _CopyTile(label: 'Parallel', value: card.parallel),
                      const SizedBox(height: 8),
                      _CopyTile(label: 'Price paid', value: '\$${(card.pricePaid ?? 0).toStringAsFixed(2)}'),
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
                    parallelName: card.parallel,
                    initialGrade: _resolveDefaultGrade(card),
                    segmentColor: colors.primary,
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No catalog link — market data unavailable.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.onSurface.withValues(alpha: 0.55),
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

class _FullBleedHero extends StatelessWidget {
  const _FullBleedHero({super.key, required this.card, required this.topInset});

  final UserCard card;
  final double topInset;

  String get _sportEmoji => switch (card.sport.toLowerCase()) {
    'basketball' => '🏀',
    'baseball'   => '⚾',
    'football'   => '🏈',
    'hockey'     => '🏒',
    'soccer'     => '⚽',
    _            => '🏀',
  };

  @override
  Widget build(BuildContext context) {
    final imageUrl = card.imageUrl;
    final cardNumber = card.cardNumber;
    final parallelName = card.parallel != 'Base' ? card.parallel : null;

    final metaParts = <String>[
      if (card.year != null) card.year.toString(),
      if (card.set != null) card.set!,
      if (card.checklist != null && card.checklist != card.set) card.checklist!,
    ];

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF800020), Color(0xFF3D0010)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, topInset + kToolbarHeight + 4, 20, 28),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      width: 180,
                      height: 252,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 180,
                      height: 252,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(_sportEmoji, style: const TextStyle(fontSize: 64)),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 18),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: card.player,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              if (cardNumber != null)
                TextSpan(
                  text: '  #$cardNumber',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
            ]),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (metaParts.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              metaParts.join(' · '),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (parallelName != null) ...[
            const SizedBox(height: 4),
            Text(
              parallelName,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              if (card.rookie) AttrTag('RC', color: const Color(0xFF16A34A)),
              if (card.autograph) AttrTag('AUTO', color: const Color(0xFF7C3AED)),
              if (card.memorabilia) AttrTag('PATCH', color: const Color(0xFF0369A1)),
              if (card.ssp) AttrTag('SSP', color: const Color(0xFFB45309)),
              if (card.isGraded) AttrTag('${card.grader ?? 'PSA'} ${card.grade ?? ''}'.trim()),
              SerialTag(serialNumber: card.serialNumber, serialMax: card.serialMax),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlCard extends StatelessWidget {
  const _PlCard({required this.pl, required this.plPct});

  final double pl;
  final double plPct;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final positive = pl >= 0;
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
                  '${positive ? '+' : ''}\$${pl.toStringAsFixed(2)}',
                  style: _detailValueEmphasisStyle(context)?.copyWith(color: accent),
                ),
                Text(
                  '${plPct.toStringAsFixed(1)}%',
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
  });

  final DateTime? refreshedAt;
  final String Function(DateTime) relativeRefreshed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final t = refreshedAt;
    final text = t != null
        ? 'Value last refreshed ${relativeRefreshed(t)} · ${_fmtClock(t)}'
        : 'Value has not been refreshed yet — open Edit or pull collection refresh when available.';

    final theme = Theme.of(context);
    return Semantics(
      label: text,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.schedule, size: 18, color: colors.onSurface.withValues(alpha: 0.45)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.35,
                  color: colors.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
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

class _DailyRefreshBadge extends StatelessWidget {
  const _DailyRefreshBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      label: 'Auto-refreshed daily. Top 50 by value, updated every 24 hours automatically.',
      child: AdaptiveListCard(
        margin: EdgeInsets.zero,
        cornerRadius: 12,
        highlightBorderColor: colors.primary.withValues(alpha: 0.35),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.bolt, size: 20, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Auto-refreshed daily',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
                      ),
                    ),
                    Text(
                      'Top 50 by value — updated every 24 hours automatically',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriceCheckToggle extends StatelessWidget {
  const _PriceCheckToggle({required this.enabled, required this.onChanged});
  final bool enabled;
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = enabled ? _detailProfitColor(context) : colors.onSurface.withValues(alpha: 0.45);

    return Semantics(
      label: 'Weekly price check. Auto-refresh value every 7 days.',
      toggled: enabled,
      child: AdaptiveListCard(
        margin: EdgeInsets.zero,
        cornerRadius: 12,
        highlightBorderColor: enabled ? _detailProfitColor(context).withValues(alpha: 0.45) : null,
        color: enabled
            ? Color.alphaBlend(
                _detailProfitColor(context).withValues(alpha: theme.brightness == Brightness.dark ? 0.14 : 0.08),
                colors.surfaceContainerHighest,
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.schedule, size: 20, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Weekly price check',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: enabled ? _detailProfitColor(context) : colors.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                    Text(
                      'Auto-refresh value every 7 days',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: enabled,
                activeThumbColor: colors.primary,
                activeTrackColor: colors.primary.withValues(alpha: 0.35),
                onChanged: onChanged,
              ),
            ],
          ),
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

/// Circular liquid-glass nav chrome for the item-detail screen.
///
/// Has two visual treatments selected by [onDarkSurface]:
///   * `true`  — wine-tinted smoked plate, white icon. For sitting on the
///     burgundy hero (light/system blur stacks otherwise read as flat gray
///     on a dark red background).
///   * `false` — light frosted plate, dark icon. For when the hero has
///     scrolled away and the AppBar floats over the page background.
///
/// We crossfade two distinct subtrees with [AnimatedSwitcher] (keyed on
/// [onDarkSurface]) instead of animating decoration deltas. That keeps the
/// blur, gradient, border, and icon color all in lockstep on every flip.
class _GlassCircleIconButton extends StatelessWidget {
  const _GlassCircleIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.iconSize = 18,
    this.onDarkSurface = true,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final double iconSize;
  final bool onDarkSurface;

  static const double _size = 38;

  @override
  Widget build(BuildContext context) {
    final variant = KeyedSubtree(
      key: ValueKey<bool>(onDarkSurface),
      child: _GlassCircleVariant(
        icon: icon,
        iconSize: iconSize,
        onDarkSurface: onDarkSurface,
      ),
    );

    final button = SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeOut,
            child: variant,
          ),
          Material(
            color: Colors.transparent,
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(_size / 2),
              onTap: onPressed,
            ),
          ),
        ],
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

class _GlassCircleVariant extends StatelessWidget {
  const _GlassCircleVariant({
    required this.icon,
    required this.iconSize,
    required this.onDarkSurface,
  });

  final IconData icon;
  final double iconSize;
  final bool onDarkSurface;

  @override
  Widget build(BuildContext context) {
    const size = _GlassCircleIconButton._size;
    const r = size / 2;
    final outerRadius = BorderRadius.circular(r);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = theme.colorScheme;

    final List<Color> plateColors;
    final Color borderColor;
    final Color iconColor;
    final List<Color> highlightColors;
    final BoxShadow dropShadow;

    if (onDarkSurface) {
      plateColors = [
        const Color(0xFF5C0A20).withValues(alpha: 0.58),
        const Color(0xFF1A0508).withValues(alpha: 0.72),
      ];
      borderColor = Colors.white.withValues(alpha: 0.20);
      iconColor = Colors.white;
      highlightColors = [
        Colors.white.withValues(alpha: 0.14),
        Colors.white.withValues(alpha: 0.02),
        Colors.transparent,
      ];
      dropShadow = BoxShadow(
        color: Colors.black.withValues(alpha: 0.28),
        blurRadius: 10,
        offset: const Offset(0, 3),
      );
    } else {
      plateColors = isDark
          ? [
              Colors.white.withValues(alpha: 0.10),
              Colors.white.withValues(alpha: 0.06),
            ]
          : [
              Colors.white.withValues(alpha: 0.55),
              Colors.white.withValues(alpha: 0.40),
            ];
      borderColor = isDark
          ? Colors.white.withValues(alpha: 0.18)
          : Colors.black.withValues(alpha: 0.08);
      iconColor = colors.onSurface;
      highlightColors = isDark
          ? [
              Colors.white.withValues(alpha: 0.10),
              Colors.white.withValues(alpha: 0.02),
              Colors.transparent,
            ]
          : [
              Colors.white.withValues(alpha: 0.32),
              Colors.white.withValues(alpha: 0.10),
              Colors.transparent,
            ];
      dropShadow = BoxShadow(
        color: Colors.black.withValues(alpha: 0.10),
        blurRadius: 12,
        offset: const Offset(0, 3),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: outerRadius,
        boxShadow: [dropShadow],
      ),
      child: ClipRRect(
        borderRadius: outerRadius,
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: outerRadius,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: plateColors,
                  ),
                  border: Border.all(color: borderColor),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: outerRadius,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: highlightColors,
                      stops: const [0.0, 0.35, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: Icon(icon, size: iconSize, color: iconColor),
            ),
          ],
        ),
      ),
    );
  }
}
