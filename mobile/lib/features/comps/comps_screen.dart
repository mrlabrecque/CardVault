import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/comps_service.dart';
import '../../core/models/comp.dart';
import '../../core/theme/app_theme.dart';

class CompsScreen extends ConsumerStatefulWidget {
  const CompsScreen({super.key});

  @override
  ConsumerState<CompsScreen> createState() => _CompsScreenState();
}

class _CompsScreenState extends ConsumerState<CompsScreen> {
  final _searchCtrl = TextEditingController();
  List<Comp>? _results;
  bool _loading = false;
  String? _error;
  int _page = 1;

  static const _pageSize = 10;

  void _showValueDisclaimer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.info_outline, size: 18, color: Color(0xFFF97316)),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Why values may differ',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'This search returns broad eBay sold results based on whatever you type — it doesn\'t know your specific card.',
              style: TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.5),
            ),
            const SizedBox(height: 10),
            const Text(
              'The value shown on cards in your collection is refreshed using that card\'s exact details — player, year, set, parallel, grade, and serial number — so those comps are much more targeted.',
              style: TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.5),
            ),
            const SizedBox(height: 10),
            const Text(
              'Use this search to explore the market. For the most accurate value on a card you own, use the refresh button on that card.',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _search([String? query]) async {
    final q = query ?? _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() { _loading = true; _error = null; _page = 1; });
    try {
      final results = await ref.read(compsServiceProvider).search(q);
      setState(() => _results = results);
      ref.invalidate(lookupHistoryProvider);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _loading = false);
    }
  }

  _Stats? get _stats {
    if (_results == null || _results!.isEmpty) return null;
    final prices = _results!.map((c) => c.price).where((p) => p > 0).toList()..sort();
    if (prices.isEmpty) return null;
    final avg = prices.reduce((a, b) => a + b) / prices.length;
    final mid = prices.length ~/ 2;
    final median = prices.length % 2 == 0
        ? (prices[mid - 1] + prices[mid]) / 2
        : prices[mid];
    return _Stats(avg: avg, median: median, min: prices.first, max: prices.last);
  }

  List<Comp> get _pagedResults {
    if (_results == null) return [];
    final start = (_page - 1) * _pageSize;
    return _results!.skip(start).take(_pageSize).toList();
  }

  int get _totalPages =>
      _results == null ? 0 : (_results!.length / _pageSize).ceil().clamp(1, 999);

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(lookupHistoryProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          // ── Breadcrumb ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Text('Tools', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF9CA3AF))),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.chevron_right, size: 14, color: Color(0xFFD1D5DB)),
                ),
                const Text('Comp Search', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                const Spacer(),
                GestureDetector(
                  onTap: () => _showValueDisclaimer(context),
                  child: const Icon(Icons.info_outline, size: 16, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
          ),

          // ── Search bar ──────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onSubmitted: (_) => _search(),
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Player, set, year, grade…',
                    hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                    prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF9CA3AF)),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primary.withValues(alpha: 0.4))),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _loading ? null : _search,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: _loading ? 0.4 : 1.0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _loading
                      ? const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          ),
                        )
                      : const Icon(Icons.search, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),

          // ── Error ───────────────────────────────────────────────────────────
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13))),
                ],
              ),
            ),
          ],

          // ── Stats bar ───────────────────────────────────────────────────────
          if (_stats case final s?) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                _StatCard(label: 'Avg',    value: s.avg),
                const SizedBox(width: 8),
                _StatCard(label: 'Median', value: s.median),
                const SizedBox(width: 8),
                _StatCard(label: 'Low',    value: s.min),
                const SizedBox(width: 8),
                _StatCard(label: 'High',   value: s.max),
              ],
            ),
          ],

          // ── Results ─────────────────────────────────────────────────────────
          if (_results != null) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Results', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                Text('${_results!.length} sold', style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
              ],
            ),
            const SizedBox(height: 10),
            if (_results!.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text('No sold listings found.', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
                ),
              )
            else ...[
              ..._pagedResults.map((comp) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CompCard(comp: comp),
              )),
              if (_totalPages > 1) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _PageButton(
                      icon: Icons.chevron_left,
                      enabled: _page > 1,
                      onTap: () => setState(() => _page--),
                    ),
                    Text('$_page / $_totalPages', style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                    _PageButton(
                      icon: Icons.chevron_right,
                      enabled: _page < _totalPages,
                      onTap: () => setState(() => _page++),
                    ),
                  ],
                ),
              ],
            ],
          ],

          // ── Recent lookups (always shown) ──────────────────────────────────
          historyAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (history) {
              if (history.isEmpty && _results == null) {
                return const Padding(
                  padding: EdgeInsets.only(top: 64),
                  child: Center(
                    child: Text(
                      'Search for a card to see eBay sold values.',
                      style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              if (history.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  const Text('Recent Lookups', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                  const SizedBox(height: 10),
                  ...history.map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _HistoryTile(
                      entry: entry,
                      onTap: () {
                        _searchCtrl.text = entry.query;
                        _search(entry.query);
                      },
                    ),
                  )),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Data ──────────────────────────────────────────────────────────────────────

class _Stats {
  final double avg, median, min, max;
  const _Stats({required this.avg, required this.median, required this.min, required this.max});
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF3F4F6)),
        ),
        child: Column(
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF9CA3AF), letterSpacing: 0.5),
            ),
            const SizedBox(height: 3),
            Text(
              '\$${value.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompCard extends StatelessWidget {
  const _CompCard({required this.comp});
  final Comp comp;

  @override
  Widget build(BuildContext context) {
    final daysAgo = comp.soldAt != null ? DateTime.now().difference(comp.soldAt!).inDays : null;
    final dateLabel = daysAgo == null
        ? ''
        : daysAgo == 0
            ? 'Today'
            : daysAgo == 1
                ? 'Yesterday'
                : '${daysAgo}d ago';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF3F4F6)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  comp.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87, height: 1.35),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '\$${comp.price.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black87),
              ),
            ],
          ),
          if (dateLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(dateLabel, style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
          ],
          if (comp.url != null) ...[
            const SizedBox(height: 10),
            const Divider(color: Color(0xFFF9FAFB), height: 1),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => launchUrl(Uri.parse(comp.url!), mode: LaunchMode.externalApplication),
              child: const Row(
                children: [
                  Icon(Icons.open_in_new, size: 12, color: Color(0xFF800020)),
                  SizedBox(width: 4),
                  Text('View on eBay', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF800020))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry, required this.onTap});
  final LookupHistory entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF3F4F6)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            const Icon(Icons.history, size: 16, color: Color(0xFFD1D5DB)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                entry.query,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
              ),
            ),
            if (entry.avgPrice != null) ...[
              Text(
                '\$${entry.avgPrice!.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF6B7280)),
              ),
              const SizedBox(width: 6),
            ],
            const Icon(Icons.north_east, size: 12, color: Color(0xFFD1D5DB)),
          ],
        ),
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({required this.icon, required this.enabled, required this.onTap});
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Icon(icon, size: 20, color: enabled ? const Color(0xFF6B7280) : const Color(0xFFD1D5DB)),
      ),
    );
  }
}
