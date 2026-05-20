import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/user_card.dart';
import '../../core/services/cards_service.dart';
import '../../core/theme/chrome_metrics.dart';
import '../../core/theme/fonts.dart';
import '../../core/widgets/app_bar_action_capsule.dart';
import '../../core/widgets/app_segmented_control.dart';
import '../../core/widgets/card_fan_loader.dart';
import '../../core/widgets/frosted_chrome_layer.dart';
import '../../core/widgets/glass_nav_bar.dart';
import '../../core/widgets/glass_search_field.dart';
import '../../core/widgets/sliver_frosted_header.dart';
import 'master_card_detail_screen.dart';

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

/// Set checklist grid — pushed route (same chrome pattern as [CollectionScreen] / Grading).
class SetChecklistScreen extends ConsumerStatefulWidget {
  const SetChecklistScreen({super.key, required this.args});
  final SetChecklistArgs args;

  @override
  ConsumerState<SetChecklistScreen> createState() => _SetChecklistScreenState();
}

class _SetChecklistScreenState extends ConsumerState<SetChecklistScreen> {
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

  Future<void> _onSlotTap(BuildContext context, _ChecklistRow row) async {
    if (row.owned && row.userCard != null) {
      context.push('/collection/card', extra: row.userCard);
      return;
    }

    final c = row.slot.card;
    final catalogMasterId = row.slot.masterCardId ?? c.id;
    final parallelName = widget.args.parallelName;
    SetParallel? parallel;
    try {
      final parallels =
          await ref.read(cardsServiceProvider).getParallels(widget.args.setId);
      parallel = resolveSetParallelForCatalog(parallels, parallelName);
    } catch (_) {
      // Fall through with unresolved parallel id.
    }

    if (!context.mounted) return;
    final resolvedId = await ref.read(cardsServiceProvider).ensureCatalogVariant(
          catalogVariantId: catalogMasterId,
          parallelId: parallel?.id,
        );
    if (!context.mounted) return;
    final displayCard =
        await ref.read(cardsServiceProvider).fetchMasterCardById(resolvedId);
    if (!context.mounted) return;
    final master = displayCard ??
        MasterCard(
          id: resolvedId,
          player: c.player,
          cardNumber: c.cardNumber,
          isRookie: c.isRookie,
          isAuto: c.isAuto || (parallel?.isAuto ?? false),
          isPatch: c.isPatch,
          isSSP: c.isSSP,
          serialMax: parallel?.serialMax ?? c.serialMax,
          imageUrl: c.imageUrl,
          guidePriceCardId: c.guidePriceCardId,
          gain: c.gain,
        );

    context.push(
      '/catalog/master',
      extra: MasterCardDetailArgs(
        masterCard: MasterCard(
          id: master.id,
          player: master.player,
          cardNumber: master.cardNumber,
          isRookie: master.isRookie,
          isAuto: master.isAuto || (parallel?.isAuto ?? false),
          isPatch: master.isPatch,
          isSSP: master.isSSP,
          serialMax: parallel?.serialMax ?? master.serialMax,
          imageUrl: master.imageUrl,
          guidePriceCardId: master.guidePriceCardId,
          gain: master.gain,
        ),
        parallelName: parallelName,
        parallelSerialMax: parallel?.serialMax,
        parallelIsAuto: parallel?.isAuto ?? false,
        releaseName: widget.args.releaseName,
        setName: widget.args.setName,
        year: widget.args.year,
        setId: widget.args.setId,
        parallelId: parallel?.id,
      ),
    );
  }

  Widget _buildCountRow(ColorScheme colors, String countLabel) {
    final releaseSubtitle = _releaseSubtitle;
    final metaStyle = TextStyle(
      fontSize: 12,
      color: colors.onSurface.withValues(alpha: 0.5),
    );

    return Padding(
      padding: ChromeMetrics.listCountPadding(
        bottom: ChromeMetrics.listCountBottomInsetRoomy,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(countLabel, style: metaStyle),
          ),
          if (releaseSubtitle != null) ...[
            const SizedBox(width: 12),
            Text(
              releaseSubtitle,
              style: metaStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterControls(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ChromeMetrics.compactHorizontalInset,
        ChromeMetrics.segmentOnlyTopInset,
        ChromeMetrics.compactHorizontalInset,
        ChromeMetrics.searchBarBottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSegmentedControl(
            segmentKey: const ValueKey('set-checklist-filter'),
            labels: const ['All', 'Owned', 'Missing'],
            selectedIndex: _filter.index,
            onValueChanged: (i) => setState(() => _filter = _ChecklistFilter.values[i]),
            color: colors.primary,
          ),
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

  Widget _buildPinnedFilters(ColorScheme colors, double navOffset) {
    return FrostedChromeLayer(
      child: Padding(
        padding: EdgeInsets.only(top: navOffset),
        child: _buildFilterControls(colors),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ColorScheme colors) {
    // No app-bar backdrop blur — one [FrostedChromeLayer] in the pinned sliver
    // (same as [CollectionScreen]) avoids a seam above the segment row.
    return buildGlassNavBar(
      context,
      useBlurBackground: false,
      automaticallyImplyLeading: false,
      centerTitle: false,
      leading: AppBarGlassCircleButton(
        onPressed: () => context.pop(),
        icon: Icons.chevron_left,
      ),
      title: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          _title,
          style: AppFonts.appBarTitle.copyWith(color: colors.onSurface),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildScrollContent(
    ColorScheme colors,
    double navOffset,
    List<Widget> bodySlivers,
  ) {
    return CustomScrollView(
      physics: const ClampingScrollPhysics(),
      cacheExtent: 600,
      slivers: [
        SliverFrostedHeader(
          height: navOffset + ChromeMetrics.segmentSearchHeaderExtent,
          child: _buildPinnedFilters(colors, navOffset),
        ),
        const SliverChromeGap(height: ChromeMetrics.contentTopGapTight),
        ...bodySlivers,
        const SliverToBoxAdapter(child: SizedBox(height: _scrollEndCushion)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final navOffset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final slotsAsync = ref.watch(_setChecklistSlotsProvider(widget.args));
    final userCardsAsync = ref.watch(userCardsProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(colors),
      body: slotsAsync.when(
        loading: () => _buildScrollContent(
          colors,
          navOffset,
          const [
            SliverFillRemaining(
              hasScrollBody: true,
              child: Center(child: CardFanLoader()),
            ),
          ],
        ),
        error: (e, _) => _buildScrollContent(
          colors,
          navOffset,
          [
            SliverFillRemaining(
              hasScrollBody: true,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load checklist.\n$e',
                    textAlign: TextAlign.center,
                  ),
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
            return _buildScrollContent(
              colors,
              navOffset,
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
          return _buildChecklistGrid(context, colors, navOffset, slots, userCards);
        },
      ),
    );
  }

  Widget _buildChecklistGrid(
    BuildContext context,
    ColorScheme colors,
    double navOffset,
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

    return _buildScrollContent(
      colors,
      navOffset,
      [
        SliverToBoxAdapter(child: _buildCountRow(colors, countLabel)),
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
                (context, i) => _ChecklistGridTile(
                  row: visible[i],
                  onTap: () => _onSlotTap(context, visible[i]),
                ),
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
  const _ChecklistGridTile({required this.row, required this.onTap});
  final _ChecklistRow row;
  final VoidCallback onTap;

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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
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
