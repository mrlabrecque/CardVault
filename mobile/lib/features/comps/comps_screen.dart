import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/comps_service.dart';
import '../../core/models/comp.dart';

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
  String _lastQuery = '';

  Future<void> _search([String? query]) async {
    final q = query ?? _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() { _loading = true; _error = null; _lastQuery = q; });
    try {
      final results = await ref.read(compsServiceProvider).search(q);
      setState(() => _results = results);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  double? get _avg {
    if (_results == null || _results!.isEmpty) return null;
    return _results!.fold(0.0, (s, c) => s + c.price) / _results!.length;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final historyAsync = ref.watch(lookupHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Comps')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onSubmitted: (_) => _search(),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search eBay sold listings…',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _loading ? null : _search, child: const Text('Go')),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: colors.error))),
          if (_results != null) ...[
            if (_avg != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_lastQuery, style: TextStyle(fontWeight: FontWeight.w600, color: colors.onPrimaryContainer), overflow: TextOverflow.ellipsis),
                    Text('Avg \$${_avg!.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.w700, color: colors.onPrimaryContainer)),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 100),
                itemCount: _results!.length,
                itemBuilder: (_, i) => _CompTile(comp: _results![i]),
              ),
            ),
          ] else
            Expanded(
              child: historyAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => const SizedBox.shrink(),
                data: (history) {
                  if (history.isEmpty) {
                    return Center(child: Text('Search for a card to see eBay sold values.', style: TextStyle(color: colors.onSurface.withValues(alpha: 0.5))));
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Text('Recent Lookups', style: Theme.of(context).textTheme.titleSmall),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: history.length,
                          itemBuilder: (_, i) => ListTile(
                            title: Text(history[i].query),
                            trailing: history[i].avgPrice != null
                                ? Text('Avg \$${history[i].avgPrice!.toStringAsFixed(2)}', style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600))
                                : null,
                            onTap: () { _searchCtrl.text = history[i].query; _search(history[i].query); },
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _CompTile extends StatelessWidget {
  const _CompTile({required this.comp});
  final Comp comp;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final daysAgo = DateTime.now().difference(comp.soldAt).inDays;
    final dateLabel = daysAgo == 0 ? 'Today' : daysAgo == 1 ? 'Yesterday' : '${daysAgo}d ago';

    return ListTile(
      title: Text(comp.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
      subtitle: Text(dateLabel, style: TextStyle(fontSize: 11, color: colors.onSurface.withValues(alpha: 0.5))),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('\$${comp.price.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          if (comp.url != null)
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 16),
              onPressed: () => launchUrl(Uri.parse(comp.url!), mode: LaunchMode.externalApplication),
            ),
        ],
      ),
    );
  }
}
