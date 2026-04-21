import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/auth/auth_service.dart';
import '../../core/models/wishlist_item.dart';

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
    await ref.read(supabaseProvider).from('wishlist').insert(data);
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
  final _expandedMatches = <String>{};
  String? _deletingId;
  bool _checking = false;
  ({int checked, int triggered, String? error})? _checkResult;

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
    return ListView(
      children: [
        const SizedBox(height: 64),
        Column(
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
              child: Icon(Icons.bookmark_border, size: 28, color: Colors.grey.shade300),
            ),
            const SizedBox(height: 16),
            const Text('No cards on your wishlist',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
            const SizedBox(height: 4),
            Text('Add cards to watch for deals on eBay.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _showWishlistForm(context, ref),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF800020),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Add a Card', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildList(List<WishlistItem> items) {
    final lastChecked = items
        .where((i) => i.lastCheckedAt != null)
        .map((i) => i.lastCheckedAt!)
        .fold<DateTime?>(null, (best, t) => best == null || t.isAfter(best) ? t : best);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 100),
      children: [
        // Check Now bar
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _checking ? null : () async {
                setState(() { _checking = true; _checkResult = null; });
                final result = await ref.read(wishlistProvider.notifier).checkNow();
                setState(() { _checking = false; _checkResult = result; });
              },
              icon: _checking
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.refresh, size: 14),
              label: Text(_checking ? 'Checking eBay…' : 'Check Now',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF800020),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF800020).withValues(alpha: 0.5),
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                elevation: 0,
              ),
            ),
            if (_checkResult != null) ...[
              const SizedBox(width: 12),
              if (_checkResult!.triggered > 0)
                Text(
                  '${_checkResult!.triggered} deal${_checkResult!.triggered == 1 ? '' : 's'} found!',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF059669)),
                )
              else if (_checkResult!.error != null)
                Text('Error: ${_checkResult!.error}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444)))
              else
                Text('Checked ${_checkResult!.checked} item${_checkResult!.checked == 1 ? '' : 's'} — no deals yet.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
          ],
        ),
        if (lastChecked != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text('Last checked at ${_formatChecked(lastChecked)}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          ),
        ],
        const SizedBox(height: 16),
        for (final item in items) ...[
          _WishlistCard(
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
          ),
          const SizedBox(height: 12),
        ],
        // Add another
        OutlinedButton.icon(
          onPressed: () => _showWishlistForm(context, ref),
          icon: const Icon(Icons.add, size: 14),
          label: const Text('Add Another Card', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.grey.shade400,
            side: BorderSide(color: Colors.grey.shade200, width: 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            minimumSize: const Size(double.infinity, 0),
          ),
        ),
      ],
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

  String _formatChecked(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    final time = '$h:$m $ampm';
    if (isToday) return time;
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day} at $time';
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
    final triggered = item.isTriggered;
    final borderColor = triggered ? const Color(0xFF6EE7B7) : const Color(0xFFF3F4F6);
    final bgColor = triggered ? const Color(0xFFF0FDF4) : Colors.white;
    final dividerColor = triggered ? const Color(0xFFD1FAE5) : const Color(0xFFF9FAFB);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Deal Found banner
          if (triggered) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF10b981),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_offer, color: Colors.white, size: 14),
                  const SizedBox(width: 8),
                  const Text('Deal Found!',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  const Spacer(),
                  if (item.savings > 0)
                    Text('\$${item.savings.toStringAsFixed(0)} under target',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],

          // Top row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.player ?? 'Unknown',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black87),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (item.year != null) '${item.year}',
                        if (item.setName != null) item.setName!,
                        if (item.parallel != null) '· ${item.parallel}',
                      ].join(' '),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                children: [
                  if (!triggered) _StatusBadge(status: item.alertStatus),
                  const SizedBox(width: 4),
                  _IconBtn(icon: Icons.edit_outlined, size: 14, onTap: onEdit),
                ],
              ),
            ],
          ),

          // Attributes
          if (item.attrs.isNotEmpty || item.cardNumber != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6, runSpacing: 4,
              children: [
                if (item.cardNumber != null)
                  Text('#${item.cardNumber}',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade400)),
                for (final tag in item.attrs) _AttrTag(tag: tag),
              ],
            ),
          ],

          // Price row
          const SizedBox(height: 12),
          Divider(color: dividerColor, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              _PriceCell(
                label: 'Target',
                value: item.targetPrice != null ? '\$${item.targetPrice!.toStringAsFixed(0)}' : null,
                valueColor: const Color(0xFF800020),
                valueBold: true,
              ),
              _PriceCell(
                label: 'Best Match',
                value: item.lastSeenPrice != null ? '\$${item.lastSeenPrice!.toStringAsFixed(2)}' : null,
                valueColor: triggered ? const Color(0xFF059669) : Colors.black87,
                valueBold: true,
                prefix: triggered ? const Icon(Icons.arrow_downward, size: 10, color: Color(0xFF059669)) : null,
              ),
              _PriceCell(
                label: 'Grade',
                value: item.grade?.isNotEmpty == true ? item.grade! : 'Any',
                valueColor: Colors.black87,
              ),
            ],
          ),

          // Active listings
          if (triggered && item.matches.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(color: dividerColor, height: 1),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onToggleMatches,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${item.matches.length} Active Listing${item.matches.length == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                        color: Color(0xFF059669), letterSpacing: 0.5),
                  ),
                  Icon(
                    isMatchesExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16, color: const Color(0xFF059669),
                  ),
                ],
              ),
            ),
            if (isMatchesExpanded) ...[
              const SizedBox(height: 8),
              for (final match in item.matches)
                _MatchRow(match: match, onDismiss: () => onDismissMatch(match.id)),
            ],
          ],

          // Actions
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSearchComps,
                  icon: const Icon(Icons.search, size: 13),
                  label: const Text('Search Comps', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade600,
                    side: BorderSide(color: Colors.grey.shade200),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _IconBtn(
                icon: item.isPaused ? Icons.play_arrow : Icons.pause,
                onTap: onTogglePause,
                border: true,
              ),
              const SizedBox(width: 8),
              _IconBtn(
                icon: isDeleting ? null : Icons.delete_outline,
                loading: isDeleting,
                onTap: onDelete,
                color: const Color(0xFFFEF2F2),
                iconColor: const Color(0xFFF87171),
                border: true,
                borderColor: const Color(0xFFFEE2E2),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Match row ──────────────────────────────────────────────────────────────────

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match, required this.onDismiss});
  final WishlistMatch match;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final isAuction = match.listingType == 'AUCTION';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: match.url != null
                ? () => launchUrl(Uri.parse(match.url!), mode: LaunchMode.externalApplication)
                : null,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD1FAE5)),
              ),
              child: Row(
                children: [
                  if (match.imageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(match.imageUrl!, width: 40, height: 40, fit: BoxFit.cover,
                          errorBuilder: (ctx, err, st) => const SizedBox(width: 40, height: 40)),
                    ),
                  if (match.imageUrl != null) const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(match.title,
                            style: const TextStyle(fontSize: 11, color: Colors.black87),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(isAuction ? 'Auction' : 'Buy Now',
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w700,
                                color: isAuction ? const Color(0xFF9333EA) : const Color(0xFF2563EB))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('\$${match.price.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                              color: Color(0xFF059669))),
                      const Icon(Icons.open_in_new, size: 10, color: Colors.grey),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: -8, right: -8,
            child: GestureDetector(
              onTap: onDismiss,
              child: Container(
                width: 20, height: 20,
                decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                child: const Icon(Icons.close, color: Colors.white, size: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Small helpers ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      'active'    => ('Watching', const Color(0xFFDCFCE7), const Color(0xFF16A34A)),
      'triggered' => ('Below Target!', const Color(0xFFFEF9C3), const Color(0xFFCA8A04)),
      'paused'    => ('Paused', const Color(0xFFF3F4F6), const Color(0xFF9CA3AF)),
      _           => ('Unknown', const Color(0xFFF3F4F6), const Color(0xFF9CA3AF)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class _AttrTag extends StatelessWidget {
  const _AttrTag({required this.tag});
  final String tag;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tag) {
      'RC'   => (const Color(0xFFDBEAFE), const Color(0xFF1D4ED8)),
      'AUTO' => (const Color(0xFFF3E8FF), const Color(0xFF7E22CE)),
      'PATCH'=> (const Color(0xFFFEF3C7), const Color(0xFFB45309)),
      _      => (const Color(0xFFF3F4F6), const Color(0xFF6B7280)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(tag, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

class _PriceCell extends StatelessWidget {
  const _PriceCell({
    required this.label,
    required this.value,
    this.valueColor,
    this.valueBold = false,
    this.prefix,
  });
  final String label;
  final String? value;
  final Color? valueColor;
  final bool valueBold;
  final Widget? prefix;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(fontSize: 9, color: Colors.grey.shade400, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          if (value != null)
            Row(
              children: [
                if (prefix != null) ...[prefix!, const SizedBox(width: 2)],
                Text(value!,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: valueBold ? FontWeight.w700 : FontWeight.w600,
                        color: valueColor ?? Colors.black87)),
              ],
            )
          else
            Text('—', style: TextStyle(fontSize: 13, color: Colors.grey.shade200)),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    this.icon,
    this.loading = false,
    required this.onTap,
    this.color,
    this.iconColor,
    this.border = false,
    this.borderColor,
    this.size = 16,
  });
  final IconData? icon;
  final bool loading;
  final VoidCallback onTap;
  final Color? color;
  final Color? iconColor;
  final bool border;
  final Color? borderColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: color ?? Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: border
              ? Border.all(color: borderColor ?? Colors.grey.shade200)
              : null,
        ),
        child: Center(
          child: loading
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF87171)))
              : Icon(icon, size: size, color: iconColor ?? Colors.grey.shade500),
        ),
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
    final data = {
      'player':        player,
      'year':          int.tryParse(_yearCtrl.text),
      'set_name':      _setCtrl.text.trim(),
      'parallel':      _parallelCtrl.text.trim(),
      'card_number':   _cardNumCtrl.text.trim(),
      'is_rookie':     _isRookie,
      'is_auto':       _isAuto,
      'is_patch':      _isPatch,
      'serial_max':    int.tryParse(_serialMaxCtrl.text),
      'grade':         _gradeCtrl.text.trim(),
      'ebay_query':    _queryCtrl.text.trim(),
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
    final isEditing = widget.editing != null;
    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
              child: Row(
                children: [
                  Text(
                    isEditing ? 'Edit Wishlist Item' : 'Add to Wishlist',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.grey.shade100),
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
                          color: const Color(0xFFFEF2F2),
                          border: Border.all(color: const Color(0xFFFECACA)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(children: [
                          const Icon(Icons.error_outline, size: 14, color: Color(0xFFDC2626)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error!, style: const TextStyle(fontSize: 13, color: Color(0xFFDC2626)))),
                        ]),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _label('Player', required: true),
                    _field(_playerCtrl, hint: 'e.g. Connor Bedard', onChanged: (_) { setState(() {}); _rebuildQuery(); }),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Year'),
                        _field(_yearCtrl, hint: '2024', numeric: true, onChanged: (_) { setState(() {}); _rebuildQuery(); }),
                      ])),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Card #'),
                        _field(_cardNumCtrl, hint: 'e.g. 201', onChanged: (_) { setState(() {}); _rebuildQuery(); }),
                      ])),
                    ]),
                    const SizedBox(height: 16),
                    _label('Set'),
                    _field(_setCtrl, hint: 'e.g. Upper Deck Series 1', onChanged: (_) { setState(() {}); _rebuildQuery(); }),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Parallel'),
                        _field(_parallelCtrl, hint: 'e.g. Silver', onChanged: (_) { setState(() {}); _rebuildQuery(); }),
                      ])),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Grade'),
                        _field(_gradeCtrl, hint: 'e.g. PSA 10', onChanged: (_) { setState(() {}); _rebuildQuery(); }),
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
                      Text('/', style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      SizedBox(width: 64, child: _field(_serialMaxCtrl, hint: '99', numeric: true,
                          onChanged: (_) { setState(() {}); _rebuildQuery(); })),
                    ]),
                    const SizedBox(height: 16),
                    Row(children: [
                      Text('EBAY SEARCH QUERY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade400, letterSpacing: 0.5)),
                      const SizedBox(width: 6),
                      Text('auto-built · editable', style: TextStyle(fontSize: 11, color: Colors.grey.shade300)),
                    ]),
                    const SizedBox(height: 6),
                    _field(_queryCtrl, hint: 'e.g. Connor Bedard RC PSA 10',
                        onChanged: (_) => setState(() => _queryEdited = true)),
                    const SizedBox(height: 16),
                    Row(children: [
                      Text('EXCLUDE TERMS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade400, letterSpacing: 0.5)),
                      const SizedBox(width: 6),
                      Text('press Enter to add', style: TextStyle(fontSize: 11, color: Colors.grey.shade300)),
                    ]),
                    const SizedBox(height: 6),
                    Container(
                      constraints: const BoxConstraints(minHeight: 42),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Wrap(
                        spacing: 6, runSpacing: 6,
                        children: [
                          for (final term in _excludeTerms)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                border: Border.all(color: const Color(0xFFFECACA)),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(term, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFDC2626))),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () => setState(() => _excludeTerms.remove(term)),
                                  child: Icon(Icons.close, size: 12, color: Colors.red.shade400),
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
                                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade300),
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              style: const TextStyle(fontSize: 13),
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
                        hintStyle: TextStyle(color: Colors.grey.shade300, fontSize: 14),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide(color: Color(0xFF800020), width: 1.5),
                        ),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            // Footer
            Divider(height: 1, color: Colors.grey.shade100),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(child: Text('Cancel',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade600))),
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
                          color: const Color(0xFF800020),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: _saving
                              ? const SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(isEditing ? 'Save Changes' : 'Add to Wishlist',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
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

  Widget _label(String text, {bool required = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Text(text.toUpperCase(),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade400, letterSpacing: 0.5)),
      if (required) const Text(' *', style: TextStyle(fontSize: 11, color: Color(0xFFF87171))),
    ]),
  );

  Widget _field(TextEditingController ctrl, {String? hint, bool numeric = false, void Function(String)? onChanged}) =>
      TextField(
        controller: ctrl,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade300, fontSize: 14),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFF800020), width: 1.5),
          ),
          isDense: true,
        ),
        style: const TextStyle(fontSize: 14),
      );

  Widget _attrChip(String label, bool active, Color activeColor, VoidCallback onTap) {
    final bg = active ? activeColor : const Color(0xFFF3F4F6);
    final fg = active ? Colors.white : const Color(0xFF6B7280);
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
