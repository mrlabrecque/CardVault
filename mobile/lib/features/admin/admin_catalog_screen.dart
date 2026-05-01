import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/cards_service.dart';
import '../../core/widgets/adaptive_dropdown.dart';
import '../../core/widgets/app_breadcrumb.dart';
import '../../core/widgets/card_fan_loader.dart';

final _years = List.generate(
  2026 - 1980 + 1,
  (i) => (2026 - i).toString(),
);

const _sports = [
  ('Baseball',    'baseball'),
  ('Basketball',  'basketball'),
  ('Football',    'football'),
  ('Soccer',      'soccer'),
  ('Hockey',      'hockey'),
];

const _segmentToSport = {
  'baseball':   'Baseball',
  'basketball': 'Basketball',
  'football':   'Football',
  'soccer':     'Soccer',
  'hockey':     'Hockey',
};

int? _tryParseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  if (value is num) return value.toInt();
  return null;
}

enum _AdminStep { releases, sets }

class AdminCatalogScreen extends ConsumerStatefulWidget {
  const AdminCatalogScreen({super.key});

  @override
  ConsumerState<AdminCatalogScreen> createState() => _AdminCatalogScreenState();
}

class _AdminCatalogScreenState extends ConsumerState<AdminCatalogScreen> {
  _AdminStep _step = _AdminStep.releases;

  // ── Releases ──────────────────────────────────────────────────
  String _year = DateTime.now().year.toString();
  String _segment = 'baseball';
  bool _importingReleases = false;
  int _importSkip = 0;

  List<ReleaseRecord> _releases = [];
  bool _loadingReleases = false;
  final _searchCtrl = TextEditingController();

  ReleaseRecord? _selectedRelease;

  // ── Sets ──────────────────────────────────────────────────────
  List<SetRecord> _sets = [];
  bool _loadingSets = false;
  bool _importingSets = false;
  final _importingCards = <String>{};

  @override
  void initState() {
    super.initState();
    _loadReleases();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Release methods ───────────────────────────────────────────

  Future<void> _loadReleases() async {
    setState(() { _loadingReleases = true; _releases = []; });
    try {
      final rows = await ref.read(cardsServiceProvider).browseReleases(
        year: int.tryParse(_year),
        sport: _segmentToSport[_segment],
        offset: 0,
        limit: 500,
      );
      setState(() => _releases = rows);
    } finally {
      if (mounted) setState(() => _loadingReleases = false);
    }
  }

  Future<void> _importReleases() async {
    setState(() => _importingReleases = true);
    try {
      final result = await ref.read(cardsServiceProvider).bulkImportReleases(
        year: int.parse(_year),
        segment: _segment,
        skip: _importSkip,
      );
      final imported = _tryParseInt(result['imported']) ?? 0;
      final total    = _tryParseInt(result['total']) ?? 0; // used to detect full page (more batches available)
      if (mounted) {
        setState(() { if (imported > 0) _importSkip += 100; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(imported > 0
              ? '$imported new release${imported == 1 ? '' : 's'} added'
              : total == 100 ? 'Already up to date — tap again to check next batch' : 'Already up to date'),
        ));
        await _loadReleases();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _importingReleases = false);
    }
  }

  Future<void> _selectRelease(ReleaseRecord release) async {
    setState(() {
      _selectedRelease = release;
      _step = _AdminStep.sets;
      _sets = [];
    });
    await _loadSets();
  }

  // ── Set methods ───────────────────────────────────────────────

  Future<void> _loadSets() async {
    setState(() => _loadingSets = true);
    try {
      final sets = await ref.read(cardsServiceProvider).getSetsForRelease(_selectedRelease!.id);
      setState(() => _sets = sets);
    } finally {
      if (mounted) setState(() => _loadingSets = false);
    }
  }

  Future<void> _importSets() async {
    final csId = _selectedRelease?.cardsightId;
    if (csId == null) return;
    setState(() => _importingSets = true);
    try {
      await ref.read(cardsServiceProvider).importSetsForRelease(
        cardsightReleaseId: csId,
        releaseName: _selectedRelease!.name,
        releaseYear: _selectedRelease!.year?.toString(),
      );
      await _loadSets();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _importingSets = false);
    }
  }

  Future<void> _importCardsForSet(SetRecord set) async {
    final release = _selectedRelease!;
    if (release.cardsightId == null || set.cardsightId == null) return;
    setState(() => _importingCards.add(set.id));
    try {
      await ref.read(cardsServiceProvider).importCardsForSet(
        cardsightReleaseId: release.cardsightId!,
        cardsightSetId: set.cardsightId!,
        setId: set.id,
      );
      await _loadSets();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _importingCards.remove(set.id));
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: switch (_step) {
        _AdminStep.releases => _buildReleasesView(colors),
        _AdminStep.sets     => _buildSetsView(colors),
      },
    );
  }

  // ── Releases view ─────────────────────────────────────────────

  Widget _buildReleasesView(ColorScheme colors) {
    return Column(
      children: [
        // Filters + import button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: AdaptiveDropdown<String>(
                      value: _year,
                      decoration: _inputDec('Year'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('All years')),
                        ..._years.map((y) => DropdownMenuItem(value: y, child: Text(y))),
                      ],
                      onChanged: (v) {
                        setState(() { _year = v!; _importSkip = 0; });
                        _loadReleases();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AdaptiveDropdown<String>(
                      value: _segment,
                      decoration: _inputDec('Sport'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('All sports')),
                        ..._sports.map((s) => DropdownMenuItem(value: s.$2, child: Text(s.$1))),
                      ],
                      onChanged: (v) {
                        setState(() { _segment = v!; _importSkip = 0; });
                        _loadReleases();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
                            TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Filter releases…',
                  hintStyle: TextStyle(fontSize: 14, color: colors.onSurface.withValues(alpha: 0.4)),
                  prefixIcon: Icon(Icons.search, size: 18, color: colors.onSurface.withValues(alpha: 0.4)),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => setState(() => _searchCtrl.clear()),
                        )
                      : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (_importingReleases || _year.isEmpty || _segment.isEmpty) ? null : _importReleases,
                  icon: _importingReleases
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.download_outlined, size: 16),
                  label: Text(_year.isEmpty || _segment.isEmpty
                      ? 'Select a year and sport to import'
                      : _importSkip == 0 ? 'Import from CardSight' : 'Load next batch (skip $_importSkip)'),
                ),
              ),

            ],
          ),
        ),
        const Divider(height: 1),
        // Release list
        Expanded(
          child: _loadingReleases && _releases.isEmpty
              ? const Center(child: CardFanLoader())
              : Builder(builder: (context) {
                  final q = _searchCtrl.text.toLowerCase();
                  final filtered = q.isEmpty
                      ? _releases
                      : _releases.where((r) => r.displayName.toLowerCase().contains(q)).toList();
                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        _releases.isEmpty ? 'No releases in database.' : 'No results match your search.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurface.withValues(alpha: 0.4)),
                      ),
                    );
                  }
                  return ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = filtered[i];
                        return ListTile(
                          leading: _StatusDot(imported: r.importedSetCount, total: r.setCount),
                          title: Text(r.displayName,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                          subtitle: r.sport != null
                              ? Text('${r.sport}  ·  ${r.setCount} sets', style: const TextStyle(fontSize: 12))
                              : null,
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: () => _selectRelease(r),
                        );
                      },
                    );
                }),
        ),
      ],
    );
  }

  // ── Sets view ─────────────────────────────────────────────────

  Widget _buildSetsView(ColorScheme colors) {
    return Column(
      children: [
        AppBreadcrumb(
          parent: 'Catalog',
          current: _selectedRelease?.displayName ?? '',
          onBack: () => setState(() {
            _step = _AdminStep.releases;
            _selectedRelease = null;
            _sets = [];
          }),
        ),
        if (_loadingSets || _importingSets) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _loadingSets && _sets.isEmpty
              ? const Center(child: CardFanLoader())
              : _sets.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('No sets imported yet.',
                              style: TextStyle(color: colors.onSurface.withValues(alpha: 0.4))),
                          const SizedBox(height: 16),
                          if (_selectedRelease?.cardsightId != null)
                            FilledButton.icon(
                              onPressed: _importingSets ? null : _importSets,
                              icon: const Icon(Icons.download_outlined, size: 16),
                              label: const Text('Import Sets from CardSight'),
                            ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: _sets.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final s = _sets[i];
                        final isImporting = _importingCards.contains(s.id);
                        final isImported = s.importedCount > 0;
                        return ListTile(
                          leading: _StatusDot(imported: s.importedCount, total: s.cardCount ?? 0),
                          title: Text(s.name,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                          subtitle: s.cardCount != null
                              ? Text(
                                  isImported
                                      ? '${s.importedCount} / ${s.cardCount} cards imported'
                                      : '${s.cardCount} cards',
                                  style: const TextStyle(fontSize: 12),
                                )
                              : null,
                          trailing: isImporting
                              ? const SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : isImported
                                  ? IconButton(
                                      icon: Icon(Icons.refresh, size: 18, color: colors.onSurface.withValues(alpha: 0.4)),
                                      tooltip: 'Re-import cards',
                                      onPressed: () => _importCardsForSet(s),
                                    )
                                  : FilledButton.tonal(
                                      onPressed: () => _importCardsForSet(s),
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        textStyle: const TextStyle(fontSize: 12),
                                      ),
                                      child: const Text('Import Cards'),
                                    ),
                        );
                      },
                    ),
        ),
        if (_sets.isNotEmpty && _selectedRelease?.cardsightId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _importingSets ? null : _importSets,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Re-import sets from CardSight'),
              ),
            ),
          ),
      ],
    );
  }

  InputDecoration _inputDec(String label) => InputDecoration(
    labelText: label,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    isDense: true,
  );
}

// ── Status dot ────────────────────────────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.imported, required this.total});
  final int imported;
  final int total;

  @override
  Widget build(BuildContext context) {
    if (total > 0 && imported >= total) {
      return const Icon(Icons.check_circle_outline, size: 16, color: Colors.green);
    }
    if (imported > 0) {
      return const Icon(Icons.adjust, size: 16, color: Colors.amber);
    }
    return Icon(Icons.radio_button_unchecked, size: 16,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3));
  }
}
