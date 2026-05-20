import 'dart:async' show unawaited;

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

String _formatCount(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
  return '${(n / 1000000).toStringAsFixed(1)}M';
}

String _releaseCoverageSubtitle(AdminCatalogReleaseRow r) {
  if (!r.inVault || r.setCount == 0) {
    return '${r.setCount} sets in vault';
  }
  final parts = <String>['${r.setCount} sets'];
  if (r.setsWithParallels > 0) {
    parts.add('${_formatCount(r.setsWithParallels)}/${_formatCount(r.setCount)} parallels');
  }
  if (r.importedSetCount > 0) {
    parts.add('${_formatCount(r.importedSetCount)}/${_formatCount(r.setCount)} with cards');
  }
  if (r.expectedCardTotal > 0) {
    parts.add('${_formatCount(r.vaultCardTotal)}/${_formatCount(r.expectedCardTotal)} cards');
  } else if (r.vaultCardTotal > 0) {
    parts.add('${_formatCount(r.vaultCardTotal)} cards');
  }
  return parts.join(' · ');
}

String _setCoverageSubtitle(SetRecord s, CatalogSetCoverage? cov) {
  final parts = <String>[];
  if (cov != null) {
    final parExpected = cov.expectedParallelCount;
    if (parExpected != null && parExpected > 0) {
      parts.add('${cov.parallelCount}/$parExpected parallels');
    } else {
      parts.add('${cov.parallelCount} parallel${cov.parallelCount == 1 ? '' : 's'}');
    }
    final expected = cov.expectedCardCount ?? s.cardCount;
    if (expected != null && expected > 0) {
      parts.add('${cov.vaultCardCount}/$expected cards');
    } else if (cov.vaultCardCount > 0) {
      parts.add('${cov.vaultCardCount} cards');
    } else if (expected != null) {
      parts.add('$expected cards expected');
    }
  } else if (s.cardCount != null) {
    parts.add(s.importedCount > 0
        ? '${s.importedCount}/${s.cardCount} cards'
        : '${s.cardCount} cards');
  }
  return parts.join(' · ');
}

bool _setNeedsImport(CatalogSetCoverage? cov, SetRecord s) {
  if (cov == null) {
    return s.importedCount == 0 || s.cardCount == null || s.importedCount < (s.cardCount ?? 0);
  }
  return !cov.parallelsComplete || !cov.cardsComplete;
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
  /// Null until the admin picks a sport (no catalog API calls before then).
  String? _segment;
  bool _importingReleases = false;

  List<AdminCatalogReleaseRow> _catalogReleases = [];
  int _missingCount = 0;
  bool _vaultOnlyCatalog = false;
  bool _catalogFromCache = false;
  String? _catalogNotice;
  bool _loadingReleases = false;
  bool _missingOnly = false;
  final Set<String> _selectedIds = {};
  final _searchCtrl = TextEditingController();

  ReleaseRecord? _selectedRelease;

  // ── Sets ──────────────────────────────────────────────────────
  List<SetRecord> _sets = [];
  Map<String, CatalogSetCoverage> _setCoverage = {};
  CatalogReleaseCoverage? _releaseCoverage;
  bool _loadingSets = false;
  bool _importingSets = false;
  bool _setsIncompleteOnly = false;
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

  Future<void> _loadCatalogReleases({bool refresh = false}) async {
    final segment = _segment;
    if (segment == null || segment.isEmpty) return;
    setState(() {
      _loadingReleases = true;
      if (!refresh) {
        _catalogReleases = [];
        _selectedIds.clear();
      }
    });
    try {
      final result = await ref.read(cardsServiceProvider).listAdminCatalogReleases(
        segment: segment,
        refresh: refresh,
      );
      setState(() {
        _catalogReleases = result.releases;
        _missingCount = result.missing;
        _vaultOnlyCatalog = result.vaultOnly;
        _catalogFromCache = result.fromCache;
        _catalogNotice = result.notice;
      });
    } catch (e) {
      if (mounted) {
        AdaptiveSnackBar.show(
          context,
          message: 'Could not load catalog releases: $e',
          type: AdaptiveSnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _loadingReleases = false);
    }
  }

  Future<void> _importReleases({List<AdminCatalogReleaseRow>? rows}) async {
    final toImport = rows ??
        _catalogReleases.where((r) => _selectedIds.contains(r.cardsightId)).toList();
    if (toImport.isEmpty) return;
    final segment = _segment;
    if (segment == null) return;

    setState(() => _importingReleases = true);
    try {
      final result = await ref.read(cardsServiceProvider).bulkImportReleases(
        segment: segment,
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
          '${_segmentToSport[_segment!] ?? _segment} that are not in the vault yet.',
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
      _selectedRelease = row.toReleaseRecord(_segmentToSport[_segment!] ?? '');
      _step = _AdminStep.sets;
      _sets = [];
      _setCoverage = {};
      _releaseCoverage = null;
      _setsIncompleteOnly = false;
      _searchCtrl.clear();
    });
    await _loadSets();
  }

  List<SetRecord> _filteredSets() {
    var list = _sets;
    final q = _searchCtrl.text.toLowerCase().trim();
    if (q.isNotEmpty) {
      list = list.where((s) => s.name.toLowerCase().contains(q)).toList();
    }
    if (_setsIncompleteOnly) {
      list = list.where((s) => _setNeedsImport(_setCoverage[s.id], s)).toList();
    }
    return list;
  }

  // ── Set methods ───────────────────────────────────────────────

  Future<void> _loadSets() async {
    final releaseId = _selectedRelease!.id;
    setState(() => _loadingSets = true);
    try {
      final state = await ref
          .read(cardsServiceProvider)
          .loadCatalogImportStateForRelease(releaseId);
      if (!mounted) return;
      setState(() {
        _sets = state.sets;
        _setCoverage = state.setCoverage;
        _releaseCoverage = state.releaseCoverage;
      });
      _syncCurrentReleaseInCatalogList(state.releaseCoverage);
    } finally {
      if (mounted) setState(() => _loadingSets = false);
    }
  }

  void _syncCurrentReleaseInCatalogList(CatalogReleaseCoverage cov) {
    final csId = _selectedRelease?.catalogImportReleaseKey;
    if (csId == null) return;
    final idx = _catalogReleases.indexWhere((r) => r.cardsightId == csId);
    if (idx < 0) return;
    final old = _catalogReleases[idx];
    setState(() {
      _catalogReleases[idx] = AdminCatalogReleaseRow(
        cardsightId: old.cardsightId,
        name: old.name,
        year: old.year,
        inVault: old.inVault,
        vaultReleaseId: old.vaultReleaseId,
        setCount: cov.setCount,
        importedSetCount: cov.setsWithCards,
        setsWithParallels: cov.setsWithParallels,
        setsCardsComplete: cov.setsCardsComplete,
        vaultCardTotal: cov.vaultCardTotal,
        expectedCardTotal: cov.expectedCardTotal,
      );
    });
  }

  Future<void> _importRelease() async {
    final csId = _selectedRelease?.catalogImportReleaseKey;
    if (csId == null) return;
    setState(() => _importingSets = true);
    try {
      final result = await ref.read(cardsServiceProvider).importReleaseCatalog(
        cardsightReleaseId: csId,
        releaseName: _selectedRelease!.name,
        releaseYear: _selectedRelease!.year?.toString(),
      );
      await _loadSets();
      if (mounted) {
        var message =
            'Release imported: ${result.setsWithParallels}/${result.setsUpserted} sets, '
            '${result.cardsImported} cards';
        final failures = result.parallelErrors.length + result.cardErrors.length;
        if (failures > 0) {
          message += ' ($failures set issue${failures == 1 ? '' : 's'})';
        }
        AdaptiveSnackBar.show(
          context,
          message: message,
          type: failures == 0
              ? AdaptiveSnackBarType.success
              : AdaptiveSnackBarType.info,
        );
      }
    } catch (e) {
      if (mounted) {
        AdaptiveSnackBar.show(context, message: 'Error: $e', type: AdaptiveSnackBarType.error);
      }
    } finally {
      if (mounted) setState(() => _importingSets = false);
    }
  }

  Future<void> _importCardsForSet(SetRecord set, {bool showSnackBar = true}) async {
    final release = _selectedRelease!;
    if (release.catalogImportReleaseKey == null || set.catalogImportSetKey == null) return;
    setState(() => _importingCards.add(set.id));
    try {
      await ref.read(cardsServiceProvider).importCardsForSet(
        cardsightReleaseId: release.catalogImportReleaseKey!,
        cardsightSetId: set.catalogImportSetKey!,
        setId: set.id,
      );
      if (showSnackBar) await _loadSets();
      if (mounted && showSnackBar) {
        final cov = _setCoverage[set.id];
        final n = cov?.vaultCardCount ?? set.importedCount;
        AdaptiveSnackBar.show(
          context,
          message: 'Cards imported for ${set.name} ($n in vault)',
          type: AdaptiveSnackBarType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AdaptiveSnackBar.show(context, message: 'Error: $e', type: AdaptiveSnackBarType.error);
      }
      rethrow;
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
                commitOnDone: true,
                decoration: _inputDec('Sport'),
                hint: 'Select sport',
                items: _sports
                    .map((s) => DropdownMenuItem(value: s.$2, child: Text(s.$1)))
                    .toList(),
                onChanged: (segment) {
                  if (segment == null || segment.isEmpty) return;
                  setState(() {
                    _segment = segment;
                    _selectedIds.clear();
                    _missingOnly = false;
                  });
                  _loadCatalogReleases();
                },
              ),
              if (_segment != null &&
                  ((_catalogNotice?.isNotEmpty ?? false) ||
                      (_catalogFromCache && !_vaultOnlyCatalog)))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Material(
                    color: colors.tertiaryContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, size: 18, color: colors.tertiary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _catalogNotice ??
                                  'Loaded from cached CardSight index — use refresh to sync new releases.',
                              style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.85)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_segment != null &&
                  _catalogReleases.isNotEmpty &&
                  !_loadingReleases &&
                  !_vaultOnlyCatalog)
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
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: 'Refresh from CardSight',
                        visualDensity: VisualDensity.compact,
                        onPressed: _loadingReleases
                            ? null
                            : () => _loadCatalogReleases(refresh: true),
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
              if (_segment != null && visibleMissing.isNotEmpty && !_loadingReleases)
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
              if (_segment != null) ...[
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

            ],
          ),
        ),
        const Divider(height: 1),
        // Release list
        Expanded(
          child: _segment == null
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
                              ? _StatusDot(
                                  imported: r.setsCardsComplete > 0
                                      ? r.setsCardsComplete
                                      : r.importedSetCount,
                                  total: r.setCount,
                                )
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
                                ? _releaseCoverageSubtitle(r)
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
          onBack: () {
            setState(() {
              _step = _AdminStep.releases;
              _selectedRelease = null;
              _sets = [];
              _setCoverage = {};
              _releaseCoverage = null;
            });
            if (_segment != null) unawaited(_loadCatalogReleases());
          },
        ),
        if (_loadingSets || _importingSets || _importingCards.isNotEmpty)
          const LinearProgressIndicator(minHeight: 2),
        if (_releaseCoverage != null && _sets.isNotEmpty)
          _ReleaseCoverageBanner(coverage: _releaseCoverage!, colors: colors),
        if (_sets.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlassSearchField(
                  controller: _searchCtrl,
                  hint: 'Filter sets…',
                  onChanged: (_) => setState(() {}),
                  onClear: () => setState(() => _searchCtrl.clear()),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_sets.length} sets',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                    FilterChip(
                      label: const Text('Incomplete only'),
                      selected: _setsIncompleteOnly,
                      onSelected: (v) => setState(() => _setsIncompleteOnly = v),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        Expanded(
          child: _loadingSets && _sets.isEmpty
              ? const Center(child: CardFanLoader())
              : _sets.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('No sets in vault yet.',
                              style: TextStyle(color: colors.onSurface.withValues(alpha: 0.4))),
                          const SizedBox(height: 16),
                          if (_selectedRelease?.catalogImportReleaseKey != null)
                            AdaptiveButton.child(
                              onPressed: _importingSets ? null : _importRelease,
                              style: AdaptiveButtonStyle.filled,
                              color: AppTheme.primary,
                              child: DefaultTextStyle.merge(
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.download_outlined, size: 16, color: Colors.white),
                                    SizedBox(width: 8),
                                    Text('Import release'),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  : Builder(builder: (context) {
                      final filtered = _filteredSets();
                      if (filtered.isEmpty) {
                        return Center(
                          child: Text(
                            'No sets match your filter.',
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
                        final s = filtered[i];
                        final cov = _setCoverage[s.id];
                        final isImporting = _importingCards.contains(s.id);
                        final cardsComplete = cov?.cardsComplete ?? false;
                        final parallelsComplete = cov?.parallelsComplete ?? false;
                        final hasCards = cov?.hasCards ?? s.importedCount > 0;
                        final cardTotal = cov?.expectedCardCount ?? s.cardCount ?? 0;
                        final cardImported = cov?.vaultCardCount ?? s.importedCount;
                        return AdaptiveListTile(
                          hideBottomDivider: true,
                          leading: _StatusDot(
                            imported: cardsComplete
                                ? cardTotal
                                : cardImported,
                            total: cardTotal > 0 ? cardTotal : (hasCards ? 1 : 0),
                          ),
                          title: Text(
                            s.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            _setCoverageSubtitle(s, cov),
                            style: TextStyle(
                              fontSize: 12,
                              color: (!parallelsComplete || !cardsComplete)
                                  ? colors.error.withValues(alpha: 0.85)
                                  : null,
                            ),
                          ),
                          trailing: isImporting
                              ? const SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : (hasCards && cardsComplete)
                                  ? IconButton(
                                      icon: Icon(Icons.refresh, size: 18, color: colors.onSurface.withValues(alpha: 0.4)),
                                      tooltip: 'Re-import cards',
                                      onPressed: () => _importCardsForSet(s),
                                    )
                                  : null,
                        );
                      },
                    );
                    }),
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
                onPressed: _importingSets ? null : _importRelease,
                style: AdaptiveButtonStyle.bordered,
                color: AppTheme.primary,
                padding: ChromeMetrics.adaptiveBorderedButtonPadding,
                child: DefaultTextStyle.merge(
                  style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.download_outlined, size: 16, color: AppTheme.primary),
                      SizedBox(width: 8),
                      Text('Import release'),
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

// ── Release coverage summary (Phase 0) ────────────────────────────────────────

class _ReleaseCoverageBanner extends StatelessWidget {
  const _ReleaseCoverageBanner({required this.coverage, required this.colors});

  final CatalogReleaseCoverage coverage;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final c = coverage;
    final lines = <String>[
      '${c.setCount} sets',
      if (c.setCount > 0)
        '${c.setsWithParallels}/${c.setCount} with parallels',
      if (c.setCount > 0)
        '${c.setsWithCards}/${c.setCount} with cards',
      if (c.setsCardsComplete > 0)
        '${c.setsCardsComplete}/${c.setCount} card-complete',
    ];
    final cardLine = c.expectedCardTotal > 0
        ? '${_formatCount(c.vaultCardTotal)} / ${_formatCount(c.expectedCardTotal)} cards in vault'
        : c.vaultCardTotal > 0
            ? '${_formatCount(c.vaultCardTotal)} cards in vault'
            : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Import coverage',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 4),
              Text(lines.join(' · '), style: const TextStyle(fontSize: 13)),
              if (cardLine != null) ...[
                const SizedBox(height: 2),
                Text(cardLine, style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.65))),
              ],
            ],
          ),
        ),
      ),
    );
  }
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
