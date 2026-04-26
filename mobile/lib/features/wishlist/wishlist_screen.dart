import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/auth/auth_service.dart';
import '../../core/models/wishlist_item.dart';
import '../../core/widgets/attr_tag.dart';
import '../../core/widgets/serial_tag.dart';
import '../../core/widgets/sticky_sub_header_layout.dart';
import '../collection/widgets/filter_sort_action_bar.dart';

// ── eBay query builder ─────────────────────────────────────────────────────────

String buildEbayQuery({
  String? player,
  int? year,
  String? setName,
  String? parallel,
  String? cardNumber,
  String? grade,
  int? serialMax,
  bool isRookie = false,
  bool isAuto = false,
  bool isPatch = false,
}) {
  final parts = <String>[];
  if (year != null) parts.add('$year');
  if (setName?.isNotEmpty == true) parts.add(setName!);
  if (player?.isNotEmpty == true) parts.add(player!);
  if (cardNumber?.isNotEmpty == true) parts.add('#$cardNumber');
  final parallelLabel = (parallel ?? '').replaceAll(RegExp(r'\s*/\d+$'), '').trim();
  if (parallelLabel.isNotEmpty && parallelLabel.toLowerCase() != 'base') parts.add(parallelLabel);
  if (isAuto) parts.add('Auto');
  if (isPatch) parts.add('Patch');
  if (serialMax != null) parts.add('/$serialMax');
  if (isRookie) parts.add('RC');
  if (grade?.isNotEmpty == true) parts.add(grade!);
  return parts.where((p) => p.isNotEmpty).join(' ');
}

// ── Provider ───────────────────────────────────────────────────────────────────

final wishlistProvider =
    AsyncNotifierProvider<WishlistNotifier, List<WishlistItem>>(
  WishlistNotifier.new,
);

class WishlistNotifier extends AsyncNotifier<List<WishlistItem>> {
  @override
  Future<List<WishlistItem>> build() async {
    final supabase = ref.read(supabaseProvider);
    final data = await supabase
        .from('wishlist')
        .select('*, wishlist_matches(*)')
        .order('created_at', ascending: false);
    return (data as List)
        .map((r) => WishlistItem.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> togglePause(String id) async {
    final items = state.value ?? [];
    final item = items.firstWhere((i) => i.id == id);
    final next = item.isPaused ? 'active' : 'paused';
    _updateItem(id, (i) => i.copyWith(alertStatus: next));
    await ref.read(supabaseProvider)
        .from('wishlist')
        .update({'alert_status': next})
        .eq('id', id);
  }

  Future<void> remove(String id) async {
    _removeItem(id);
    await ref.read(supabaseProvider).from('wishlist').delete().eq('id', id);
  }

  Future<void> dismissMatch(String wishlistId, String matchId) async {
    _updateItem(wishlistId, (item) {
      final matches = item.matches.where((m) => m.id != matchId).toList();
      final lowestPrice = matches.isEmpty
          ? null
          : matches.map((m) => m.price).reduce((a, b) => a < b ? a : b);
      return item.copyWith(
        matches: matches,
        alertStatus: matches.isEmpty ? 'active' : item.alertStatus,
        lastSeenPrice: lowestPrice,
      );
    });
    await ref.read(supabaseProvider)
        .from('wishlist_matches')
        .delete()
        .eq('id', matchId);
  }

  void _updateItem(String id, WishlistItem Function(WishlistItem) updater) {
    state = state.whenData(
      (items) => items.map((i) => i.id == id ? updater(i) : i).toList(),
    );
  }

  void _removeItem(String id) {
    state = state.whenData((items) => items.where((i) => i.id != id).toList());
  }

  Future<({int checked, int triggered, String? error})> checkNow() async {
    try {
      final res = await ref.read(supabaseProvider).functions.invoke('wishlist-check-now');
      if (res.status != 200) {
        final err = (res.data as Map<String, dynamic>?)?['error'] as String? ?? 'Failed';
        return (checked: 0, triggered: 0, error: err);
      }
      final body = res.data as Map<String, dynamic>;
      await reload();
      return (
        checked: body['checked'] as int? ?? 0,
        triggered: body['triggered'] as int? ?? 0,
        error: null,
      );
    } catch (e) {
      return (checked: 0, triggered: 0, error: e.toString());
    }
  }

  Future<void> add(Map<String, dynamic> data) async {
    final userId = ref.read(supabaseProvider).auth.currentUser?.id;
    await ref.read(supabaseProvider).from('wishlist').insert({...data, 'user_id': userId});
    await reload();
  }

  Future<void> patch(String id, Map<String, dynamic> data) async {
    await ref.read(supabaseProvider).from('wishlist').update(data).eq('id', id);
    await reload();
  }
}

// ── Screen ─────────────────────────────────────────────────────────────────────

class WishlistScreen extends ConsumerStatefulWidget {
  const WishlistScreen({super.key});

  @override
  ConsumerState<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends ConsumerState<WishlistScreen> {
  final _searchCtrl = TextEditingController();
  final _expandedMatches = <String>{};
  String? _deletingId;
  String _searchQuery = '';
  final Set<String> _activeFilters = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleFilter(String f) => setState(() {
    _activeFilters.contains(f) ? _activeFilters.remove(f) : _activeFilters.add(f);
  });

  List<WishlistItem> _filterItems(List<WishlistItem> items) {
    if (_searchQuery.isEmpty && _activeFilters.isEmpty) return items;
    final q = _searchQuery.toLowerCase();
    return items.where((item) {
      if (q.isNotEmpty) {
        final matches = (item.player?.toLowerCase().contains(q) ?? false) ||
            (item.setName?.toLowerCase().contains(q) ?? false) ||
            (item.parallel?.toLowerCase().contains(q) ?? false) ||
            (item.cardNumber?.toLowerCase().contains(q) ?? false);
        if (!matches) return false;
      }
      if (_activeFilters.contains('DEAL FOUND') && item.matches.isEmpty) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(wishlistProvider);

    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) => RefreshIndicator(
          onRefresh: () => ref.read(wishlistProvider.notifier).reload(),
          child: items.isEmpty ? _buildEmpty() : _buildList(items),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      children: [
        const SizedBox(height: 64),
        Column(
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: colors.outline.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(Icons.bookmark_border, size: 28, color: colors.onSurface.withValues(alpha: 0.3)),
            ),
            const SizedBox(height: 16),
            Text('No cards on your wishlist',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.onSurface)),
            const SizedBox(height: 4),
            Text('Add cards to watch for deals on eBay.',
                style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.5))),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _showWishlistForm(context, ref),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: Text('Add a Card', style: TextStyle(fontWeight: FontWeight.w600, color: colors.onPrimary)),
            ),
          ],
        ),
      ],
    );
  }


  Widget _buildList(List<WishlistItem> items) {
    final filtered = _filterItems(items);

    return StickySubHeaderLayout(
      header: const SizedBox.shrink(),
      subHeader: FilterSortActionBar<String>(
        searchText: _searchQuery,
        onSearchChanged: (v) => setState(() => _searchQuery = v),
        onSearchClear: () {
          _searchCtrl.clear();
          setState(() => _searchQuery = '');
        },
        searchHint: 'Search player, set, card #…',
        filters: const ['DEAL FOUND'],
        activeFilters: _activeFilters,
        onFilterToggle: _toggleFilter,
        actionButton: const SizedBox.shrink(),
      ),
      label: null,
      body: filtered.isEmpty
          ? Center(
              child: Text(
                _searchQuery.isNotEmpty ? 'No cards match your search.' : 'No wishlist items yet.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final item = filtered[i];
                return _WishlistCard(
                  item: item,
                  isMatchesExpanded: _expandedMatches.contains(item.id),
                  isDeleting: _deletingId == item.id,
                  onToggleMatches: () => setState(() {
                    _expandedMatches.contains(item.id)
                        ? _expandedMatches.remove(item.id)
                        : _expandedMatches.add(item.id);
                  }),
                  onEdit: () => _showWishlistForm(context, ref, editing: item),
                  onSearchComps: () {
                    final base = item.ebayQuery ?? item.player ?? '';
                    final exclusions = item.excludeTerms.map((t) => '-"$t"').join(' ');
                    final q = exclusions.isNotEmpty ? '$base $exclusions' : base;
                    context.go('/comps?q=${Uri.encodeComponent(q)}');
                  },
                  onTogglePause: () => ref.read(wishlistProvider.notifier).togglePause(item.id),
                  onDelete: () async {
                    setState(() => _deletingId = item.id);
                    await ref.read(wishlistProvider.notifier).remove(item.id);
                    setState(() => _deletingId = null);
                  },
                  onDismissMatch: (matchId) =>
                      ref.read(wishlistProvider.notifier).dismissMatch(item.id, matchId),
                );
              },
            ),
    );
  }

  void _showWishlistForm(BuildContext context, WidgetRef ref, {WishlistItem? editing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WishlistFormSheet(
        editing: editing,
        onSave: (data) async {
          try {
            if (editing != null) {
              await ref.read(wishlistProvider.notifier).patch(editing.id, data);
            } else {
              await ref.read(wishlistProvider.notifier).add(data);
            }
            return null;
          } catch (e) {
            return e.toString();
          }
        },
      ),
    );
  }

}

// ── Item card ──────────────────────────────────────────────────────────────────

class _WishlistCard extends StatelessWidget {
  const _WishlistCard({
    required this.item,
    required this.isMatchesExpanded,
    required this.isDeleting,
    required this.onToggleMatches,
    required this.onEdit,
    required this.onSearchComps,
    required this.onTogglePause,
    required this.onDelete,
    required this.onDismissMatch,
  });

  final WishlistItem item;
  final bool isMatchesExpanded;
  final bool isDeleting;
  final VoidCallback onToggleMatches;
  final VoidCallback onEdit;
  final VoidCallback onSearchComps;
  final VoidCallback onTogglePause;
  final VoidCallback onDelete;
  final void Function(String matchId) onDismissMatch;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final triggered = item.isTriggered;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: triggered ? colors.surface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: triggered ? colors.primary : colors.outline.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Deal Found banner
          if (triggered) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(
                children: [
                  Icon(Icons.local_offer, color: colors.onPrimary, size: 14),
                  const SizedBox(width: 8),
                  Text('Deal Found!', style: TextStyle(color: colors.onPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (item.savings > 0)
                    Text('\$${item.savings.toStringAsFixed(0)} under target',
                        style: TextStyle(color: colors.onPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Main content row: left (info) + right (badge/edit + prices)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left side: player, set, parallel, attributes
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(text: item.player ?? 'Unknown', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              if (item.cardNumber != null)
                                TextSpan(
                                  text: '  #${item.cardNumber}',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: colors.onSurface.withValues(alpha: 0.5)),
                                ),
                            ]),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                          if (item.year != null || item.setName != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              [if (item.year != null) '${item.year}', if (item.setName != null) item.setName!].join(' · '),
                              style: TextStyle(fontSize: 11, color: colors.onSurface.withValues(alpha: 0.5)),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (item.parallel != null || item.attrs.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 4, runSpacing: 4,
                              children: [
                                if (item.parallel != null && item.parallel != 'Base')
                                  Text(item.parallel!, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: colors.primary)),
                                for (final tag in item.attrs)
                                  AttrTag(tag, color: _attrColor(tag)),
                                if (item.serialMax != null)
                                  SerialTag(serialMax: item.serialMax),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Right side: badge + edit, then prices
                    SizedBox(
                      width: 130,
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Top: badge + edit
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!triggered)
                              _StatusBadge(status: item.alertStatus, colors: colors),
                            if (!triggered)
                              const SizedBox(width: 6),
                            GestureDetector(
                              onTap: onEdit,
                              child: Icon(Icons.edit_outlined, size: 18, color: colors.onSurface.withValues(alpha: 0.4)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Price boxes (inline)
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          alignment: WrapAlignment.end,
                          children: [
                            if (item.targetPrice != null)
                              _PriceBox(colors: colors, label: 'Target', value: '\$${item.targetPrice!.toStringAsFixed(2)}'),
                            if (item.lastSeenPrice != null)
                              _PriceBox(
                                colors: colors,
                                label: 'Best',
                                value: '\$${item.lastSeenPrice!.toStringAsFixed(2)}',
                                highlight: triggered,
                              ),
                            _PriceBox(colors: colors, label: 'Grade', value: item.grade?.isNotEmpty == true ? item.grade! : 'Any'),
                          ],
                        ),
                      ],
                    ),
                    ),
                  ],
                ),

                // Active listings section
                if (triggered && item.matches.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Divider(height: 1, color: colors.outline.withValues(alpha: 0.2)),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: onToggleMatches,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${item.matches.length} active listing${item.matches.length == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.onSurface.withValues(alpha: 0.7)),
                        ),
                        Icon(isMatchesExpanded ? Icons.expand_less : Icons.expand_more, size: 16, color: colors.onSurface.withValues(alpha: 0.5)),
                      ],
                    ),
                  ),
                  if (isMatchesExpanded) ...[
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        children: [
                          for (int i = 0; i < item.matches.length; i++) ...[
                            _MatchRow(
                              match: item.matches[i],
                              colors: colors,
                              onDismiss: () => onDismissMatch(item.matches[i].id),
                            ),
                            if (i < item.matches.length - 1)
                              Divider(height: 1, color: colors.outline.withValues(alpha: 0.1)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],

                // Action buttons
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onSearchComps,
                        icon: Icon(Icons.search, size: 13, color: colors.onSurface.withValues(alpha: 0.6)),
                        label: Text('Comps', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.onSurface.withValues(alpha: 0.7))),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          side: BorderSide(color: colors.outline.withValues(alpha: 0.3)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onTogglePause,
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          border: Border.all(color: colors.outline.withValues(alpha: 0.3)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(item.isPaused ? Icons.play_arrow : Icons.pause, size: 16, color: colors.onSurface.withValues(alpha: 0.5)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onDelete,
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          border: Border.all(color: colors.error.withValues(alpha: 0.3)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: isDeleting
                            ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: colors.error))
                            : Icon(Icons.delete_outline, size: 16, color: colors.error.withValues(alpha: 0.6)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _attrColor(String tag) => switch (tag) {
    'RC'   => const Color(0xFF16A34A),
    'AUTO' => const Color(0xFF7C3AED),
    'PATCH'=> const Color(0xFF0369A1),
    _      => const Color(0xFF6B7280),
  };
}

// ── Match row ──────────────────────────────────────────────────────────────────

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match, required this.colors, required this.onDismiss});
  final WishlistMatch match;
  final ColorScheme colors;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final isAuction = match.listingType == 'AUCTION';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (match.imageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(match.imageUrl!, width: 36, height: 48, fit: BoxFit.cover,
                  errorBuilder: (ctx, err, st) => const SizedBox(width: 36, height: 48)),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(match.title,
                    style: const TextStyle(fontSize: 11, color: Colors.black87),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(isAuction ? 'Auction' : 'Buy Now',
                        style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w600,
                            color: isAuction ? const Color(0xFF9333EA) : const Color(0xFF2563EB))),
                    if (match.url != null) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => launchUrl(Uri.parse(match.url!), mode: LaunchMode.externalApplication),
                        child: Icon(Icons.open_in_new, size: 11, color: colors.onSurface.withValues(alpha: 0.4)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('\$${match.price.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.primary)),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: onDismiss,
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.error.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.close, size: 14, color: colors.error.withValues(alpha: 0.6)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Small helpers ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.colors});
  final String status;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      'active'    => ('Watching', colors.primary.withValues(alpha: 0.15), colors.primary),
      'triggered' => ('Below Target!', colors.error.withValues(alpha: 0.15), colors.error),
      'paused'    => ('Paused', colors.outline.withValues(alpha: 0.1), colors.onSurface.withValues(alpha: 0.5)),
      _           => ('Unknown', colors.outline.withValues(alpha: 0.1), colors.onSurface.withValues(alpha: 0.5)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class _PriceBox extends StatelessWidget {
  const _PriceBox({
    required this.colors,
    required this.label,
    required this.value,
    this.highlight = false,
  });
  final ColorScheme colors;
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: highlight ? colors.primary.withValues(alpha: 0.1) : colors.surface,
        border: Border.all(color: highlight ? colors.primary.withValues(alpha: 0.3) : colors.outline.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 7, fontWeight: FontWeight.w600, color: colors.onSurface.withValues(alpha: 0.4), letterSpacing: 0.2)),
          const SizedBox(height: 1),
          Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: highlight ? colors.primary : colors.onSurface)),
        ],
      ),
    );
  }
}

// ── Wishlist form sheet ─────────────────────────────────────────────────────────

class _WishlistFormSheet extends StatefulWidget {
  const _WishlistFormSheet({this.editing, required this.onSave});
  final WishlistItem? editing;
  final Future<String?> Function(Map<String, dynamic>) onSave;

  @override
  State<_WishlistFormSheet> createState() => _WishlistFormSheetState();
}

class _WishlistFormSheetState extends State<_WishlistFormSheet> {
  late final TextEditingController _playerCtrl;
  late final TextEditingController _yearCtrl;
  late final TextEditingController _cardNumCtrl;
  late final TextEditingController _setCtrl;
  late final TextEditingController _parallelCtrl;
  late final TextEditingController _gradeCtrl;
  late final TextEditingController _queryCtrl;
  late final TextEditingController _excludeCtrl;
  late final TextEditingController _targetPriceCtrl;
  late final TextEditingController _serialMaxCtrl;

  bool _isRookie = false;
  bool _isAuto = false;
  bool _isPatch = false;
  List<String> _excludeTerms = [];
  bool _queryEdited = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _playerCtrl     = TextEditingController(text: e?.player ?? '');
    _yearCtrl       = TextEditingController(text: e?.year != null ? '${e!.year}' : '');
    _cardNumCtrl    = TextEditingController(text: e?.cardNumber ?? '');
    _setCtrl        = TextEditingController(text: e?.setName ?? '');
    _parallelCtrl   = TextEditingController(text: e?.parallel ?? '');
    _gradeCtrl      = TextEditingController(text: e?.grade ?? '');
    _queryCtrl      = TextEditingController(text: e?.ebayQuery ?? '');
    _excludeCtrl    = TextEditingController();
    _targetPriceCtrl = TextEditingController(
      text: e?.targetPrice != null ? e!.targetPrice!.toStringAsFixed(2) : '',
    );
    _serialMaxCtrl  = TextEditingController(
      text: e?.serialMax != null ? '${e!.serialMax}' : '',
    );
    _isRookie     = e?.isRookie ?? false;
    _isAuto       = e?.isAuto ?? false;
    _isPatch      = e?.isPatch ?? false;
    _excludeTerms = [...(e?.excludeTerms ?? [])];
    if (e?.ebayQuery?.isEmpty != false) _rebuildQuery();
  }

  @override
  void dispose() {
    _playerCtrl.dispose();
    _yearCtrl.dispose();
    _cardNumCtrl.dispose();
    _setCtrl.dispose();
    _parallelCtrl.dispose();
    _gradeCtrl.dispose();
    _queryCtrl.dispose();
    _excludeCtrl.dispose();
    _targetPriceCtrl.dispose();
    _serialMaxCtrl.dispose();
    super.dispose();
  }

  void _rebuildQuery() {
    if (_queryEdited) return;
    _queryCtrl.text = buildEbayQuery(
      player:    _playerCtrl.text,
      year:      int.tryParse(_yearCtrl.text),
      setName:   _setCtrl.text,
      parallel:  _parallelCtrl.text,
      cardNumber: _cardNumCtrl.text,
      grade:     _gradeCtrl.text,
      serialMax: int.tryParse(_serialMaxCtrl.text),
      isRookie:  _isRookie,
      isAuto:    _isAuto,
      isPatch:   _isPatch,
    );
  }

  void _addExcludeTerm() {
    final term = _excludeCtrl.text.trim();
    if (term.isNotEmpty && !_excludeTerms.contains(term)) {
      setState(() => _excludeTerms.add(term));
    }
    _excludeCtrl.clear();
  }

  Future<void> _save() async {
    final player = _playerCtrl.text.trim();
    if (player.isEmpty) {
      setState(() => _error = 'Player name is required.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    String? str(String v) => v.trim().isEmpty ? null : v.trim();
    final data = {
      'player':        player,
      'year':          int.tryParse(_yearCtrl.text),
      'set_name':      str(_setCtrl.text),
      'parallel':      str(_parallelCtrl.text),
      'card_number':   str(_cardNumCtrl.text),
      'is_rookie':     _isRookie,
      'is_auto':       _isAuto,
      'is_patch':      _isPatch,
      'serial_max':    int.tryParse(_serialMaxCtrl.text),
      'grade':         str(_gradeCtrl.text),
      'ebay_query':    str(_queryCtrl.text),
      'exclude_terms': _excludeTerms,
      'target_price':  double.tryParse(_targetPriceCtrl.text),
    };
    final error = await widget.onSave(data);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      setState(() => _error = error);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isEditing = widget.editing != null;
    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: colors.outline.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
              child: Row(
                children: [
                  Text(
                    isEditing ? 'Edit Wishlist Item' : 'Add to Wishlist',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colors.onSurface),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.outline.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.close, size: 16, color: colors.onSurface.withValues(alpha: 0.5)),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.outline.withValues(alpha: 0.2)),
            // Scrollable form
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: colors.error.withValues(alpha: 0.1),
                          border: Border.all(color: colors.error.withValues(alpha: 0.3)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(children: [
                          Icon(Icons.error_outline, size: 14, color: colors.error),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error!, style: TextStyle(fontSize: 13, color: colors.error))),
                        ]),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _label('Player', required: true),
                    _field(_playerCtrl, colors: colors, hint: 'e.g. Connor Bedard', onChanged: (_) { setState(() {}); _rebuildQuery(); }),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Year'),
                        _field(_yearCtrl, colors: colors, hint: '2024', numeric: true, onChanged: (_) { setState(() {}); _rebuildQuery(); }),
                      ])),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Card #'),
                        _field(_cardNumCtrl, colors: colors, hint: 'e.g. 201', onChanged: (_) { setState(() {}); _rebuildQuery(); }),
                      ])),
                    ]),
                    const SizedBox(height: 16),
                    _label('Set'),
                    _field(_setCtrl, colors: colors, hint: 'e.g. Upper Deck Series 1', onChanged: (_) { setState(() {}); _rebuildQuery(); }),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Parallel'),
                        _field(_parallelCtrl, colors: colors, hint: 'e.g. Silver', onChanged: (_) { setState(() {}); _rebuildQuery(); }),
                      ])),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Grade'),
                        _field(_gradeCtrl, colors: colors, hint: 'e.g. PSA 10', onChanged: (_) { setState(() {}); _rebuildQuery(); }),
                      ])),
                    ]),
                    const SizedBox(height: 16),
                    _label('Attributes'),
                    Row(children: [
                      _attrChip('RC', _isRookie, const Color(0xFF2563EB),
                          () => setState(() { _isRookie = !_isRookie; _rebuildQuery(); })),
                      const SizedBox(width: 8),
                      _attrChip('AUTO', _isAuto, const Color(0xFF7C3AED),
                          () => setState(() { _isAuto = !_isAuto; _rebuildQuery(); })),
                      const SizedBox(width: 8),
                      _attrChip('PATCH', _isPatch, const Color(0xFFF59E0B),
                          () => setState(() { _isPatch = !_isPatch; _rebuildQuery(); })),
                      const Spacer(),
                      Text('/', style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.4), fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      SizedBox(width: 64, child: _field(_serialMaxCtrl, colors: colors, hint: '99', numeric: true,
                          onChanged: (_) { setState(() {}); _rebuildQuery(); })),
                    ]),
                    const SizedBox(height: 16),
                    Row(children: [
                      Text('EBAY SEARCH QUERY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.onSurface.withValues(alpha: 0.4), letterSpacing: 0.5)),
                      const SizedBox(width: 6),
                      Text('auto-built · editable', style: TextStyle(fontSize: 11, color: colors.onSurface.withValues(alpha: 0.3))),
                    ]),
                    const SizedBox(height: 6),
                    _field(_queryCtrl, colors: colors, hint: 'e.g. Connor Bedard RC PSA 10',
                        onChanged: (_) => setState(() => _queryEdited = true)),
                    const SizedBox(height: 16),
                    Row(children: [
                      Text('EXCLUDE TERMS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.onSurface.withValues(alpha: 0.4), letterSpacing: 0.5)),
                      const SizedBox(width: 6),
                      Text('press Enter to add', style: TextStyle(fontSize: 11, color: colors.onSurface.withValues(alpha: 0.3))),
                    ]),
                    const SizedBox(height: 6),
                    Container(
                      constraints: const BoxConstraints(minHeight: 42),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.outline.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Wrap(
                        spacing: 6, runSpacing: 6,
                        children: [
                          for (final term in _excludeTerms)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: colors.error.withValues(alpha: 0.1),
                                border: Border.all(color: colors.error.withValues(alpha: 0.3)),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(term, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.error)),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () => setState(() => _excludeTerms.remove(term)),
                                  child: Icon(Icons.close, size: 12, color: colors.error.withValues(alpha: 0.6)),
                                ),
                              ]),
                            ),
                          SizedBox(
                            width: double.infinity,
                            child: TextField(
                              controller: _excludeCtrl,
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: _excludeTerms.isEmpty ? 'e.g. draft picks' : '',
                                hintStyle: TextStyle(fontSize: 13, color: colors.onSurface.withValues(alpha: 0.3)),
                                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                              ),
                              style: TextStyle(fontSize: 13, color: colors.onSurface),
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _addExcludeTerm(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _label('Target Price'),
                    TextField(
                      controller: _targetPriceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        hintText: '0.00',
                        prefixText: '\$ ',
                        hintStyle: TextStyle(color: colors.onSurface.withValues(alpha: 0.3), fontSize: 14),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colors.outline.withValues(alpha: 0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colors.primary, width: 1.5),
                        ),
                        isDense: true,
                      ),
                      style: TextStyle(fontSize: 14, color: colors.onSurface),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            // Footer
            Divider(height: 1, color: colors.outline.withValues(alpha: 0.2)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.outline.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(child: Text('Cancel',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.onSurface.withValues(alpha: 0.6)))),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _saving ? null : _save,
                    child: Opacity(
                      opacity: _saving ? 0.5 : 1.0,
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: _saving
                              ? SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: colors.onPrimary))
                              : Text(isEditing ? 'Save Changes' : 'Add to Wishlist',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.onPrimary)),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text, {bool required = false}) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Text(text.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.onSurface.withValues(alpha: 0.4), letterSpacing: 0.5)),
        if (required) Text(' *', style: TextStyle(fontSize: 11, color: colors.error)),
      ]),
    );
  }

  Widget _field(TextEditingController ctrl, {ColorScheme? colors, String? hint, bool numeric = false, void Function(String)? onChanged}) {
    final colorScheme = colors ?? Theme.of(context).colorScheme;
    return TextField(
      controller: ctrl,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.3), fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        isDense: true,
      ),
      style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
    );
  }

  Widget _attrChip(String label, bool active, Color activeColor, VoidCallback onTap) {
    final colors = Theme.of(context).colorScheme;
    final bg = active ? activeColor : colors.outline.withValues(alpha: 0.1);
    final fg = active ? Colors.white : colors.onSurface.withValues(alpha: 0.6);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: fg)),
      ),
    );
  }
}
