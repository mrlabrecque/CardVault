import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart' hide showAdaptiveDialog;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/user_card.dart';
import '../../core/theme/fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/adaptive_dropdown.dart';
import '../../core/widgets/adaptive_list_card.dart';
import '../../core/widgets/modal_sheet_scaffold.dart';
import '../../core/services/cards_service.dart';
import '../../core/utils/adaptive_ui.dart';
import 'widgets/card_detail_view.dart';
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

    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => _close(context),
          tooltip: 'Back',
          style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
        ),
        title: Text(
          card.player,
          style: AppFonts.appBarTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
            onPressed: () => _delete(card),
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPad),
        children: [
                CardDetailView(
                  userCard: card,
                  sections: const [CardDetailSection.hero],
                ),
                const SizedBox(height: 20),

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
                      Row(
                        children: [
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text(
                                'Your copy',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _openEditSheet(card),
                            style: TextButton.styleFrom(
                              foregroundColor: colors.primary,
                              minimumSize: const Size(44, 44),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            child: const Text('Edit'),
                          ),
                        ],
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
