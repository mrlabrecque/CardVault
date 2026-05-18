import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart' hide showAdaptiveDialog;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/fonts.dart';
import '../../core/services/cards_service.dart';
import '../../core/utils/adaptive_ui.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/chrome_metrics.dart';
import '../../core/widgets/adaptive_dropdown.dart';
import '../../core/widgets/app_bar_shell_trailing_actions.dart';
import '../../core/widgets/app_breadcrumb.dart';
import '../../core/widgets/card_fan_loader.dart';
import '../../core/widgets/glass_nav_bar.dart';
import '../../core/widgets/glass_search_field.dart';
import '../../core/widgets/sticky_chrome_scaffold.dart';

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
  /// Empty until the admin picks a sport (avoids CardSight fetch on screen open).
  String _segment = '';
  bool _importingReleases = false;

  List<AdminCatalogReleaseRow> _catalogReleases = [];
  int _missingCount = 0;
  bool _loadingReleases = false;
  bool _missingOnly = false;
  final Set<String> _selectedIds = {};
  final _searchCtrl = TextEditingController();

  ReleaseRecord? _selectedRelease;

  // ── Sets ──────────────────────────────────────────────────────
  List<SetRecord> _sets = [];
  bool _loadingSets = false;
  bool _importingSets = false;
  final _importingCards = <String>{};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Release methods ───────────────────────────────────────────

  List<AdminCatalogReleaseRow> _filteredCatalogReleases() {
    final q = _searchCtrl.text.toLowerCase().trim();
    var list = _catalogReleases;
    if (_missingOnly) list = list.where((r) => !r.inVault).toList();
    if (q.isNotEmpty) {
      list = list.where((r) => r.displayName.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  List<AdminCatalogReleaseRow> _visibleMissing() =>
      _filteredCatalogReleases().where((r) => !r.inVault).toList();

  void _toggleSelection(AdminCatalogReleaseRow row) {
    if (row.inVault) return;
    setState(() {
      if (_selectedIds.contains(row.cardsightId)) {
        _selectedIds.remove(row.cardsightId);
      } else {
        _selectedIds.add(row.cardsightId);
      }
    });
  }

  void _selectAllVisibleMissing() {
    setState(() {
      for (final r in _visibleMissing()) {
        _selectedIds.add(r.cardsightId);
      }
    });
  }

  void _clearSelection() => setState(_selectedIds.clear);

  Future<void> _loadCatalogReleases() async {
    if (_segment.isEmpty) return;
    setState(() {
      _loadingReleases = true;
      _catalogReleases = [];
      _selectedIds.clear();
    });
    try {
      final result = await ref.read(cardsServiceProvider).listAdminCatalogReleases(
        segment: _segment,
      );
      setState(() {
        _catalogReleases = result.releases;
        _missingCount = result.missing;
      });
    } finally {
      if (mounted) setState(() => _loadingReleases = false);
    }
  }

  Future<void> _importReleases({List<AdminCatalogReleaseRow>? rows}) async {
    final toImport = rows ??
        _catalogReleases.where((r) => _selectedIds.contains(r.cardsightId)).toList();
    if (toImport.isEmpty) return;

    setState(() => _importingReleases = true);
    try {
      final result = await ref.read(cardsServiceProvider).bulkImportReleases(
        segment: _segment,
        selected: toImport,
      );
      final imported = _tryParseInt(result['imported']) ?? 0;
      final total    = _tryParseInt(result['total']) ?? toImport.length;
      if (mounted) {
        setState(_selectedIds.clear);
        AdaptiveSnackBar.show(context,
          message: imported > 0
              ? '$imported new of $total release${total == 1 ? '' : 's'} imported'
              : 'Already in vault ($total checked)',
          type: imported > 0 ? AdaptiveSnackBarType.success : AdaptiveSnackBarType.info,
        );
        await _loadCatalogReleases();
      }
    } catch (e) {
      if (mounted) {
        AdaptiveSnackBar.show(context, message: 'Error: $e', type: AdaptiveSnackBarType.error);
      }
    } finally {
      if (mounted) setState(() => _importingReleases = false);
    }
  }

  Future<void> _confirmImportAllMissing() async {
    final missing = _catalogReleases.where((r) => !r.inVault).toList();
    if (missing.isEmpty) return;
    final ok = await showAdaptiveDialog<bool>(
      context: context,
      title: 'Import all missing?',
      content: 'Add ${missing.length} release shells for '
          '${_segmentToSport[_segment] ?? _segment} that are not in the vault yet.',
      cancelLabel: 'Cancel',
      confirmLabel: 'Import all',
    );
    if (ok == true && mounted) await _importReleases(rows: missing);
  }

  void _onReleaseRowTap(AdminCatalogReleaseRow row) {
    if (!row.inVault) {
      _toggleSelection(row);
      return;
    }
    _openReleaseSets(row);
  }

  Future<void> _openReleaseSets(AdminCatalogReleaseRow row) async {
    if (!row.inVault || row.vaultReleaseId == null) return;
    setState(() {
      _selectedRelease = row.toReleaseRecord(_segmentToSport[_segment] ?? '');
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
    final csId = _selectedRelease?.catalogImportReleaseKey;
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
        AdaptiveSnackBar.show(context, message: 'Error: $e', type: AdaptiveSnackBarType.error);
      }
    } finally {
      if (mounted) setState(() => _importingSets = false);
    }
  }

  Future<void> _importCardsForSet(SetRecord set) async {
    final release = _selectedRelease!;
    if (release.catalogImportReleaseKey == null || set.catalogImportSetKey == null) return;
    setState(() => _importingCards.add(set.id));
    try {
      await ref.read(cardsServiceProvider).importCardsForSet(
        cardsightReleaseId: release.catalogImportReleaseKey!,
        cardsightSetId: set.catalogImportSetKey!,
        setId: set.id,
      );
      await _loadSets();
    } catch (e) {
      if (mounted) {
        AdaptiveSnackBar.show(context, message: 'Error: $e', type: AdaptiveSnackBarType.error);
      }
    } finally {
      if (mounted) setState(() => _importingCards.remove(set.id));
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final navTop = StickyChromeScaffold.navToolbarExtent(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: buildGlassNavBar(
        context,
        centerTitle: false,
        title: Text('Catalog Admin', style: AppFonts.appBarTitle.copyWith(color: colors.onSurface)),
        actions: appBarShellTrailingActions(context),
      ),
      body: Padding(
        padding: EdgeInsets.only(top: navTop),
        child: switch (_step) {
          _AdminStep.releases => _buildReleasesView(colors),
          _AdminStep.sets     => _buildSetsView(colors),
        },
      ),
    );
  }

  // ── Releases view ─────────────────────────────────────────────

  Widget _buildReleasesView(ColorScheme colors) {
    final selectedCount = _selectedIds.length;
    final visibleMissing = _visibleMissing();
    return Column(
      children: [
        // Filters + import button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            children: [
              AdaptiveDropdown<String>(
                value: _segment,
                decoration: _inputDec('Sport'),
                hint: 'Select sport',
                items: [
                  const DropdownMenuItem(value: '', child: Text('Select sport')),
                  ..._sports.map((s) => DropdownMenuItem(value: s.$2, child: Text(s.$1))),
                ],
                onChanged: (v) {
                  final segment = v ?? '';
                  setState(() {
                    _segment = segment;
                    _selectedIds.clear();
                    if (segment.isEmpty) {
                      _catalogReleases = [];
                      _missingCount = 0;
                      _missingOnly = false;
                    }
                  });
                  if (segment.isNotEmpty) _loadCatalogReleases();
                },
              ),
              if (_catalogReleases.isNotEmpty && !_loadingReleases)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _missingCount > 0
                              ? '$_missingCount of ${_catalogReleases.length} not in vault'
                              : '${_catalogReleases.length} releases — all in vault',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                      FilterChip(
                        label: const Text('Missing only'),
                        selected: _missingOnly,
                        onSelected: (v) => setState(() => _missingOnly = v),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              if (visibleMissing.isNotEmpty && !_loadingReleases)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: _selectAllVisibleMissing,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Select visible (${visibleMissing.length})',
                          style: TextStyle(fontSize: 12, color: colors.primary),
                        ),
                      ),
                      if (selectedCount > 0) ...[
                        Text(' · ', style: TextStyle(color: colors.onSurface.withValues(alpha: 0.35))),
                        TextButton(
                          onPressed: _clearSelection,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Clear ($selectedCount)',
                            style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.55)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              GlassSearchField(
                controller: _searchCtrl,
                hint: 'Filter catalog by name or year…',
                onChanged: (_) => setState(() {}),
                onClear: () => setState(() => _searchCtrl.clear()),
              ),
              SizedBox(height: ChromeMetrics.searchBarBottomInset),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_importingReleases || selectedCount == 0)
                      ? null
                      : _importReleases,
                  child: _importingReleases
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          selectedCount == 0
                              ? 'Select releases to import'
                              : 'Import selected ($selectedCount)',
                        ),
                ),
              ),
              if (_missingCount > 0) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: AdaptiveButton.child(
                    onPressed: _importingReleases ? null : _confirmImportAllMissing,
                    style: AdaptiveButtonStyle.bordered,
                    color: AppTheme.primary,
                    padding: ChromeMetrics.adaptiveBorderedButtonPadding,
                    child: DefaultTextStyle.merge(
                      style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600),
                      child: Text('Import all missing ($_missingCount)'),
                    ),
                  ),
                ),
              ],

            ],
          ),
        ),
        const Divider(height: 1),
        // Release list
        Expanded(
          child: _segment.isEmpty
              ? Center(
                  child: Text(
                    'Select a sport to load catalog releases\nand compare with the vault.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurface.withValues(alpha: 0.4)),
                  ),
                )
              : _loadingReleases && _catalogReleases.isEmpty
              ? const Center(child: CardFanLoader())
              : Builder(builder: (context) {
                  final filtered = _filteredCatalogReleases();
                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        _catalogReleases.isEmpty
                            ? 'No releases returned from catalog for this sport.'
                            : 'No results match your filters.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurface.withValues(alpha: 0.4)),
                      ),
                    );
                  }
                  return ListView.separated(
                      padding: const EdgeInsets.only(
                        bottom: ChromeMetrics.shellTabBarReserveHeight,
                      ),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = filtered[i];
                        final selected = _selectedIds.contains(r.cardsightId);
                        return AdaptiveListTile(
                          hideBottomDivider: true,
                          leading: r.inVault
                              ? _StatusDot(imported: r.importedSetCount, total: r.setCount)
                              : SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: Checkbox(
                                    value: selected,
                                    onChanged: (_) => _toggleSelection(r),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                          title: Text(
                            r.displayName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: r.inVault
                                  ? null
                                  : colors.onSurface.withValues(alpha: selected ? 1 : 0.85),
                            ),
                          ),
                          subtitle: Text(
                            r.inVault
                                ? '${r.setCount} sets in vault'
                                : selected ? 'Selected for import' : 'Tap to select',
                            style: TextStyle(
                              fontSize: 12,
                              color: r.inVault
                                  ? null
                                  : colors.primary.withValues(alpha: selected ? 1 : 0.75),
                            ),
                          ),
                          trailing: r.inVault
                              ? const Icon(Icons.chevron_right, size: 18)
                              : null,
                          onTap: () => _onReleaseRowTap(r),
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
                          if (_selectedRelease?.catalogImportReleaseKey != null)
                            AdaptiveButton.child(
                              onPressed: _importingSets ? null : _importSets,
                              style: AdaptiveButtonStyle.filled,
                              color: AppTheme.primary,
                              child: DefaultTextStyle.merge(
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.download_outlined, size: 16, color: Colors.white),
                                    SizedBox(width: 8),
                                    Text('Import sets from catalog'),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(
                        bottom: ChromeMetrics.shellTabBarReserveHeight,
                      ),
                      itemCount: _sets.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final s = _sets[i];
                        final isImporting = _importingCards.contains(s.id);
                        final isImported = s.importedCount > 0;
                        return AdaptiveListTile(
                          hideBottomDivider: true,
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
        if (_sets.isNotEmpty && _selectedRelease?.catalogImportReleaseKey != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              16,
              8,
              16,
              ChromeMetrics.shellTabBarReserveHeight,
            ),
            child: SizedBox(
              width: double.infinity,
              child: AdaptiveButton.child(
                onPressed: _importingSets ? null : _importSets,
                style: AdaptiveButtonStyle.bordered,
                color: AppTheme.primary,
                padding: ChromeMetrics.adaptiveBorderedButtonPadding,
                child: DefaultTextStyle.merge(
                  style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh, size: 16, color: AppTheme.primary),
                      SizedBox(width: 8),
                      Text('Re-import sets from catalog'),
                    ],
                  ),
                ),
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
