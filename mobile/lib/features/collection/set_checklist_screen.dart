import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../../core/models/user_card.dart';
import '../../core/services/cards_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/chrome_metrics.dart';
import '../../core/theme/fonts.dart';
import '../../core/utils/adaptive_ui.dart';
import '../../core/widgets/card_fan_loader.dart';
import '../../core/widgets/glass_search_field.dart';
import '../../core/widgets/sliver_frosted_header.dart';

/// Opens the set checklist in a tall bottom sheet.
Future<void> showSetChecklistSheet(BuildContext context, SetChecklistArgs args) {
  return showAdaptiveSheet<void>(
    context: context,
    builder: (sheetContext) {
      final sheetHeight = MediaQuery.sizeOf(sheetContext).height * 0.92;
      return SizedBox(
        height: sheetHeight,
        child: SetChecklistSheet(args: args),
      );
    },
  );
}

int _gridCrossAxisCount(double width) {
  const pad = 16.0;
  const spacing = 8.0;
  const minTileWidth = 68.0;
  final inner = width - pad * 2;
  return (inner / (minTileWidth + spacing)).floor().clamp(4, 5);
}

int _compareCardNumbers(String? a, String? b) {
  String norm(String? s) => (s ?? '').trim().replaceFirst(RegExp(r'^#'), '');
  final na = norm(a);
  final nb = norm(b);
  if (na.isEmpty && nb.isEmpty) return 0;
  if (na.isEmpty) return 1;
  if (nb.isEmpty) return -1;

  int? leadingInt(String s) {
    final direct = int.tryParse(s);
    if (direct != null) return direct;
    final m = RegExp(r'^(\d+)').firstMatch(s);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  final ia = leadingInt(na);
  final ib = leadingInt(nb);
  if (ia != null && ib != null && ia != ib) return ia.compareTo(ib);
  if (ia != null && ib == null) return -1;
  if (ia == null && ib != null) return 1;
  return na.toLowerCase().compareTo(nb.toLowerCase());
}

class SetChecklistArgs {
  const SetChecklistArgs({
    required this.setId,
    required this.setName,
    this.releaseName,
    this.year,
    this.parallelName = 'Base',
  });

  final String setId;
  final String setName;
  final String? releaseName;
  final int? year;
  final String parallelName;
}

enum _ChecklistFilter { all, owned, missing }

bool _parallelMatches(String cardParallel, String targetParallel) {
  final card = cardParallel.trim().isEmpty ? 'Base' : cardParallel.trim();
  final target = targetParallel.trim().isEmpty ? 'Base' : targetParallel.trim();
  return card.toLowerCase() == target.toLowerCase();
}

class SetChecklistSheet extends ConsumerStatefulWidget {
  const SetChecklistSheet({super.key, required this.args});
  final SetChecklistArgs args;

  @override
  ConsumerState<SetChecklistSheet> createState() => _SetChecklistSheetState();
}

class _SetChecklistSheetState extends ConsumerState<SetChecklistSheet> {
  static const double _filterTopInset = 4;
  static const double _scrollEndCushion = 32;

  final _searchCtrl = TextEditingController();
  String _query = '';
  _ChecklistFilter _filter = _ChecklistFilter.all;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String get _title {
    var title = widget.args.setName;
    if (widget.args.parallelName != 'Base') {
      title = '$title · ${widget.args.parallelName}';
    }
    return title;
  }

  String? get _releaseSubtitle {
    final parts = <String>[
      if (widget.args.year != null) '${widget.args.year}',
      if (widget.args.releaseName != null) widget.args.releaseName!,
    ];
    return parts.isEmpty ? null : parts.join(' ');
  }

  Widget _buildSheetHeader(ColorScheme colors) {
    final releaseSubtitle = _releaseSubtitle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: colors.outline.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      style: AppFonts.appBarTitle.copyWith(color: colors.onSurface),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (releaseSubtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        releaseSubtitle,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.2,
                          color: colors.onSurface.withValues(alpha: 0.55),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              AdaptiveButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icons.close,
                style: AdaptiveButtonStyle.glass,
                iconColor: colors.onSurface,
                size: AdaptiveButtonSize.small,
                minSize: const Size(46, 46),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Native iOS 26 [UiKitView] segments break in modal sheets (layout + compositing).
  /// [GlassSegmentedControl] matches the liquid-glass look without a platform view.
  Widget _buildFilterSegments(ColorScheme colors) {
    final segmentHeight = ChromeMetrics.segmentControlHeight;
    return GlassSegmentedControl(
      segments: const ['All', 'Owned', 'Missing'],
      selectedIndex: _filter.index,
      onSegmentSelected: (i) => setState(() => _filter = _ChecklistFilter.values[i]),
      height: segmentHeight,
      borderRadius: segmentHeight / 2,
      // No backdrop blur parent in this sheet — segment glass is self-contained.
      useOwnLayer: true,
      backgroundColor: AppTheme.segmentedTrackBackground(context),
      indicatorColor: colors.primary,
      selectedTextStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: colors.onPrimary,
      ),
      unselectedTextStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: colors.onSurface.withValues(alpha: 0.65),
      ),
    );
  }

  Widget _buildFilterChromeContent(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ChromeMetrics.compactHorizontalInset,
        _filterTopInset,
        ChromeMetrics.compactHorizontalInset,
        ChromeMetrics.searchBarBottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFilterSegments(colors),
          const SizedBox(height: ChromeMetrics.segmentToSearchGap),
          GlassSearchField(
            controller: _searchCtrl,
            hint: 'Search player or #',
            onChanged: (v) => setState(() => _query = v),
          ),
        ],
      ),
    );
  }

  /// Grid only — filters are a fixed sibling above [Expanded], not an overlay, so
  /// scroll content never passes under [BackdropFilter].
  Widget _buildScrollArea(ColorScheme colors, List<Widget> bodySlivers) {
    return ColoredBox(
      color: colors.surface,
      child: CustomScrollView(
        physics: const ClampingScrollPhysics(),
        cacheExtent: 600,
        slivers: [
          ...bodySlivers,
          const SliverToBoxAdapter(child: SizedBox(height: _scrollEndCushion)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final slotsAsync = ref.watch(_setChecklistSlotsProvider(widget.args));
    final userCardsAsync = ref.watch(userCardsProvider);

    return Material(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSheetHeader(colors),
          ColoredBox(
            color: colors.surface,
            child: _buildFilterChromeContent(colors),
          ),
          Expanded(
            child: slotsAsync.when(
              loading: () => _buildScrollArea(
                colors,
                const [
                  SliverFillRemaining(
                    hasScrollBody: true,
                    child: Center(child: CardFanLoader()),
                  ),
                ],
              ),
              error: (e, _) => _buildScrollArea(
                colors,
                [
                  SliverFillRemaining(
                    hasScrollBody: true,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('Could not load checklist.\n$e', textAlign: TextAlign.center),
                      ),
                    ),
                  ),
                ],
              ),
              data: (slots) {
                final userCards = userCardsAsync.maybeWhen(
                  data: (cards) => cards,
                  orElse: () => const <UserCard>[],
                );
                if (userCardsAsync.hasError) {
                  return _buildScrollArea(
                    colors,
                    [
                      SliverFillRemaining(
                        hasScrollBody: true,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('Could not load collection.\n${userCardsAsync.error}'),
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return _buildScrollBody(context, colors, slots, userCards);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollBody(
    BuildContext context,
    ColorScheme colors,
    List<SetChecklistSlot> slots,
    List<UserCard> userCards,
  ) {
    final ownedByMaster = <String, UserCard>{};
    for (final c in userCards) {
      if (c.setId != widget.args.setId) continue;
      if (!_parallelMatches(c.parallel, widget.args.parallelName)) continue;
      final mid = c.masterCardId;
      if (mid == null || mid.isEmpty) continue;
      ownedByMaster.putIfAbsent(mid, () => c);
    }

    final rows = slots.map((slot) {
      final owned = slot.masterCardId != null && ownedByMaster.containsKey(slot.masterCardId);
      return _ChecklistRow(
        slot: slot,
        owned: owned,
        userCard: owned ? ownedByMaster[slot.masterCardId] : null,
      );
    }).toList()
      ..sort((a, b) {
        final byNum = _compareCardNumbers(a.slot.card.cardNumber, b.slot.card.cardNumber);
        if (byNum != 0) return byNum;
        return a.slot.card.player.toLowerCase().compareTo(b.slot.card.player.toLowerCase());
      });

    var visible = List<_ChecklistRow>.from(rows);
    if (_filter == _ChecklistFilter.owned) {
      visible = visible.where((r) => r.owned).toList();
    } else if (_filter == _ChecklistFilter.missing) {
      visible = visible.where((r) => !r.owned).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      visible = visible.where((r) {
        final c = r.slot.card;
        return c.player.toLowerCase().contains(q) ||
            (c.cardNumber?.toLowerCase().contains(q) ?? false);
      }).toList();
    }

    final ownedCount = rows.where((r) => r.owned).length;
    final total = rows.length;
    final crossAxisCount = _gridCrossAxisCount(MediaQuery.sizeOf(context).width);
    final bottomPad = MediaQuery.paddingOf(context).bottom + 16;
    final countLabel =
        '$ownedCount of $total collected'
        '${visible.length != rows.length ? ' · ${visible.length} shown' : ''}';

    return _buildScrollArea(
      colors,
      [
        const SliverChromeGap(height: ChromeMetrics.contentTopGapTight),
        SliverToBoxAdapter(
          child: Padding(
            padding: ChromeMetrics.listCountPadding(
              bottom: ChromeMetrics.listCountBottomInsetRoomy,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                countLabel,
                style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ),
        if (visible.isEmpty)
          SliverFillRemaining(
            hasScrollBody: true,
            child: Center(
              child: Text(
                _filter == _ChecklistFilter.owned
                    ? 'No owned cards match.'
                    : _filter == _ChecklistFilter.missing
                        ? 'Nothing missing — nice!'
                        : 'No cards match your search.',
                style: TextStyle(color: colors.onSurface.withValues(alpha: 0.5)),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.68,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => _ChecklistGridTile(row: visible[i]),
                childCount: visible.length,
              ),
            ),
          ),
      ],
    );
  }
}

class _ChecklistRow {
  const _ChecklistRow({required this.slot, required this.owned, this.userCard});
  final SetChecklistSlot slot;
  final bool owned;
  final UserCard? userCard;
}

final _setChecklistSlotsProvider = FutureProvider.family<List<SetChecklistSlot>, SetChecklistArgs>(
  (ref, args) => ref.watch(cardsServiceProvider).fetchSetChecklistSlots(
        setId: args.setId,
        parallelName: args.parallelName,
      ),
);

class _ChecklistGridTile extends StatelessWidget {
  const _ChecklistGridTile({required this.row});
  final _ChecklistRow row;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final card = row.slot.card;
    final label = card.cardNumber != null ? '#${card.cardNumber}' : card.player;

    Widget imageChild;
    if (card.imageUrl != null && card.imageUrl!.isNotEmpty) {
      imageChild = CachedNetworkImage(
        imageUrl: card.imageUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        color: row.owned ? null : Colors.grey,
        colorBlendMode: row.owned ? null : BlendMode.saturation,
        errorWidget: (_, _, _) => _PlaceholderFace(colors: colors, label: label, muted: !row.owned),
      );
    } else {
      imageChild = _PlaceholderFace(colors: colors, label: label, muted: !row.owned);
    }

    final tile = Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: ColoredBox(
            color: colors.surfaceContainerHighest.withValues(alpha: row.owned ? 0.35 : 0.55),
            child: imageChild,
          ),
        ),
        if (!row.owned)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: ColoredBox(color: Colors.white.withValues(alpha: 0.28)),
          ),
        if (row.owned)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.green.shade600,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(Icons.check, size: 12, color: Colors.white),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: row.owned ? 0.55 : 0.4),
                ],
              ),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: row.owned ? 1 : 0.85),
              ),
            ),
          ),
        ),
      ],
    );

    if (!row.owned || row.userCard == null) {
      return tile;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          Navigator.of(context).pop();
          context.push('/collection/card', extra: row.userCard);
        },
        child: tile,
      ),
    );
  }
}

class _PlaceholderFace extends StatelessWidget {
  const _PlaceholderFace({
    required this.colors,
    required this.label,
    required this.muted,
  });

  final ColorScheme colors;
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Text(
          label,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            height: 1.15,
            color: colors.onSurface.withValues(alpha: muted ? 0.35 : 0.55),
          ),
        ),
      ),
    );
  }
}
