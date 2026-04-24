import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/cards_service.dart';

class AdminReleasesScreen extends ConsumerStatefulWidget {
  const AdminReleasesScreen({super.key});

  @override
  ConsumerState<AdminReleasesScreen> createState() => _AdminReleasesScreenState();
}

class _AdminReleasesScreenState extends ConsumerState<AdminReleasesScreen> {
  final _searchCtrl = TextEditingController();
  List<ReleaseRecord> _results = [];
  bool _loading = false;
  bool _hasMore = false;
  int _offset = 0;
  static const _pageSize = 30;
  bool _searchMode = false;

  @override
  void initState() {
    super.initState();
    _loadReleases(reset: true);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReleases({bool reset = false}) async {
    if (reset) setState(() { _offset = 0; _results = []; });
    setState(() => _loading = true);
    try {
      final q = _searchCtrl.text.trim();
      List<ReleaseRecord> rows;
      if (q.isNotEmpty) {
        rows = await ref.read(cardsServiceProvider).searchReleases(q);
        _searchMode = true;
      } else {
        rows = await ref.read(cardsServiceProvider).browseReleases(
          offset: _offset, limit: _pageSize,
        );
        _searchMode = false;
      }
      setState(() {
        _results = reset ? rows : [..._results, ...rows];
        _hasMore = !_searchMode && rows.length == _pageSize;
        _offset = _results.length;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => _loadReleases(reset: true),
              decoration: InputDecoration(
                hintText: 'Search releases…',
                hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
                prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF9CA3AF)),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () { _searchCtrl.clear(); _loadReleases(reset: true); },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: _loading && _results.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? Center(child: Text('No releases found.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4))))
                    : ListView.separated(
                        itemCount: _results.length + (_hasMore ? 1 : 0),
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          if (i == _results.length) {
                            return _loading
                                ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                                : ListTile(
                                    title: Text('Load more',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 14)),
                                    onTap: _loadReleases,
                                  );
                          }
                          final r = _results[i];
                          return ListTile(
                            title: Text(r.displayName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            subtitle: r.sport != null ? Text(r.sport!, style: const TextStyle(fontSize: 12)) : null,
                            trailing: const Icon(Icons.chevron_right, size: 18),
                            onTap: () => context.push('/admin/releases/${r.id}/sets', extra: r),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
