import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';
import '../models/cardhedge_image_search.dart';
import '../models/user_card.dart';
import '../utils/guide_grade_prices.dart';

int? _tryParseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  if (value is num) return value.toInt();
  return null;
}

double? _tryParseDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value);
  if (value is num) return value.toDouble();
  return null;
}

String _chNormKey(String? s) {
  if (s == null) return '';
  return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

bool _chNumbersRoughMatch(String? a, String? b) {
  if (a == null || b == null) return false;
  final na = a.replaceFirst(RegExp(r'^#'), '').trim().toLowerCase();
  final nb = b.replaceFirst(RegExp(r'^#'), '').trim().toLowerCase();
  if (na.isEmpty || nb.isEmpty) return false;
  if (na == nb) return true;
  final ia = int.tryParse(na);
  final ib = int.tryParse(nb);
  if (ia != null && ib != null && ia == ib) return true;
  return false;
}

bool _chPlayersRoughMatch(String a, String b) {
  final dp = a.toLowerCase().trim();
  final hp = b.toLowerCase().trim();
  if (dp.isEmpty || hp.isEmpty) return false;
  if (hp.contains(dp) || dp.contains(hp)) return true;
  final dTok = dp.split(RegExp(r'\s+')).where((e) => e.length > 2).toSet();
  final hTok = hp.split(RegExp(r'\s+')).where((e) => e.length > 2).toSet();
  return dTok.intersection(hTok).isNotEmpty;
}

/// Catalog parallel string for a CardHedge row — same as [CardHedgeImageSearchHit.displayParallelName]
/// (null/blank `variant` is already **Base** on the model).
String _chEffectiveParallelHint(CardHedgeImageSearchHit hit) {
  final s = hit.displayParallelName.trim();
  return s.isEmpty ? 'Base' : s;
}

SetParallel? _chPickParallel(List<SetParallel> parallels, String? parallelHint) {
  if (parallels.isEmpty) return null;
  final raw = parallelHint?.trim();
  final eff = (raw == null || raw.isEmpty) ? 'Base' : raw;
  // "Base" = catalog **default paper** variant: matches Postgres `_default_parallel_for_set`,
  // the `set_card_base_variants` view, and `catalog-import-cards` `pickBaseParallelId`.
  // There is not always a `set_parallels` row literally named "Base"; `master_card_definitions.parallel_id`
  // is NOT NULL and points at whichever parallel is default (often lowest `sort_order`).
  if (parallelLabelImpliesDefaultPaper(eff)) {
    return pickDefaultPaperParallel(parallels);
  }
  final target = _chNormKey(eff);
  if (target.isNotEmpty) {
    SetParallel? exact;
    final fuzzy = <SetParallel>[];
    for (final p in parallels) {
      final n = _chNormKey(p.name);
      if (n == target) {
        exact = p;
        break;
      }
      if (n.contains(target) || target.contains(n)) fuzzy.add(p);
    }
    if (exact != null) return exact;
    if (fuzzy.length == 1) return fuzzy.first;
    if (fuzzy.length > 1) {
      fuzzy.sort((a, b) => _chNormKey(b.name).length.compareTo(_chNormKey(a.name).length));
      return fuzzy.first;
    }
  }
  for (final p in parallels) {
    if (p.name.trim().toLowerCase() == 'base') return p;
  }
  return parallels.first;
}

SetRecord? _chPickSet(List<SetRecord> sets, String setNameHint) {
  if (sets.isEmpty) return null;
  final hint = setNameHint.trim();
  if (hint.isEmpty) return sets.length == 1 ? sets.first : null;
  final t = _chNormKey(hint);
  SetRecord? best;
  var bestScore = -1;
  for (final s in sets) {
    final n = _chNormKey(s.name);
    var score = 0;
    if (n == t) {
      score = 100;
    } else if (n.contains(t) || t.contains(n)) {
      score = 50;
    } else if (s.name.toLowerCase().contains(hint.toLowerCase())) {
      score = 25;
    }
    if (score > bestScore) {
      bestScore = score;
      best = s;
    }
  }
  return bestScore > 0 ? best : null;
}

String? _chPickSetCardId(List<Map<String, dynamic>> rows, String player, String? number) {
  String? bestId;
  var bestScore = -1;
  final numPresent = number != null && number.trim().isNotEmpty;
  for (final r in rows) {
    final pid = r['id'] as String?;
    if (pid == null) continue;
    final p = (r['player'] as String?)?.trim() ?? '';
    final cn = r['card_number'] as String?;
    if (numPresent && !_chNumbersRoughMatch(cn, number)) continue;
    var score = 0;
    if (_chPlayersRoughMatch(p, player)) {
      score += 8;
    } else if (p.toLowerCase().contains(player.toLowerCase())) {
      score += 4;
    }
    if (_chNumbersRoughMatch(cn, number)) score += 12;
    if (score > bestScore) {
      bestScore = score;
      bestId = pid;
    }
  }
  if (bestId == null) return null;
  if (numPresent && bestScore < 12) return null;
  if (!numPresent && bestScore < 8) return null;
  return bestId;
}

bool _scanSportIsBasketball(String scanSport) {
  final s = scanSport.trim().toLowerCase();
  return s == 'basketball' || s == 'nba';
}

/// When the scan picker sport string is empty (common on some routes), infer from CardHedge [category]
/// so release-year logic (e.g. basketball dual-year) still applies.
String _effectiveChScanSport(String scanSport, CardHedgeImageSearchHit hit) {
  if (scanSport.trim().isNotEmpty) return scanSport;
  final c = (hit.category ?? '').toLowerCase();
  if (c.contains('basketball') || c.contains('nba')) return 'Basketball';
  if (c.contains('football')) return 'Football';
  if (c.contains('baseball')) return 'Baseball';
  if (c.contains('hockey') || c.contains('nhl')) return 'Hockey';
  return scanSport;
}

List<ReleaseRecord> _mergeChReleaseRecords(Iterable<ReleaseRecord> a, Iterable<ReleaseRecord> b) {
  final byId = <String, ReleaseRecord>{};
  for (final r in a) {
    byId[r.id] = r;
  }
  for (final r in b) {
    byId[r.id] = r;
  }
  final list = byId.values.toList();
  list.sort((x, y) {
    final yx = x.year ?? 0;
    final yy = y.year ?? 0;
    if (yx != yy) return yy.compareTo(yx);
    return x.name.compareTo(y.name);
  });
  return list;
}

/// Injects batched `current_prices` rows under `master_card_definitions` for [UserCard.fromJson].
Map<String, dynamic> _mergeCurrentPricesIntoUserCardRow(
  Map<String, dynamic> row,
  Map<String, List<Map<String, dynamic>>> pricesByMaster,
) {
  final out = Map<String, dynamic>.from(row);
  final mid = row['master_card_id'] as String?;
  if (mid == null) return out;

  final masterRaw = out['master_card_definitions'];
  Map<String, dynamic>? masterMap;
  if (masterRaw is Map<String, dynamic>) {
    masterMap = Map<String, dynamic>.from(masterRaw);
  } else if (masterRaw is Map) {
    masterMap = Map<String, dynamic>.from(masterRaw);
  } else if (masterRaw is List && masterRaw.isNotEmpty) {
    final e = masterRaw.first;
    if (e is Map<String, dynamic>) {
      masterMap = Map<String, dynamic>.from(e);
    } else if (e is Map) {
      masterMap = Map<String, dynamic>.from(e);
    }
  }
  if (masterMap != null) {
    final batch = pricesByMaster[mid];
    if (batch != null && batch.isNotEmpty) {
      masterMap['current_prices'] = batch;
    } else {
      final embedded = masterMap['current_prices'];
      if (embedded is! List || embedded.isEmpty) {
        masterMap['current_prices'] = const <Map<String, dynamic>>[];
      }
    }
    out['master_card_definitions'] = masterMap;
  }
  return out;
}

class SetParallel {
  const SetParallel({required this.id, required this.name, this.serialMax, this.isAuto = false});
  final String id;
  final String name;
  final int? serialMax;
  final bool isAuto;

  factory SetParallel.fromJson(Map<String, dynamic> j) => SetParallel(
    id: j['id'] as String,
    name: j['name'] as String,
    serialMax: _tryParseInt(j['serial_max']),
    isAuto: j['is_auto'] as bool? ?? false,
  );
}

/// UI labels like "Base" / empty — not always a literal `set_parallels.name`.
bool parallelLabelImpliesDefaultPaper(String parallelName) {
  final n = parallelName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return n.isEmpty ||
      n == 'base' ||
      n == 'base set' ||
      n == 'base parallel' ||
      n == 'base card' ||
      n == 'baseset' ||
      n == 'baseparallel';
}

/// Default paper parallel — matches `set_card_base_variants` / edge `pickBaseParallelId`.
SetParallel? pickDefaultPaperParallel(List<SetParallel> parallels) {
  if (parallels.isEmpty) return null;
  for (final p in parallels) {
    if (p.name.trim().toLowerCase() == 'base') return p;
  }
  return parallels.first;
}

/// When false, the DB already has a `set_parallels` row whose name is `Base` (case-insensitive);
/// the catalog UI must not add a second synthetic "Base" tile (`parallel == null`).
bool catalogNeedsSyntheticBaseParallelTile(List<SetParallel> parallels) =>
    !parallels.any((p) => p.name.trim().toLowerCase() == 'base');

/// A–Z by name for catalog browse/search parallel lists ([getParallels] uses admin [sort_order]).
List<SetParallel> catalogParallelsSortedForDisplay(List<SetParallel> parallels) {
  final out = List<SetParallel>.from(parallels);
  out.sort((a, b) => a.name.trim().toLowerCase().compareTo(b.name.trim().toLowerCase()));
  return out;
}

/// Resolves a catalog/browse parallel label to a `set_parallels` row.
SetParallel? resolveSetParallelForCatalog(List<SetParallel> parallels, String parallelName) {
  if (parallels.isEmpty) return null;
  if (parallelLabelImpliesDefaultPaper(parallelName)) {
    return pickDefaultPaperParallel(parallels);
  }
  final target = parallelName.trim().toLowerCase();
  for (final p in parallels) {
    if (p.name.trim().toLowerCase() == target) return p;
  }
  return null;
}

class ReleaseRecord {
  const ReleaseRecord({
    required this.id,
    required this.name,
    this.year,
    this.sport,
    this.catalogImportReleaseKey,
    this.setCount = 0,
    this.importedSetCount = 0,
  });
  final String id;
  final String name;
  final int? year;
  final String? sport;
  /// External id for the catalog import provider (matches the import column on `releases`).
  final String? catalogImportReleaseKey;
  final int setCount;
  final int importedSetCount;

  factory ReleaseRecord.fromJson(Map<String, dynamic> j) {
    final setsRaw = (j['sets'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    int imported = 0;
    for (final s in setsRaw) {
      final defs = s['set_cards'] as List?;
      if (defs != null && defs.isNotEmpty && (_tryParseInt(defs[0]['count']) ?? 0) > 0) imported++;
    }
    return ReleaseRecord(
      id:               j['id'] as String,
      name:             j['name'] as String,
      year:             _tryParseInt(j['year']),
      sport:            j['sport'] as String?,
      catalogImportReleaseKey: j['cardsight_id'] as String?,
      setCount:         setsRaw.length,
      importedSetCount: imported,
    );
  }

  String get displayName => year != null ? '$year $name' : name;
}

class SetRecord {
  const SetRecord({
    required this.id,
    required this.name,
    this.cardCount,
    this.catalogImportSetKey,
    this.expectedParallelCount,
    this.importedCount = 0,
  });
  final String id;
  final String name;
  final int? cardCount;
  /// External id for the catalog import provider (matches the import column on `sets`).
  final String? catalogImportSetKey;
  /// CardSight `releases[].sets[].parallelCount` (stored as `sets.cardsight_parallel_count`).
  final int? expectedParallelCount;
  final int importedCount;

  factory SetRecord.fromJson(Map<String, dynamic> j) {
    final defsRaw = j['set_cards'] as List?;
    return SetRecord(
      id:            j['id'] as String,
      name:          j['name'] as String,
      cardCount:     _tryParseInt(j['card_count']),
      catalogImportSetKey: j['cardsight_id'] as String?,
      expectedParallelCount: _tryParseInt(j['cardsight_parallel_count']),
      importedCount: defsRaw != null && defsRaw.isNotEmpty ? (_tryParseInt(defsRaw[0]['count']) ?? 0) : 0,
    );
  }
}

class MasterCard {
  const MasterCard({
    required this.id,
    required this.player,
    this.cardNumber,
    this.isRookie = false,
    this.isAuto = false,
    this.isPatch = false,
    this.isSSP = false,
    this.serialMax,
    this.imageUrl,
    this.guidePriceCardId,
    this.gain,
  });
  final String id;
  final String player;
  final String? cardNumber;
  final bool isRookie;
  final bool isAuto;
  final bool isPatch;
  final bool isSSP;
  final int? serialMax;
  final String? imageUrl;
  /// Upstream guide-price card id when matched / persisted on this variant.
  final String? guidePriceCardId;
  /// Market change (typically percent); persisted on `master_card_definitions`.
  final double? gain;

  factory MasterCard.fromJson(Map<String, dynamic> j) => MasterCard(
    id: j['id'] as String,
    player: j['player'] as String? ?? '',
    cardNumber: j['card_number'] as String?,
    isRookie: j['is_rookie'] as bool? ?? false,
    isAuto: j['is_auto'] as bool? ?? false,
    isPatch: j['is_patch'] as bool? ?? false,
    isSSP: j['is_ssp'] as bool? ?? false,
    serialMax: _tryParseInt(j['serial_max']),
    imageUrl: j['image_url'] as String?,
    guidePriceCardId: (j['cardhedge_id'] as String?)?.trim().isNotEmpty == true ? j['cardhedge_id'] as String : null,
    gain: _tryParseDouble(j['gain']),
  );

  String get displayName => cardNumber != null ? '$player  #$cardNumber' : player;
}

/// One checklist row for a [set_card] in a set, optionally resolved to a parallel variant.
class SetChecklistSlot {
  const SetChecklistSlot({
    required this.setCardId,
    required this.masterCardId,
    required this.card,
  });

  final String setCardId;
  /// Variant id for the requested parallel; null when that parallel has no catalog row yet.
  final String? masterCardId;
  final MasterCard card;
}

class CatalogRelease {
  const CatalogRelease({required this.id, required this.name, required this.year, required this.segmentId});
  final String id;
  final String name;
  final String year;
  final String segmentId;

  factory CatalogRelease.fromJson(Map<String, dynamic> j) => CatalogRelease(
    id:        j['id'] as String,
    name:      j['name'] as String,
    year:      (j['year'] ?? '').toString(),
    segmentId: (j['segmentId'] ?? '') as String,
  );

  String get displayName => '$year $name';
}

/// Per-set import coverage from `catalog_set_coverage` (Phase 0 backfill visibility).
class CatalogSetCoverage {
  const CatalogSetCoverage({
    required this.setId,
    required this.vaultCardCount,
    this.expectedCardCount,
    required this.parallelCount,
    this.expectedParallelCount,
    required this.hasParallels,
    required this.hasCards,
    required this.cardsComplete,
  });

  final String setId;
  final int vaultCardCount;
  final int? expectedCardCount;
  final int parallelCount;
  /// CardSight catalog parallel count for this set (when known).
  final int? expectedParallelCount;
  final bool hasParallels;
  final bool hasCards;
  final bool cardsComplete;

  bool get parallelsComplete {
    final expected = expectedParallelCount;
    if (expected != null && expected > 0) return parallelCount >= expected;
    return hasParallels;
  }

  factory CatalogSetCoverage.fromJson(Map<String, dynamic> j) => CatalogSetCoverage(
    setId: j['set_id'] as String,
    vaultCardCount: _tryParseInt(j['vault_card_count']) ?? 0,
    expectedCardCount: _tryParseInt(j['expected_card_count']),
    parallelCount: _tryParseInt(j['parallel_count']) ?? 0,
    expectedParallelCount: _tryParseInt(
      j['expected_parallel_count'] ?? j['cardsight_parallel_count'],
    ),
    hasParallels: j['has_parallels'] as bool? ?? false,
    hasCards: j['has_cards'] as bool? ?? false,
    cardsComplete: j['cards_complete'] as bool? ?? false,
  );
}

/// Per-release rollup from `catalog_release_coverage`.
class CatalogReleaseCoverage {
  const CatalogReleaseCoverage({
    required this.releaseId,
    required this.setCount,
    required this.setsWithParallels,
    required this.setsWithCards,
    required this.setsCardsComplete,
    required this.vaultCardTotal,
    required this.expectedCardTotal,
  });

  final String releaseId;
  final int setCount;
  final int setsWithParallels;
  final int setsWithCards;
  final int setsCardsComplete;
  final int vaultCardTotal;
  final int expectedCardTotal;

  factory CatalogReleaseCoverage.fromJson(Map<String, dynamic> j) => CatalogReleaseCoverage(
    releaseId: j['release_id'] as String,
    setCount: _tryParseInt(j['set_count']) ?? 0,
    setsWithParallels: _tryParseInt(j['sets_with_parallels']) ?? 0,
    setsWithCards: _tryParseInt(j['sets_with_cards']) ?? 0,
    setsCardsComplete: _tryParseInt(j['sets_cards_complete']) ?? 0,
    vaultCardTotal: _tryParseInt(j['vault_card_total']) ?? 0,
    expectedCardTotal: _tryParseInt(j['expected_card_total']) ?? 0,
  );
}

int _jsonIntOrZero(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

/// CardSight release row for admin catalog — merged with vault import status.
class AdminCatalogReleaseRow {
  const AdminCatalogReleaseRow({
    required this.cardsightId,
    required this.name,
    this.year,
    required this.inVault,
    this.vaultReleaseId,
    int setCount = 0,
    int importedSetCount = 0,
    int setsWithParallels = 0,
    int setsCardsComplete = 0,
    int vaultCardTotal = 0,
    int expectedCardTotal = 0,
  })  : _setCount = setCount,
        _importedSetCount = importedSetCount,
        _setsWithParallels = setsWithParallels,
        _setsCardsComplete = setsCardsComplete,
        _vaultCardTotal = vaultCardTotal,
        _expectedCardTotal = expectedCardTotal;

  final String cardsightId;
  final String name;
  final int? year;
  final bool inVault;
  final String? vaultReleaseId;

  final int? _setCount;
  final int? _importedSetCount;
  final int? _setsWithParallels;
  final int? _setsCardsComplete;
  final int? _vaultCardTotal;
  final int? _expectedCardTotal;

  int get setCount => _setCount ?? 0;
  /// Sets with at least one `set_cards` row.
  int get importedSetCount => _importedSetCount ?? 0;
  int get setsWithParallels => _setsWithParallels ?? 0;
  int get setsCardsComplete => _setsCardsComplete ?? 0;
  int get vaultCardTotal => _vaultCardTotal ?? 0;
  int get expectedCardTotal => _expectedCardTotal ?? 0;

  factory AdminCatalogReleaseRow.fromJson(Map<String, dynamic> j) => AdminCatalogReleaseRow(
    cardsightId: j['cardsightId'] as String,
    name: j['name'] as String,
    year: _tryParseInt(j['year']),
    inVault: j['inVault'] as bool? ?? false,
    vaultReleaseId: j['vaultReleaseId'] as String?,
    setCount: _jsonIntOrZero(j, 'setCount'),
    importedSetCount: _jsonIntOrZero(j, 'importedSetCount'),
    setsWithParallels: _jsonIntOrZero(j, 'setsWithParallels'),
    setsCardsComplete: _jsonIntOrZero(j, 'setsCardsComplete'),
    vaultCardTotal: _jsonIntOrZero(j, 'vaultCardTotal'),
    expectedCardTotal: _jsonIntOrZero(j, 'expectedCardTotal'),
  );

  String get displayName => year != null ? '$year $name' : name;

  int resolvedYear() {
    if (year != null && year! > 1900) return year!;
    final m = RegExp(r'\b(19|20)\d{2}\b').firstMatch(name);
    if (m != null) return int.parse(m.group(0)!);
    return DateTime.now().year;
  }

  ReleaseRecord toReleaseRecord(String sport) => ReleaseRecord(
    id: vaultReleaseId!,
    name: name,
    year: year,
    sport: sport,
    catalogImportReleaseKey: cardsightId,
    setCount: setCount,
    importedSetCount: importedSetCount,
  );
}

class CatalogSetSummary {
  const CatalogSetSummary({required this.id, required this.name, this.parallelCount = 0, this.cardCount});
  final String id;
  final String name;
  final int parallelCount;
  final int? cardCount;

  factory CatalogSetSummary.fromJson(Map<String, dynamic> j) => CatalogSetSummary(
    id:            j['id'] as String,
    name:          j['name'] as String,
    parallelCount: _tryParseInt(j['parallelCount']) ?? 0,
    cardCount:     _tryParseInt(j['cardCount']),
  );
}

class LazyImportResult {
  const LazyImportResult({
    required this.releaseId,
    required this.releaseName,
    this.releaseSport,
    required this.setId,
    required this.setName,
    required this.parallels,
  });
  final String releaseId;
  final String releaseName;
  final String? releaseSport;
  final String setId;
  final String setName;
  final List<SetParallel> parallels;

  factory LazyImportResult.fromJson(Map<String, dynamic> j) => LazyImportResult(
    releaseId:    j['releaseId'] as String,
    releaseName:  j['releaseName'] as String,
    releaseSport: j['releaseSport'] as String?,
    setId:        j['setId'] as String,
    setName:      j['setName'] as String,
    parallels:    ((j['parallels'] as List?) ?? [])
        .map((p) => SetParallel.fromJson(p as Map<String, dynamic>))
        .toList(),
  );
}

/// How scan / catalog-search release+set ids map to this vault (see [classifyScanCatalogAnchor]).
enum ScanCatalogAnchorKind {
  /// No direct PK or `cardsight_id` match yet — use [resolveCardFromCatalog] so [lazyImportCatalog]
  /// can create the release/set when CardSight returns valid catalog keys.
  none,
  /// `releases.id` + `sets.id` are our PKs — use [resolveVaultAnchoredScanCard] so we never pass
  /// vault UUIDs into [lazyImportCatalog] as if they were CardSight ids.
  vaultPrimaryKeys,
  /// Ids are CardSight keys that match `releases.cardsight_id` / `sets.cardsight_id`.
  cardsightIds,
}

class CatalogSearchCardResult {
  const CatalogSearchCardResult({
    required this.id,
    required this.name,
    this.number,
    required this.setId,
    required this.setName,
    required this.releaseId,
    required this.attributes,
  });
  final String id;
  final String name;
  final String? number;
  final String setId;
  final String setName;
  final String releaseId;
  final List<String> attributes;

  factory CatalogSearchCardResult.fromJson(Map<String, dynamic> j) => CatalogSearchCardResult(
    id:        j['id'] as String,
    name:      j['name'] as String,
    number:    j['number'] as String?,
    setId:     j['setId'] as String,
    setName:   j['setName'] as String,
    releaseId: j['releaseId'] as String,
    attributes: List<String>.from(j['attributes'] as List? ?? []),
  );
}

class AddCardFormData {
  const AddCardFormData({
    this.masterCardId,
    this.setId,
    this.player = '',
    this.cardNumber,
    this.serialMax,
    this.isRookie = false,
    this.isAuto = false,
    this.isPatch = false,
    this.isSSP = false,
    this.parallelId,
    this.parallelName = 'Base',
    this.pricePaid,
    this.serialNumber,
    this.isGraded = false,
    this.grader = 'PSA',
    this.gradeValue,
  });
  final String? masterCardId;
  final String? setId;
  final String player;
  final String? cardNumber;
  final int? serialMax;
  final bool isRookie;
  final bool isAuto;
  final bool isPatch;
  final bool isSSP;
  final String? parallelId;
  final String parallelName;
  final double? pricePaid;
  final String? serialNumber;
  final bool isGraded;
  final String grader;
  final String? gradeValue;
}

/// Payload from `catalog-ensure-from-scan-selection` edge function.
class CatalogEnsureFromScanResult {
  const CatalogEnsureFromScanResult({
    required this.masterCardDefinitionsId,
    required this.setId,
    required this.releaseId,
    this.parallelId,
  });

  final String masterCardDefinitionsId;
  final String setId;
  final String releaseId;
  final String? parallelId;

  factory CatalogEnsureFromScanResult.fromJson(Map<String, dynamic> j) {
    final p = j['parallelId']?.toString().trim();
    return CatalogEnsureFromScanResult(
      masterCardDefinitionsId: (j['masterCardDefinitionsId'] ?? '').toString(),
      setId: (j['setId'] ?? '').toString(),
      releaseId: (j['releaseId'] ?? '').toString(),
      parallelId: (p != null && p.isNotEmpty) ? p : null,
    );
  }
}

/// Result of [CardsService.resolveCardHedgeHitForMasterDetail] for opening catalog master detail from scan.
class ChScanCatalogResolveResult {
  const ChScanCatalogResolveResult({
    required this.resolvedMasterCardId,
    required this.parallelName,
    this.parallel,
    this.release,
    this.set,
  });

  final String resolvedMasterCardId;
  final String parallelName;
  final SetParallel? parallel;
  final ReleaseRecord? release;
  final SetRecord? set;
}

class CardsService {
  CardsService(this._supabase);
  final SupabaseClient _supabase;

  /// Batch-load `current_prices` rows keyed by `master_card_id` (UUID-safe strings).
  Future<Map<String, List<Map<String, dynamic>>>> _fetchCurrentPricesGrouped(Set<String> masterIds) async {
    final out = <String, List<Map<String, dynamic>>>{};
    if (masterIds.isEmpty) return out;
    final cp = await _supabase
        .from('current_prices')
        .select('master_card_id, grade, price, fetched_at')
        .inFilter('master_card_id', masterIds.toList());
    for (final raw in cp as List) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final mid = m['master_card_id']?.toString().trim();
      if (mid == null || mid.isEmpty) continue;
      out.putIfAbsent(mid, () => []).add({
        'grade': m['grade'],
        'price': m['price'],
        'fetched_at': m['fetched_at'],
      });
    }
    return out;
  }

  /// Authoritative: pick `current_prices.price` for each copy’s slab (`is_graded`, `grader`, `grade` / `grade_value`).
  List<UserCard> _resolveCatalogPricesFromCurrentPricesTable(
    List<UserCard> cards,
    Map<String, List<Map<String, dynamic>>> byMaster,
  ) {
    return cards.map((c) {
      final mid = c.masterCardId?.trim();
      if (mid == null || mid.isEmpty) return c;
      final rows = byMaster[mid];
      if (rows == null || rows.isEmpty) return c;

      final gradeStr = c.grade?.trim();
      final gradeLabel = (gradeStr != null && gradeStr.isNotEmpty)
          ? gradeStr
          : c.gradeValue?.toString().trim();
      final gradeValueRaw = (gradeLabel == null || gradeLabel.isEmpty) ? null : gradeLabel;

      final spot = priceFromCurrentPricesRowsForUserCopy(
        rows,
        isGraded: c.isGraded,
        grader: c.grader,
        gradeValueRaw: gradeValueRaw,
      );

      final ch = parseEmbeddedCurrentPrices(rows);
      final maxFt = maxFetchedAtFromCurrentPriceRows(rows);

      final useSpot = spot != null && spot > 0;
      final useCh = guideGradeMapHasAnyPrice(ch);

      if (!useSpot && !useCh) return c;

      return UserCard.withResolvedCatalogTablePricing(
        c,
        catalogPriceFromCurrentPrices: useSpot ? spot : c.catalogPriceFromCurrentPrices,
        embeddedGuideGradePrices: useCh ? ch : c.embeddedGuideGradePrices,
        embeddedGuideGradePricesFetchedAt: maxFt ?? c.embeddedGuideGradePricesFetchedAt,
      );
    }).toList();
  }

  Future<List<UserCard>> loadUserCards() async {
    try {
      final data = await _supabase
          .from('user_cards')
          .select('''
              id, master_card_id, parallel_id, parallel_name,
              price_paid, current_value, previous_value, serial_number,
              is_graded, grader, grade_value, created_at,
              value_refreshed_at,
              master_card_definitions (
                id, image_url, is_auto, is_patch, is_ssp, serial_max,
                gain, cardhedge_id, cardhedge_fetched_at,
                current_prices ( grade, price, fetched_at ),
                set_cards (
                  player, card_number, is_rookie, image_url,
                  sets ( id, name, card_count, releases ( year, sport, name ) )
                )
              ),
              set_parallels!parallel_id ( name, serial_max, is_auto, color_hex )
            ''')
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 20));

      final rows = (data as List)
          .map((r) => Map<String, dynamic>.from(r as Map<String, dynamic>))
          .toList();
      final masterIds = <String>{};
      for (final r in rows) {
        final rawId = r['master_card_id'];
        if (rawId == null) continue;
        final id = rawId.toString().trim();
        if (id.isEmpty) continue;
        masterIds.add(id);
      }

      final pricesByMaster = await _fetchCurrentPricesGrouped(masterIds);

      final merged = rows
          .map((r) => UserCard.fromJson(_mergeCurrentPricesIntoUserCardRow(r, pricesByMaster)))
          .toList();
      return _resolveCatalogPricesFromCurrentPricesTable(merged, pricesByMaster);
    } on TimeoutException {
      throw Exception(
        'Loading cards timed out. Check your network connection and Supabase settings.',
      );
    }
  }

  Future<void> deleteCard(String cardId) async {
    await _supabase.from('user_cards').delete().eq('id', cardId);
  }

  Future<void> updateCard(String cardId, Map<String, dynamic> patch) async {
    await _supabase.from('user_cards').update(patch).eq('id', cardId);
  }

  Future<List<SetParallel>> getParallels(String setId) async {
    final data = await _supabase
        .from('set_parallels')
        .select('id, name, serial_max, is_auto')
        .eq('set_id', setId)
        .order('sort_order');
    return (data as List).map((r) => SetParallel.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<List<ReleaseRecord>> searchReleases(String query) async {
    var q = _supabase.from('releases').select('id, name, year, sport, cardsight_id, sets(id, set_cards(count))');
    if (query.trim().isNotEmpty) {
      q = q.ilike('name', '%${query.trim()}%');
    }
    final data = await q.order('year', ascending: false).limit(30);
    return (data as List).map((r) => ReleaseRecord.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// Browses releases from our DB — no API call. Paginated.
  Future<List<ReleaseRecord>> browseReleases({int? year, String? sport, int offset = 0, int limit = 30}) async {
    var q = _supabase.from('releases').select('id, name, year, sport, cardsight_id, sets(id, set_cards(count))');
    if (year != null) q = q.eq('year', year);
    if (sport != null && sport.isNotEmpty) q = q.eq('sport', sport);
    final data = await q
        .order('year', ascending: false)
        .order('name', ascending: true)
        .range(offset, offset + limit - 1);
    return (data as List).map((r) => ReleaseRecord.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// Lazily fetches sets for a release from the catalog API and caches them in DB.
  Future<List<SetRecord>> importSetsForRelease({
    required String cardsightReleaseId,
    String? releaseName,
    String? releaseYear,
    String? releaseSegmentId,
  }) async {
    final res = await _supabase.functions.invoke(
      'catalog-import-sets',
      body: {
        'cardsightReleaseId': cardsightReleaseId,
        if (releaseName    case final v?) 'releaseName':      v,
        if (releaseYear    case final v?) 'releaseYear':      v,
        if (releaseSegmentId case final v?) 'releaseSegmentId': v,
      },
    );
    if (res.status != 200) throw Exception('Import sets failed: ${res.status}');
    final list = ((res.data as Map<String, dynamic>)['sets'] as List?) ?? [];
    return list.map((r) => SetRecord.fromJson({
      'id':           (r as Map<String, dynamic>)['id'],
      'name':         r['name'],
      'card_count':   r['cardCount'],
      'cardsight_id': (r as Map<String, dynamic>)['cardsightId'],
      'cardsight_parallel_count': r['parallelCount'],
    })).toList();
  }

  /// Admin: full release import — sets, parallels, and checklist cards (no images).
  Future<({
    String releaseId,
    int setsUpserted,
    int setsWithParallels,
    int parallelDefinitionsUpserted,
    int cardsImported,
    int setCardsMerged,
    List<String> parallelErrors,
    List<String> cardErrors,
  })> importReleaseCatalog({
    required String cardsightReleaseId,
    String? releaseName,
    String? releaseYear,
    String? releaseSegmentId,
  }) async {
    final res = await _supabase.functions.invoke(
      'catalog-import-release',
      body: {
        'cardsightReleaseId': cardsightReleaseId,
        if (releaseName case final v?) 'releaseName': v,
        if (releaseYear case final v?) 'releaseYear': v,
        if (releaseSegmentId case final v?) 'releaseSegmentId': v,
      },
    );
    if (res.status != 200) {
      throw Exception(_functionErrorMessage(res, 'Import release failed'));
    }
    final data = res.data as Map<String, dynamic>;
    List<String> mapErrors(String key) {
      final list = (data[key] as List?) ?? [];
      return list
          .map((e) {
            final m = e as Map<String, dynamic>;
            return '${m['setName']}: ${m['error']}';
          })
          .toList();
    }
    return (
      releaseId: data['releaseId'] as String? ?? '',
      setsUpserted: _tryParseInt(data['setsUpserted']) ?? 0,
      setsWithParallels: _tryParseInt(data['setsWithParallels']) ?? 0,
      parallelDefinitionsUpserted: _tryParseInt(data['parallelDefinitionsUpserted']) ?? 0,
      cardsImported: _tryParseInt(data['cardsImported']) ?? 0,
      setCardsMerged: _tryParseInt(data['setCardsMerged']) ?? 0,
      parallelErrors: mapErrors('parallelErrors'),
      cardErrors: mapErrors('cardErrors'),
    );
  }

  /// Admin: upsert all sets for a release and import every set's parallels from CardSight.
  Future<({
    int setsUpserted,
    int setsWithParallels,
    int parallelDefinitionsUpserted,
    List<String> parallelErrors,
  })> hydrateReleaseCatalog({
    required String cardsightReleaseId,
    String? releaseName,
    String? releaseYear,
    String? releaseSegmentId,
  }) async {
    final res = await _supabase.functions.invoke(
      'catalog-hydrate-release',
      body: {
        'cardsightReleaseId': cardsightReleaseId,
        if (releaseName case final v?) 'releaseName': v,
        if (releaseYear case final v?) 'releaseYear': v,
        if (releaseSegmentId case final v?) 'releaseSegmentId': v,
      },
    );
    if (res.status != 200) {
      throw Exception(_functionErrorMessage(res, 'Hydrate release failed'));
    }
    final data = res.data as Map<String, dynamic>;
    final errors = (data['parallelErrors'] as List?) ?? [];
    return (
      setsUpserted: _tryParseInt(data['setsUpserted']) ?? 0,
      setsWithParallels: _tryParseInt(data['setsWithParallels']) ?? 0,
      parallelDefinitionsUpserted: _tryParseInt(data['parallelDefinitionsUpserted']) ?? 0,
      parallelErrors: errors
          .map((e) {
            final m = e as Map<String, dynamic>;
            return '${m['setName']}: ${m['error']}';
          })
          .toList(),
    );
  }

  Future<List<SetRecord>> getSetsForRelease(String releaseId) async {
    final data = await _supabase
        .from('sets')
        .select('id, name, card_count, cardsight_id, cardsight_parallel_count, set_cards(count)')
        .eq('release_id', releaseId)
        .order('name', ascending: true);
    return (data as List).map((r) => SetRecord.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// CardSight `releases/{id}.sets[]` — `metaOnly` (no vault writes).
  Future<List<({String cardsightId, int parallelCount, int? cardCount})>> fetchCardsightReleaseSetMeta(
    String cardsightReleaseId,
  ) async {
    final res = await _supabase.functions.invoke(
      'catalog-import-sets',
      body: {
        'cardsightReleaseId': cardsightReleaseId,
        'metaOnly': true,
      },
    );
    if (res.status != 200) {
      throw Exception(_functionErrorMessage(res, 'Release set meta failed'));
    }
    final list = ((res.data as Map<String, dynamic>)['sets'] as List?) ?? [];
    return list.map((raw) {
      final r = raw as Map<String, dynamic>;
      return (
        cardsightId: r['cardsightId'] as String,
        parallelCount: _tryParseInt(r['parallelCount']) ?? 0,
        cardCount: _tryParseInt(r['cardCount']),
      );
    }).toList();
  }

  /// Persists `sets[].parallelCount` from the CardSight release payload onto vault rows.
  Future<void> syncCardsightParallelCountsForRelease({
    required String vaultReleaseId,
    required String cardsightReleaseId,
  }) async {
    final meta = await fetchCardsightReleaseSetMeta(cardsightReleaseId);
    for (final row in meta) {
      await _supabase
          .from('sets')
          .update({'cardsight_parallel_count': row.parallelCount})
          .eq('release_id', vaultReleaseId)
          .eq('cardsight_id', row.cardsightId);
    }
  }

  /// Per-set coverage rows for admin backfill (view `catalog_set_coverage`).
  Future<Map<String, CatalogSetCoverage>> getCatalogSetCoverageForRelease(String releaseId) async {
    final data = await _supabase
        .from('catalog_set_coverage')
        .select(
          'set_id, vault_card_count, expected_card_count, expected_parallel_count, '
          'parallel_count, has_parallels, has_cards, cards_complete, parallels_complete',
        )
        .eq('release_id', releaseId);
    final out = <String, CatalogSetCoverage>{};
    for (final row in data as List) {
      final cov = CatalogSetCoverage.fromJson(Map<String, dynamic>.from(row as Map));
      out[cov.setId] = cov;
    }
    return out;
  }

  /// Release-level rollup (view `catalog_release_coverage`).
  Future<CatalogReleaseCoverage?> getCatalogReleaseCoverage(String releaseId) async {
    final data = await _supabase
        .from('catalog_release_coverage')
        .select(
          'release_id, set_count, sets_with_parallels, sets_with_cards, '
          'sets_cards_complete, expected_card_total, vault_card_total',
        )
        .eq('release_id', releaseId)
        .maybeSingle();
    if (data == null) return null;
    return CatalogReleaseCoverage.fromJson(Map<String, dynamic>.from(data));
  }

  /// Parallel row counts per set (live table read — use after imports).
  Future<Map<String, int>> getParallelCountsBySetIds(List<String> setIds) async {
    if (setIds.isEmpty) return {};
    final counts = <String, int>{};
    const chunk = 80;
    for (var i = 0; i < setIds.length; i += chunk) {
      final slice = setIds.sublist(i, i + chunk > setIds.length ? setIds.length : i + chunk);
      final data = await _supabase.from('set_parallels').select('set_id').inFilter('set_id', slice);
      for (final row in data as List) {
        final sid = (row as Map<String, dynamic>)['set_id'] as String;
        counts[sid] = (counts[sid] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Merges coverage view rows with fresh `SetRecord` embed counts and parallel totals.
  Map<String, CatalogSetCoverage> mergeCatalogSetCoverage({
    required List<SetRecord> sets,
    required Map<String, CatalogSetCoverage> fromView,
    required Map<String, int> parallelCounts,
  }) {
    final out = <String, CatalogSetCoverage>{};
    for (final s in sets) {
      final v = fromView[s.id];
      final vaultCards = _maxInt(v?.vaultCardCount ?? 0, s.importedCount);
      final expected = v?.expectedCardCount ?? s.cardCount;
      final parallels = _maxInt(v?.parallelCount ?? 0, parallelCounts[s.id] ?? 0);
      final expectedParallels = s.expectedParallelCount ?? v?.expectedParallelCount;
      final hasParallels = parallels > 0 || (v?.hasParallels ?? false);
      final hasCards = vaultCards > 0 || (v?.hasCards ?? false);
      final cardsComplete = expected != null && expected > 0
          ? vaultCards >= expected
          : (v?.cardsComplete ?? false) || (vaultCards > 0 && s.cardCount == null);
      out[s.id] = CatalogSetCoverage(
        setId: s.id,
        vaultCardCount: vaultCards,
        expectedCardCount: expected,
        parallelCount: parallels,
        expectedParallelCount: expectedParallels,
        hasParallels: hasParallels,
        hasCards: hasCards,
        cardsComplete: cardsComplete,
      );
    }
    return out;
  }

  /// Roll up set-level coverage when the release view is missing or stale.
  CatalogReleaseCoverage buildReleaseCoverageFromSets({
    required String releaseId,
    required List<SetRecord> sets,
    required Map<String, CatalogSetCoverage> setCoverage,
  }) {
    var setsWithParallels = 0;
    var setsWithCards = 0;
    var setsCardsComplete = 0;
    var vaultCardTotal = 0;
    var expectedCardTotal = 0;
    for (final s in sets) {
      final c = setCoverage[s.id];
      if (c == null) continue;
      if (c.parallelsComplete) setsWithParallels++;
      if (c.hasCards) setsWithCards++;
      if (c.cardsComplete) setsCardsComplete++;
      vaultCardTotal += c.vaultCardCount;
      if (c.expectedCardCount != null) expectedCardTotal += c.expectedCardCount!;
    }
    return CatalogReleaseCoverage(
      releaseId: releaseId,
      setCount: sets.length,
      setsWithParallels: setsWithParallels,
      setsWithCards: setsWithCards,
      setsCardsComplete: setsCardsComplete,
      vaultCardTotal: vaultCardTotal,
      expectedCardTotal: expectedCardTotal,
    );
  }

  int _maxInt(int a, int b) => a > b ? a : b;

  /// Sets + merged coverage for admin release detail (always reflects latest imports).
  Future<({
    List<SetRecord> sets,
    Map<String, CatalogSetCoverage> setCoverage,
    CatalogReleaseCoverage releaseCoverage,
  })> loadCatalogImportStateForRelease(String releaseId) async {
    final sets = await getSetsForRelease(releaseId);
    Map<String, CatalogSetCoverage> fromView = {};
    try {
      fromView = await getCatalogSetCoverageForRelease(releaseId);
    } catch (_) {}
    var workingSets = sets;
    final needsParallelMeta = workingSets.any(
      (s) => s.expectedParallelCount == null && (s.catalogImportSetKey?.isNotEmpty ?? false),
    );
    if (needsParallelMeta) {
      final rel = await _supabase
          .from('releases')
          .select('cardsight_id')
          .eq('id', releaseId)
          .maybeSingle();
      final csReleaseId = (rel?['cardsight_id'] as String?)?.trim();
      if (csReleaseId != null && csReleaseId.isNotEmpty) {
        try {
          await syncCardsightParallelCountsForRelease(
            vaultReleaseId: releaseId,
            cardsightReleaseId: csReleaseId,
          );
          workingSets = await getSetsForRelease(releaseId);
        } catch (_) {}
      }
    }

    final parallelCounts = await getParallelCountsBySetIds(workingSets.map((s) => s.id).toList());
    final setCoverage = mergeCatalogSetCoverage(
      sets: workingSets,
      fromView: fromView,
      parallelCounts: parallelCounts,
    );
    CatalogReleaseCoverage? releaseCov;
    try {
      releaseCov = await getCatalogReleaseCoverage(releaseId);
    } catch (_) {}
    final mergedRelease = buildReleaseCoverageFromSets(
      releaseId: releaseId,
      sets: workingSets,
      setCoverage: setCoverage,
    );
    final releaseCoverage = CatalogReleaseCoverage(
      releaseId: releaseId,
      setCount: _maxInt(releaseCov?.setCount ?? 0, mergedRelease.setCount),
      setsWithParallels: _maxInt(releaseCov?.setsWithParallels ?? 0, mergedRelease.setsWithParallels),
      setsWithCards: _maxInt(releaseCov?.setsWithCards ?? 0, mergedRelease.setsWithCards),
      setsCardsComplete: _maxInt(releaseCov?.setsCardsComplete ?? 0, mergedRelease.setsCardsComplete),
      vaultCardTotal: _maxInt(releaseCov?.vaultCardTotal ?? 0, mergedRelease.vaultCardTotal),
      expectedCardTotal: _maxInt(releaseCov?.expectedCardTotal ?? 0, mergedRelease.expectedCardTotal),
    );
    return (sets: workingSets, setCoverage: setCoverage, releaseCoverage: releaseCoverage);
  }

  /// Looks up `releases.cardsight_id` for a CardSight set id already stored on `sets.cardsight_id`.
  Future<String?> _cardsightReleaseIdFromCardsightSetId(String cardsightSetId) async {
    final cs = cardsightSetId.trim();
    if (cs.isEmpty) return null;
    try {
      final setRow = await _supabase.from('sets').select('release_id').eq('cardsight_id', cs).maybeSingle();
      if (setRow == null) return null;
      final rid = setRow['release_id'] as String?;
      if (rid == null || rid.isEmpty) return null;
      final relRow =
          await _supabase.from('releases').select('cardsight_id').eq('id', rid).maybeSingle();
      if (relRow == null) return null;
      final out = (relRow['cardsight_id'] as String?)?.trim();
      return (out != null && out.isNotEmpty) ? out : null;
    } catch (_) {
      return null;
    }
  }

  /// Lazily imports all cards for a set from the catalog API and caches them in DB.
  /// Returns request + HTTP status + parsed body for diagnostics.
  Future<Map<String, dynamic>> importCardsForSetDetailed({
    required String cardsightReleaseId,
    required String cardsightSetId,
    required String vaultSetId,
  }) async {
    final body = <String, dynamic>{
      'cardsightReleaseId': cardsightReleaseId,
      'cardsightSetId': cardsightSetId,
      'setId': vaultSetId,
    };
    final res = await _supabase.functions.invoke('catalog-import-cards', body: body);
    final data = res.data;
    Object? serializable = data;
    if (data is Map) {
      serializable = Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{
      'request': body,
      'httpStatus': res.status,
      'responseBody': serializable,
    };
  }

  /// Lazily imports all cards for a set from the catalog API and caches them in DB.
  Future<void> importCardsForSet({
    required String cardsightReleaseId,
    required String cardsightSetId,
    required String setId,
  }) async {
    final r = await importCardsForSetDetailed(
      cardsightReleaseId: cardsightReleaseId,
      cardsightSetId: cardsightSetId,
      vaultSetId: setId,
    );
    final status = r['httpStatus'];
    if (status is! int || status != 200) {
      throw Exception('Import cards failed: $status');
    }
  }

  /// Server-side: lazy-import spine, import cards, upsert parallel if needed, hydrate CardHedge prices.
  /// Returns null when the edge call fails or returns an error payload.
  Future<CatalogEnsureFromScanResult?> ensureCatalogFromScanSelection({
    required String cardsightReleaseId,
    required String cardsightSetId,
    required String cardsightCardId,
    required String releaseName,
    required int releaseYear,
    String releaseSegmentId = '',
    String? cardHedgeCardId,
    String? cardHedgeVariant,
    String? parallelName,
  }) async {
    final res = await _supabase.functions.invoke(
      'catalog-ensure-from-scan-selection',
      body: {
        'cardsightReleaseId': cardsightReleaseId,
        'cardsightSetId': cardsightSetId,
        'cardsightCardId': cardsightCardId,
        'releaseName': releaseName,
        'releaseYear': releaseYear,
        'releaseSegmentId': releaseSegmentId,
        if (cardHedgeCardId != null && cardHedgeCardId.trim().isNotEmpty) 'cardHedgeCardId': cardHedgeCardId.trim(),
        if (cardHedgeVariant != null && cardHedgeVariant.trim().isNotEmpty) 'cardHedgeVariant': cardHedgeVariant.trim(),
        if (parallelName != null && parallelName.trim().isNotEmpty) 'parallelName': parallelName.trim(),
      },
    );
    if (res.status != 200) return null;
    final raw = res.data;
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    if (map['error'] != null) return null;
    final mid = map['masterCardDefinitionsId']?.toString().trim();
    if (mid == null || mid.isEmpty) return null;
    return CatalogEnsureFromScanResult.fromJson(map);
  }

  Future<List<ReleaseRecord>> _releasesForChVault(
    String releaseDisplayName,
    int? year, {
    String scanSport = '',
  }) async {
    final name = releaseDisplayName.trim();
    if (name.isEmpty) return const [];
    final basketballDual = year != null && _scanSportIsBasketball(scanSport);

    List<ReleaseRecord> mapRows(dynamic data) {
      if (data is! List) return const [];
      return data.map((r) => ReleaseRecord.fromJson(r as Map<String, dynamic>)).toList();
    }

    dynamic namedReleaseQuery() => _supabase
        .from('releases')
        .select('id, name, year, sport, cardsight_id, sets(id, set_cards(count))')
        .ilike('name', '%$name%');

    try {
      if (year == null) {
        final data = await namedReleaseQuery().order('year', ascending: false).limit(25);
        return mapRows(data);
      }

      if (basketballDual) {
        final y = year;
        final seasonSpan = '$y-${y + 1}';
        final byCalYear =
            await namedReleaseQuery().eq('year', y).order('year', ascending: false).limit(25);
        final bySeasonInName = await namedReleaseQuery()
            .ilike('name', '%$seasonSpan%')
            .order('year', ascending: false)
            .limit(25);
        return _mergeChReleaseRecords(mapRows(byCalYear), mapRows(bySeasonInName));
      }

      final data =
          await namedReleaseQuery().eq('year', year).order('year', ascending: false).limit(25);
      return mapRows(data);
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> _setCardsForPlayerInSet(String setId, String player) async {
    var safe = player.replaceAll('%', '').trim();
    if (safe.isEmpty) return const [];
    if (safe.length > 80) safe = safe.substring(0, 80);
    try {
      final data = await _supabase
          .from('set_cards')
          .select('id, player, card_number')
          .eq('set_id', setId)
          .ilike('player', '%$safe%')
          .limit(80);
      return (data as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<CatalogSearchCardResult?> _pickCatalogSearchCardForChHit(
    CardHedgeImageSearchHit hit,
    String cardsightReleaseId,
  ) async {
    final player = (hit.player ?? '').trim();
    if (player.isEmpty) return null;
    final results = await searchCardsInRelease(cardsightReleaseId, player, take: 40);
    if (results.isEmpty) return null;
    final preferSet = hit.cardsightSetId?.trim();
    final num = hit.number?.trim();
    final numPresent = num != null && num.isNotEmpty;

    if (numPresent) {
      final withNum = results.where((c) => _chNumbersRoughMatch(c.number, num)).toList();
      if (withNum.isNotEmpty) {
        final ps = preferSet;
        if (ps != null && ps.isNotEmpty) {
          final bySet = withNum.where((c) => c.setId == ps).toList();
          if (bySet.isNotEmpty) return bySet.first;
        }
        return withNum.first;
      }
    }

    CatalogSearchCardResult? best;
    var bestScore = -1;
    final firstTok = player
        .split(RegExp(r'\s+'))
        .firstWhere((e) => e.length > 2, orElse: () => player)
        .toLowerCase();
    for (final c in results) {
      var score = 0;
      if (preferSet != null && preferSet.isNotEmpty && c.setId == preferSet) score += 30;
      if (_chPlayersRoughMatch(c.name, player)) {
        score += 10;
      } else if (c.name.toLowerCase().contains(firstTok)) {
        score += 5;
      }
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return best;
  }

  /// Vault DB walk + optional `catalog-import-cards` when CardSight ids are known.
  /// For on-device debugging when resolution feels hung.
  Future<Map<String, dynamic>> debugVaultLookupForCardHedgeHit(
    CardHedgeImageSearchHit hit, {
    required String scanSport,
  }) async {
    final sw = Stopwatch()..start();
    final releaseName = (hit.displayReleaseName ?? '').trim();
    final setHint = hit.displaySetName.trim();
    final year = hit.parsedListingYear;
    final player = (hit.player ?? '').trim();
    final parallelHint = _chEffectiveParallelHint(hit);
    final sportEff = _effectiveChScanSport(scanSport, hit);
    final basketballDual = year != null && _scanSportIsBasketball(sportEff);
    final seasonSpan = switch ((basketballDual, year)) {
      (true, final int y) => '$y-${y + 1}',
      _ => null,
    };

    final out = <String, dynamic>{
      'inputs': {
        'scanSport': scanSport,
        'effectiveScanSport': sportEff,
        'displayReleaseName': releaseName,
        'displaySetName': setHint,
        'parsedListingYear': year,
        'player': player,
        'cardNumber': hit.number,
        'parallelHint': parallelHint,
        'cardsightReleaseId': hit.cardsightReleaseId,
        'cardsightSetId': hit.cardsightSetId,
        'cardsightCardId': hit.cardsightCardId,
        'cardHedgeCardId': hit.cardId,
      },
      'releasesLookupPlan': {
        'basketballDualYearQuery': basketballDual,
        if (seasonSpan != null) 'seasonSpanInReleaseName': seasonSpan,
        'description': basketballDual
            ? 'Basketball: merge releases where year==$year OR name ilike %$seasonSpan% (with same release-name filter).'
            : (year != null
                ? 'Non-basketball or wrong sport for dual-year: filter year==$year only.'
                : 'No calendar year filter on releases.'),
      },
      'note': 'Vault DB + catalog-import-cards when spine ids resolve. No catalog-search-cards / ensure.',
    };

    if (releaseName.isEmpty || player.isEmpty) {
      out['vaultSkippedReason'] = 'need_non_empty_displayReleaseName_and_player';
      out['elapsedMs'] = sw.elapsedMilliseconds;
      return out;
    }

    try {
      final rels = await _releasesForChVault(releaseName, year, scanSport: sportEff);
      out['releasesQuery'] = {
        'count': rels.length,
        'filterYear': year,
        'scanSport': scanSport,
        'effectiveScanSport': sportEff,
        'basketballDualYearQuery': basketballDual,
        'releases': [
          for (final r in rels)
            {
              'id': r.id,
              'name': r.name,
              'year': r.year,
              'sport': r.sport,
              'cardsight_id': r.catalogImportReleaseKey,
            },
        ],
      };

      final attempts = <Map<String, dynamic>>[];
      for (final rel in rels.take(10)) {
        final attempt = <String, dynamic>{
          'releaseId': rel.id,
          'releaseName': rel.name,
          'releaseYear': rel.year,
          'releaseCardsightId': rel.catalogImportReleaseKey,
        };
        try {
          final sets = await getSetsForRelease(rel.id);
          attempt['setsCount'] = sets.length;
          attempt['setNames'] = sets.map((s) => s.name).toList();
          final set = _chPickSet(sets, setHint);
          if (set == null) {
            attempt['set'] = null;
            attempt['setPickReason'] =
                sets.isEmpty ? 'no_sets_for_release' : 'no_set_name_match_for_hint';
            attempts.add(attempt);
            continue;
          }
          attempt['set'] = {
            'id': set.id,
            'name': set.name,
            'card_count': set.cardCount,
            'cardsight_id': set.catalogImportSetKey,
          };

          final parallels = await getParallels(set.id);
          attempt['parallels'] = [
            for (final p in parallels)
              {'id': p.id, 'name': p.name, 'serial_max': p.serialMax, 'is_auto': p.isAuto},
          ];
          final parallel = _chPickParallel(parallels, parallelHint);
          attempt['parallelPicked'] = parallel == null
              ? null
              : {
                  'id': parallel.id,
                  'name': parallel.name,
                  'serial_max': parallel.serialMax,
                  'is_auto': parallel.isAuto,
                };
          if (parallel == null) {
            attempt['parallelPickReason'] = 'no_parallels_on_set';
            attempts.add(attempt);
            continue;
          }

          final scRows = await _setCardsForPlayerInSet(set.id, player);
          attempt['setCardsQueriedCount'] = scRows.length;
          attempt['setCardsSample'] = scRows.take(25).map(Map<String, dynamic>.from).toList();
          final setCardId = _chPickSetCardId(scRows, player, hit.number);
          attempt['pickedSetCardId'] = setCardId;
          if (setCardId == null) {
            attempt['setCardPickReason'] = scRows.isEmpty
                ? 'no_set_cards_rows'
                : 'no_row_passed_player_number_score_gate';
            attempts.add(attempt);
            continue;
          }

          final baseVar = await _supabase
              .from('set_card_base_variants')
              .select('id')
              .eq('set_card_id', setCardId)
              .maybeSingle();
          attempt['set_card_base_variants'] =
              baseVar == null ? null : Map<String, dynamic>.from(baseVar);
          if (baseVar == null) {
            attempt['baseVariantReason'] = 'no_base_variant_row_for_set_card_id';
            attempts.add(attempt);
            continue;
          }
          final baseMasterId = baseVar['id'] as String;
          attempt['baseParallelMasterRowId'] = baseMasterId;
          attempt['wouldCallEnsureCatalogVariant'] = {
            'catalogVariantId': baseMasterId,
            'parallelId': parallel.id,
          };
        } catch (e, st) {
          attempt['error'] = e.toString();
          attempt['stack'] = st.toString();
        }
        attempts.add(attempt);
      }
      out['vaultAttempts'] = attempts;

      Map<String, dynamic> importSection;
      final attemptsList = out['vaultAttempts'] as List<dynamic>? ?? [];
      String? pickVaultSetId;
      String? pickCsRel;
      String? pickCsSet;
      for (final raw in attemptsList) {
        if (raw is! Map) continue;
        final a = Map<String, dynamic>.from(raw);
        final setRaw = a['set'];
        if (setRaw is! Map) continue;
        final sm = Map<String, dynamic>.from(setRaw);
        final sid = sm['id']?.toString().trim();
        if (sid == null || sid.isEmpty) continue;
        final rCs = (a['releaseCardsightId'] ?? '').toString().trim();
        final sCs = (sm['cardsight_id'] ?? '').toString().trim();
        final useRel = rCs.isNotEmpty ? rCs : (hit.cardsightReleaseId ?? '').trim();
        final useSet = sCs.isNotEmpty ? sCs : (hit.cardsightSetId ?? '').trim();
        if (useRel.isEmpty || useSet.isEmpty) continue;
        pickVaultSetId = sid;
        pickCsRel = useRel;
        pickCsSet = useSet;
        break;
      }

      if (pickVaultSetId == null) {
        importSection = {
          'skipped': true,
          'reason':
              'No vault attempt with a picked set plus CardSight release+set ids (from DB columns or hit); did not invoke catalog-import-cards.',
        };
      } else {
        final cr = pickCsRel;
        final cs = pickCsSet;
        if (cr == null || cs == null || cr.isEmpty || cs.isEmpty) {
          importSection = {
            'skipped': true,
            'reason': 'Picked vault set row but spine ids were empty after merge with hit.',
            'lookup': {'vaultSetId': pickVaultSetId},
          };
        } else {
          try {
            final report = await importCardsForSetDetailed(
              cardsightReleaseId: cr,
              cardsightSetId: cs,
              vaultSetId: pickVaultSetId,
            );
            importSection = {
              'skipped': false,
              'pickedFrom': 'first_vault_attempt_with_set_row_and_resolved_cardsight_ids',
              'lookup': {
                'vaultSetId': pickVaultSetId,
                'cardsightReleaseId': cr,
                'cardsightSetId': cs,
              },
              'catalogImportCards': report,
            };
          } catch (e, st) {
            importSection = {
              'skipped': false,
              'lookup': {
                'vaultSetId': pickVaultSetId,
                'cardsightReleaseId': cr,
                'cardsightSetId': cs,
              },
              'invokeError': e.toString(),
              'invokeStack': st.toString(),
            };
          }
        }
      }
      out['importCardsForSet'] = importSection;
    } catch (e, st) {
      out['fatalError'] = e.toString();
      out['fatalStack'] = st.toString();
    }

    out['elapsedMs'] = sw.elapsedMilliseconds;
    return out;
  }

  /// Looks up [SetParallel] for a `master_card_definitions` row. [pals] must be from [getParallels]
  /// for the vault set that owns [masterCardId].
  Future<SetParallel?> _setParallelForMaster(String masterCardId, List<SetParallel> pals) async {
    final row = await _supabase
        .from('master_card_definitions')
        .select('parallel_id')
        .eq('id', masterCardId.trim())
        .maybeSingle();
    final pid = (row?['parallel_id'] as String?)?.trim();
    if (pid == null || pid.isEmpty) return null;
    for (final p in pals) {
      if (p.id == pid) return p;
    }
    return null;
  }

  /// Walks vault `releases` → `sets` → `set_cards` → `set_parallels` → `master_card_definitions`,
  /// then falls back to [ensureCatalogFromScanSelection] when CardSight spine ids can resolve the card.
  Future<ChScanCatalogResolveResult?> resolveCardHedgeHitForMasterDetail(
    CardHedgeImageSearchHit hit, {
    String scanSport = '',
  }) async {
    final releaseName = (hit.displayReleaseName ?? '').trim();
    final setHint = hit.displaySetName.trim();
    final year = hit.parsedListingYear;
    final player = (hit.player ?? '').trim();
    final parallelHint = _chEffectiveParallelHint(hit);
    final sportEff = _effectiveChScanSport(scanSport, hit);

    Future<ChScanCatalogResolveResult?> finishFromEnsure(CatalogEnsureFromScanResult ens) async {
      final rs = await getReleaseAndSetForSetId(ens.setId);
      final pals = await getParallels(ens.setId);
      final mid = ens.masterCardDefinitionsId.trim();

      // [catalog-ensure-from-scan-selection] returns the final `master_card_definitions` id.
      // Prefer that row's `parallel_id` so we never disagree with the server then let Scan's
      // [ensureCatalogVariant] remap to a different variant.
      SetParallel? par = await _setParallelForMaster(mid, pals);
      if (par == null) {
        final pid = ens.parallelId?.trim();
        if (pid != null && pid.isNotEmpty) {
          for (final p in pals) {
            if (p.id == pid) {
              par = p;
              break;
            }
          }
        }
      }
      par ??= _chPickParallel(pals, parallelHint);
      final pname = par?.name ?? parallelHint;
      return ChScanCatalogResolveResult(
        resolvedMasterCardId: mid,
        parallelName: pname,
        parallel: par,
        release: rs.release,
        set: rs.set,
      );
    }

    Future<ChScanCatalogResolveResult?> tryLazyImportPath() async {
      var cr = hit.cardsightReleaseId?.trim();
      var cs = hit.cardsightSetId?.trim();
      var cc = hit.cardsightCardId?.trim();
      if (player.isEmpty) return null;

      if ((cr == null || cr.isEmpty) && cs != null && cs.isNotEmpty) {
        final fromVault = await _cardsightReleaseIdFromCardsightSetId(cs);
        if (fromVault != null && fromVault.isNotEmpty) cr = fromVault;
      }

      if (cc != null && cc.isNotEmpty) {
        if (cr == null || cr.isEmpty) return null;
        if (cs == null || cs.isEmpty) {
          final results = await searchCardsInRelease(cr, player, take: 60);
          CatalogSearchCardResult? row;
          for (final c in results) {
            if (c.id == cc) {
              row = c;
              break;
            }
          }
          if (row == null) return null;
          cs = row.setId;
          cr = row.releaseId;
        }
      } else {
        if (cr == null || cr.isEmpty) return null;
        final picked = await _pickCatalogSearchCardForChHit(hit, cr);
        if (picked == null) return null;
        cc = picked.id.trim();
        cs = (cs != null && cs.isNotEmpty) ? cs : picked.setId.trim();
        cr = picked.releaseId.trim();
      }

      if (cr.isEmpty || cs.isEmpty || cc.isEmpty) return null;

      final yn = year ?? DateTime.now().year;
      final rn = releaseName.isNotEmpty ? releaseName : 'Unknown Release';

      final ens = await ensureCatalogFromScanSelection(
        cardsightReleaseId: cr,
        cardsightSetId: cs,
        cardsightCardId: cc,
        releaseName: rn,
        releaseYear: yn,
        cardHedgeCardId: hit.cardId,
        cardHedgeVariant: (hit.variant?.trim().isNotEmpty == true) ? hit.variant!.trim() : parallelHint,
        parallelName: parallelHint,
      );
      if (ens == null) return null;
      return finishFromEnsure(ens);
    }

    if (releaseName.isNotEmpty && player.isNotEmpty) {
      final rels = await _releasesForChVault(releaseName, year, scanSport: sportEff);
      for (final rel in rels) {
        final sets = await getSetsForRelease(rel.id);
        final set = _chPickSet(sets, setHint);
        if (set == null) continue;
        final parallels = await getParallels(set.id);
        final parallel = _chPickParallel(parallels, parallelHint);
        if (parallel == null) continue;
        final scRows = await _setCardsForPlayerInSet(set.id, player);
        final setCardId = _chPickSetCardId(scRows, player, hit.number);
        if (setCardId == null) continue;
        final baseVar = await _supabase
            .from('set_card_base_variants')
            .select('id')
            .eq('set_card_id', setCardId)
            .maybeSingle();
        if (baseVar == null) continue;
        final baseMasterId = baseVar['id'] as String;
        try {
          final masterId = await ensureCatalogVariant(
            catalogVariantId: baseMasterId,
            parallelId: parallel.id,
          );
          final parOut = await _setParallelForMaster(masterId, parallels) ?? parallel;
          return ChScanCatalogResolveResult(
            resolvedMasterCardId: masterId,
            parallelName: parOut.name,
            parallel: parOut,
            release: rel,
            set: set,
          );
        } catch (_) {
          continue;
        }
      }
    }

    return tryLazyImportPath();
  }

  Future<List<MasterCard>> searchMasterCards(String setId, String query, {int offset = 0, int limit = 50}) async {
    var q = _supabase
        .from('set_card_base_variants')
        .select('id, player, card_number, is_rookie, is_auto, is_patch, is_ssp, serial_max, image_url')
        .eq('set_id', setId);
    if (query.trim().isNotEmpty) {
      q = q.ilike('player', '%${query.trim()}%');
    }
    final data = await q.order('player', ascending: true).range(offset, offset + limit - 1);
    return (data as List).map((r) => MasterCard.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// Full set checklist: one row per [set_card], with the [master_card_definitions] id
  /// for [parallelName] when that variant exists.
  Future<List<SetChecklistSlot>> fetchSetChecklistSlots({
    required String setId,
    String parallelName = 'Base',
  }) async {
    final baseData = await _supabase
        .from('set_card_base_variants')
        .select(
          'id, set_card_id, player, card_number, is_rookie, is_auto, is_patch, is_ssp, serial_max, image_url',
        )
        .eq('set_id', setId)
        .order('card_number', ascending: true, nullsFirst: false)
        .order('player', ascending: true);

    final baseRows = (baseData as List).cast<Map<String, dynamic>>();
    if (baseRows.isEmpty) return const [];

    final parallels = await getParallels(setId);
    final parallel = _chPickParallel(parallels, parallelName);
    final variantBySetCard = <String, String>{};

    if (parallel != null) {
      final setCardIds = baseRows.map((r) => r['set_card_id'] as String).toList();
      const chunk = 200;
      for (var i = 0; i < setCardIds.length; i += chunk) {
        final slice = setCardIds.sublist(i, i + chunk > setCardIds.length ? setCardIds.length : i + chunk);
        final variants = await _supabase
            .from('master_card_definitions')
            .select('id, set_card_id')
            .eq('parallel_id', parallel.id)
            .inFilter('set_card_id', slice);
        for (final v in variants as List) {
          final m = Map<String, dynamic>.from(v as Map);
          variantBySetCard[m['set_card_id'] as String] = m['id'] as String;
        }
      }
    }

    final isBaseContext = parallelName.trim().isEmpty ||
        parallelName.trim().toLowerCase() == 'base';

    return baseRows.map((r) {
      final setCardId = r['set_card_id'] as String;
      final baseMasterId = r['id'] as String;
      final variantId = variantBySetCard[setCardId];
      final ownedMasterId = isBaseContext ? baseMasterId : variantId;
      return SetChecklistSlot(
        setCardId: setCardId,
        masterCardId: ownedMasterId,
        card: MasterCard.fromJson(r),
      );
    }).toList();
  }

  /// Loads any catalog variant by `master_card_definitions.id` (not limited to Base —
  /// unlike [set_card_base_variants], which exposes one row per `set_card` at base parallel).
  Future<MasterCard?> fetchMasterCardById(String id) async {
    final data = await _supabase
        .from('master_card_definitions')
        .select(
          'id, is_auto, is_patch, is_ssp, serial_max, image_url, cardhedge_id, gain, '
          'set_cards(player, card_number, is_rookie, image_url)',
        )
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    final map = Map<String, dynamic>.from(data);
    final scRaw = map['set_cards'];
    Map<String, dynamic>? sc;
    if (scRaw is Map) sc = Map<String, dynamic>.from(scRaw);
    final masterImg = (map['image_url'] as String?)?.trim();
    final checklistImg = (sc?['image_url'] as String?)?.trim();
    final coalesced = (masterImg != null && masterImg.isNotEmpty) ? masterImg : checklistImg;
    final linkedGuidePriceId = (map['cardhedge_id'] as String?)?.trim();
    return MasterCard(
      id: map['id'] as String,
      player: sc?['player'] as String? ?? '',
      cardNumber: sc?['card_number'] as String?,
      isRookie: sc?['is_rookie'] as bool? ?? false,
      isAuto: map['is_auto'] as bool? ?? false,
      isPatch: map['is_patch'] as bool? ?? false,
      isSSP: map['is_ssp'] as bool? ?? false,
      serialMax: _tryParseInt(map['serial_max']),
      imageUrl: (coalesced != null && coalesced.isNotEmpty) ? coalesced : null,
      guidePriceCardId: (linkedGuidePriceId != null && linkedGuidePriceId.isNotEmpty) ? linkedGuidePriceId : null,
      gain: _tryParseDouble(map['gain']),
    );
  }

  /// Resolves [catalogVariantId] (any `master_card_definitions` row for that `set_card`) to the row for [parallelId],
  /// inserting a new `master_card_definitions` row when needed.
  Future<String> ensureCatalogVariant({
    required String catalogVariantId,
    required String? parallelId,
  }) async {
    final cur = await _supabase
        .from('master_card_definitions')
        .select('set_card_id, parallel_id')
        .eq('id', catalogVariantId)
        .single();
    final setCardId = cur['set_card_id'] as String;
    final currentParallel = cur['parallel_id'] as String;
    final targetParallel = parallelId ?? currentParallel;
    if (targetParallel == currentParallel) return catalogVariantId;

    final existing = await _supabase
        .from('master_card_definitions')
        .select('id')
        .eq('set_card_id', setCardId)
        .eq('parallel_id', targetParallel)
        .maybeSingle();
    if (existing != null) return existing['id'] as String;

    final flags = await _supabase
        .from('master_card_definitions')
        .select(
          'is_auto, is_patch, is_ssp, serial_max, cardhedge_id, gain, sales_7d, sales_30d',
        )
        .eq('id', catalogVariantId)
        .single();

    final inserted = await _supabase.from('master_card_definitions').insert({
      'set_card_id': setCardId,
      'parallel_id': targetParallel,
      'is_auto': flags['is_auto'] as bool? ?? false,
      'is_patch': flags['is_patch'] as bool? ?? false,
      'is_ssp': flags['is_ssp'] as bool? ?? false,
      'serial_max': flags['serial_max'],
      if (flags['cardhedge_id'] != null) 'cardhedge_id': flags['cardhedge_id'],
      if (flags['gain'] != null) 'gain': flags['gain'],
      if (flags['sales_7d'] != null) 'sales_7d': flags['sales_7d'],
      if (flags['sales_30d'] != null) 'sales_30d': flags['sales_30d'],
    }).select('id').single();
    final newId = inserted['id'] as String;
    await _copyCurrentPricesBetweenVariants(catalogVariantId, newId);
    return newId;
  }

  /// Copies `current_prices` rows when [ensureCatalogVariant] creates a sibling variant row.
  Future<void> _copyCurrentPricesBetweenVariants(String fromId, String toId) async {
    if (fromId == toId) return;
    final rows = await _supabase
        .from('current_prices')
        .select('grade, price, fetched_at')
        .eq('master_card_id', fromId);
    final list = rows as List;
    if (list.isEmpty) return;
    final inserts = list.map((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      return {
        'master_card_id': toId,
        'grade': m['grade'],
        'price': m['price'],
        'fetched_at': m['fetched_at'] ?? DateTime.now().toUtc().toIso8601String(),
      };
    }).toList();
    await _supabase.from('current_prices').insert(inserts);
  }

  Future<({ReleaseRecord release, SetRecord set})> getReleaseAndSetForSetId(String setId) async {
    final setData = await _supabase
        .from('sets')
        .select('id, name, card_count, cardsight_id, set_cards(count), release_id')
        .eq('id', setId)
        .single();
    final releaseId = setData['release_id'] as String;
    final setRecord = SetRecord.fromJson(Map<String, dynamic>.from(setData));
    final releaseData = await _supabase
        .from('releases')
        .select('id, name, year, sport, cardsight_id, sets(id, set_cards(count))')
        .eq('id', releaseId)
        .single();
    final release = ReleaseRecord.fromJson(Map<String, dynamic>.from(releaseData));
    return (release: release, set: setRecord);
  }

  Future<List<CatalogRelease>> searchCatalogReleases(String query, {int? year, String? segment}) async {
    final body = <String, dynamic>{};
    if (query.isNotEmpty) body['query'] = query;
    if (year != null) body['year'] = year;
    if (segment != null && segment.isNotEmpty) body['segment'] = segment;
    final res = await _supabase.functions.invoke('catalog-search', body: body);
    if (res.status != 200) throw Exception('Catalog search failed: ${res.status}');
    final list = res.data as List? ?? [];
    return list.map((r) => CatalogRelease.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<List<CatalogSetSummary>> getCatalogSets(String cardsightReleaseId) async {
    final res = await _supabase.functions.invoke(
      'catalog-search',
      body: {'releaseId': cardsightReleaseId},
    );
    if (res.status != 200) throw Exception('Failed to fetch sets: ${res.status}');
    final list = res.data as List? ?? [];
    return list.map((r) => CatalogSetSummary.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// Search cards within a release cross-set via catalog API (with retry on rate limit)
  Future<List<CatalogSearchCardResult>> searchCardsInRelease(
    String cardsightReleaseId,
    String name, {
    int take = 20,
  }) async {
    const maxRetries = 3;
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      final res = await _supabase.functions.invoke(
        'catalog-search-cards',
        body: {'cardsightReleaseId': cardsightReleaseId, 'name': name, 'take': take},
      );

      if (res.status == 200) {
        final data = res.data as Map<String, dynamic>? ?? {};
        final cards = data['cards'] as List? ?? [];
        return cards.map((c) => CatalogSearchCardResult.fromJson(c as Map<String, dynamic>)).toList();
      }

      if (res.status == 429 && attempt < maxRetries - 1) {
        final delayMs = 250 * (1 << attempt);
        await Future.delayed(Duration(milliseconds: delayMs));
        continue;
      }

      return [];
    }
    return [];
  }

  /// Whether [releaseId] + [setId] from a scan already identify a row in this vault.
  ///
  /// [ScanCatalogAnchorKind.vaultPrimaryKeys]: use [resolveVaultAnchoredScanCard] from scan navigation
  /// so vault UUIDs are not sent to [lazyImportCatalog].
  ///
  /// [ScanCatalogAnchorKind.cardsightIds] or [ScanCatalogAnchorKind.none]: use [resolveCardFromCatalog],
  /// which may [lazyImportCatalog] to create missing releases/sets from CardSight.
  Future<ScanCatalogAnchorKind> classifyScanCatalogAnchor({
    required String releaseId,
    required String setId,
  }) async {
    final r = releaseId.trim();
    final s = setId.trim();
    if (r.isEmpty || s.isEmpty) return ScanCatalogAnchorKind.none;

    final direct = await _supabase
        .from('sets')
        .select('id')
        .eq('id', s)
        .eq('release_id', r)
        .maybeSingle();
    if (direct != null) return ScanCatalogAnchorKind.vaultPrimaryKeys;

    final rel = await _supabase
        .from('releases')
        .select('id')
        .eq('cardsight_id', r)
        .maybeSingle();
    if (rel == null) return ScanCatalogAnchorKind.none;
    final rid = rel['id'] as String;
    final byCs = await _supabase
        .from('sets')
        .select('id')
        .eq('release_id', rid)
        .eq('cardsight_id', s)
        .maybeSingle();
    if (byCs != null) return ScanCatalogAnchorKind.cardsightIds;

    return ScanCatalogAnchorKind.none;
  }

  /// Resolve a scanned card when [classifyScanCatalogAnchor] returned [ScanCatalogAnchorKind.vaultPrimaryKeys].
  /// Skips [lazyImportCatalog] (which keys off CardSight ids and can attach the wrong release/set).
  ///
  /// When there is no matching [set_cards] row yet, [importCardsForSet] uses CardSight ids from
  /// [releases.cardsight_id] / [sets.cardsight_id], or [cardsightReleaseIdForImport] /
  /// [cardsightSetIdForImport] when those columns are not set.
  Future<({String masterCardId, String setId, List<SetParallel> parallels})>
      resolveVaultAnchoredScanCard({
    required String vaultReleaseId,
    required String vaultSetId,
    required String scanCatalogCardId,
    String? cardsightReleaseIdForImport,
    String? cardsightSetIdForImport,
  }) async {
    final parallels = await getParallels(vaultSetId);
    final scanId = scanCatalogCardId.trim();
    if (scanId.isEmpty) {
      throw Exception('Missing card id from scan');
    }

    Future<String?> baseVariantIdForSetCard(String setCardId) async {
      final v = await _supabase
          .from('set_card_base_variants')
          .select('id')
          .eq('set_card_id', setCardId)
          .maybeSingle();
      return v?['id'] as String?;
    }

    final byMasterInSet = await _supabase
        .from('set_card_base_variants')
        .select('id')
        .eq('id', scanId)
        .eq('set_id', vaultSetId)
        .maybeSingle();
    if (byMasterInSet != null) {
      return (masterCardId: byMasterInSet['id'] as String, setId: vaultSetId, parallels: parallels);
    }

    Future<({String masterCardId, String setId, List<SetParallel> parallels})?> tryByCardsight() async {
      final sc = await _supabase
          .from('set_cards')
          .select('id')
          .eq('set_id', vaultSetId)
          .eq('cardsight_card_id', scanId)
          .maybeSingle();
      if (sc == null) return null;
      final bid = await baseVariantIdForSetCard(sc['id'] as String);
      if (bid == null) return null;
      return (masterCardId: bid, setId: vaultSetId, parallels: parallels);
    }

    final first = await tryByCardsight();
    if (first != null) return first;

    final setRow = await _supabase
        .from('sets')
        .select('cardsight_id')
        .eq('id', vaultSetId)
        .maybeSingle();
    final releaseRow = await _supabase
        .from('releases')
        .select('cardsight_id')
        .eq('id', vaultReleaseId)
        .maybeSingle();
    final csRel = (releaseRow?['cardsight_id'] as String?)?.trim().isNotEmpty == true
        ? (releaseRow!['cardsight_id'] as String).trim()
        : (cardsightReleaseIdForImport?.trim().isNotEmpty == true
            ? cardsightReleaseIdForImport!.trim()
            : null);
    final csSet = (setRow?['cardsight_id'] as String?)?.trim().isNotEmpty == true
        ? (setRow!['cardsight_id'] as String).trim()
        : (cardsightSetIdForImport?.trim().isNotEmpty == true
            ? cardsightSetIdForImport!.trim()
            : null);
    if (csSet == null || csSet.isEmpty || csRel == null || csRel.isEmpty) {
      throw Exception(
        'No set_card yet for this scan, and no CardSight release/set ids available to import set_cards.',
      );
    }

    await importCardsForSet(
      cardsightReleaseId: csRel,
      cardsightSetId: csSet,
      setId: vaultSetId,
    );

    final second = await tryByCardsight();
    if (second != null) return second;

    throw Exception('set_card not found for this scan after CardSight import.');
  }

  /// Ensures the CardSight spine exists: [releases], [sets], [set_parallels] via [lazyImportCatalog],
  /// then the scanned [set_cards] row and [master_card_definitions] (via [importCardsForSet] when the
  /// `set_cards` row is missing). Each `master_card_definitions` row ties a `set_card` to a parallel.
  ///
  /// Returns the base-parallel [master_card_definitions.id] exposed by [set_card_base_variants] for UI navigation.
  Future<({String masterCardId, String setId, List<SetParallel> parallels})>
      ensureCardSightSpineAndScanCardResolved({
    required String cardsightReleaseId,
    required String cardsightSetId,
    required String cardsightCardId,
    required String releaseName,
    required int releaseYear,
    String? releaseSegmentId,
  }) async {
    final cr = cardsightReleaseId.trim();
    final cs = cardsightSetId.trim();
    final cc = cardsightCardId.trim();
    if (cr.isEmpty || cs.isEmpty || cc.isEmpty) {
      throw Exception('Missing CardSight release, set, or card id');
    }

    final importResult = await lazyImportCatalog(
      cardsightReleaseId: cr,
      releaseName: releaseName,
      releaseYear: releaseYear.toString(),
      releaseSegmentId: releaseSegmentId ?? '',
      cardsightSetId: cs,
    );
    final setId = importResult.setId;
    final parallels = importResult.parallels;

    final existingSc = await _supabase
        .from('set_cards')
        .select('id')
        .eq('set_id', setId)
        .eq('cardsight_card_id', cc)
        .maybeSingle();

    if (existingSc != null) {
      final v = await _supabase
          .from('set_card_base_variants')
          .select('id')
          .eq('set_card_id', existingSc['id'] as String)
          .maybeSingle();
      if (v != null) {
        return (masterCardId: v['id'] as String, setId: setId, parallels: parallels);
      }
    }

    await importCardsForSet(
      cardsightReleaseId: cr,
      cardsightSetId: cs,
      setId: setId,
    );

    final foundSc = await _supabase
        .from('set_cards')
        .select('id')
        .eq('set_id', setId)
        .eq('cardsight_card_id', cc)
        .maybeSingle();

    if (foundSc == null) {
      throw Exception('set_card not found for this CardSight card after import.');
    }

    final v = await _supabase
        .from('set_card_base_variants')
        .select('id')
        .eq('set_card_id', foundSc['id'] as String)
        .single();

    return (masterCardId: v['id'] as String, setId: setId, parallels: parallels);
  }

  /// Resolve a catalog card: lazy-import set + parallels, then find or import the card
  Future<({String masterCardId, String setId, List<SetParallel> parallels})>
      resolveCardFromCatalog({
    required CatalogSearchCardResult card,
    required String releaseName,
    required int releaseYear,
    String? releaseSegmentId,
  }) async {
    return ensureCardSightSpineAndScanCardResolved(
      cardsightReleaseId: card.releaseId,
      cardsightSetId: card.setId,
      cardsightCardId: card.id,
      releaseName: releaseName,
      releaseYear: releaseYear,
      releaseSegmentId: releaseSegmentId,
    );
  }

  Future<LazyImportResult> lazyImportCatalog({
    required String cardsightReleaseId,
    required String releaseName,
    required String releaseYear,
    required String releaseSegmentId,
    required String cardsightSetId,
  }) async {
    final res = await _supabase.functions.invoke(
      'catalog-lazy-import',
      body: {
        'cardsightReleaseId': cardsightReleaseId,
        'releaseName':        releaseName,
        'releaseYear':        releaseYear,
        'releaseSegmentId':   releaseSegmentId,
        'cardsightSetId':     cardsightSetId,
      },
    );
    if (res.status != 200) throw Exception('Catalog import failed: ${res.status}');
    return LazyImportResult.fromJson(res.data as Map<String, dynamic>);
  }

  // ── Admin methods ─────────────────────────────────────────────

  /// Lists CardSight releases for [segment] (cached in `cardsight_release_index` when fresh).
  /// Pass [refresh] true to force a CardSight re-sync.
  Future<({
    List<AdminCatalogReleaseRow> releases,
    int missing,
    bool vaultOnly,
    bool fromCache,
    String? notice,
  })> listAdminCatalogReleases({
    required String segment,
    bool refresh = false,
  }) async {
    final res = await _supabase.functions.invoke('catalog-releases-list', body: {
      'segment': segment,
      if (refresh) 'refresh': true,
    });
    if (res.status != 200) {
      throw Exception(_functionErrorMessage(res, 'Catalog list failed'));
    }
    final data = res.data as Map<String, dynamic>;
    final list = (data['releases'] as List?) ?? [];
    final missing = _tryParseInt(data['missing']) ?? 0;
    return (
      releases: list
          .map((r) => AdminCatalogReleaseRow.fromJson(r as Map<String, dynamic>))
          .toList(),
      missing: missing,
      vaultOnly: data['vaultOnly'] == true,
      fromCache: data['fromCache'] == true,
      notice: data['notice'] as String?,
    );
  }

  static const _segmentToSport = {
    'baseball': 'Baseball',
    'basketball': 'Basketball',
    'football': 'Football',
    'soccer': 'Soccer',
    'hockey': 'Hockey',
  };

  static String _sportForSegment(String segment) =>
      _segmentToSport[segment.toLowerCase()] ?? segment;

  static String _releaseSlug({
    required int year,
    required String name,
    required String sport,
    required String cardsightId,
  }) {
    final parts = [year.toString(), name, sport]
        .map((v) => v.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '-'))
        .map((v) => v.replaceAll(RegExp(r'[^a-z0-9-]'), ''))
        .where((s) => s.isNotEmpty);
    final tail = cardsightId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
    final suffix = tail.length > 8 ? tail.substring(0, 8) : tail;
    return '${parts.join('-')}-$suffix';
  }

  /// Imports release shells. [selected] upserts directly (fast, no CardSight round-trip).
  /// Omit [selected] to fetch every release for [segment] via the bulk-import edge function.
  Future<Map<String, dynamic>> bulkImportReleases({
    required String segment,
    int? year,
    List<AdminCatalogReleaseRow>? selected,
  }) async {
    if (selected != null && selected.isNotEmpty) {
      return _importSelectedReleaseShells(segment, selected);
    }

    final body = <String, dynamic>{'segment': segment};
    if (year != null) body['year'] = year;
    final res = await _supabase.functions.invoke('catalog-bulk-import', body: body);
    if (res.status != 200) {
      throw Exception(_functionErrorMessage(res, 'Bulk import failed'));
    }
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> _importSelectedReleaseShells(
    String segment,
    List<AdminCatalogReleaseRow> selected,
  ) async {
    final sport = _sportForSegment(segment);
    final ids = selected.map((r) => r.cardsightId).toList();

    final existingRows = await _supabase
        .from('releases')
        .select('cardsight_id')
        .inFilter('cardsight_id', ids);
    final existingIds = {
      for (final row in existingRows as List)
        (row as Map<String, dynamic>)['cardsight_id'] as String,
    };

    final rows = selected.map((r) {
      final y = r.resolvedYear();
      return {
        'name': r.name,
        'year': y,
        'sport': sport,
        'release_type': 'Hobby',
        'set_slug': _releaseSlug(
          year: y,
          name: r.name,
          sport: sport,
          cardsightId: r.cardsightId,
        ),
        'cardsight_id': r.cardsightId,
      };
    }).toList();

    final upserted = await _supabase
        .from('releases')
        .upsert(rows, onConflict: 'cardsight_id')
        .select('cardsight_id');

    var imported = 0;
    for (final row in upserted as List) {
      final id = (row as Map<String, dynamic>)['cardsight_id'] as String;
      if (!existingIds.contains(id)) imported++;
    }

    return {'imported': imported, 'total': selected.length};
  }

  String _functionErrorMessage(FunctionResponse res, String fallback) {
    final data = res.data;
    if (data is Map && data['error'] != null) {
      return data['error'].toString();
    }
    if (data is String && data.isNotEmpty) return data;
    return '$fallback (${res.status})';
  }

  Future<List<PendingParallel>> getPendingParallels() async {
    final data = await _supabase
        .from('pending_parallels')
        .select('id, set_id, name, submission_count, status, sets(name, releases(name))')
        .eq('status', 'pending')
        .order('submission_count', ascending: false);
    return (data as List).map((r) => PendingParallel.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<void> promotePendingParallel({
    required String id,
    required String setId,
    required String name,
    int? serialMax,
    bool isAuto = false,
    String? colorHex,
  }) async {
    final hex = (colorHex?.isNotEmpty ?? false) ? colorHex : null;
    await _supabase.from('set_parallels').upsert({
      'set_id': setId,
      'name': name,
      if (serialMax case final v?) 'serial_max': v,
      'is_auto': isAuto,
      if (hex case final v?) 'color_hex': v,
    }, onConflict: 'set_id,name');
    await _supabase.from('pending_parallels').update({'status': 'approved'}).eq('id', id);
  }

  Future<void> dismissPendingParallel(String id) async {
    await _supabase.from('pending_parallels').update({'status': 'dismissed'}).eq('id', id);
  }

  Future<void> upsertParallels(String setId, List<Map<String, dynamic>> parallels) async {
    final rows = parallels.map((p) => {'set_id': setId, ...p}).toList();
    await _supabase.from('set_parallels').upsert(rows, onConflict: 'set_id,name');
  }

  Future<void> deleteParallel(String id) async {
    await _supabase.from('set_parallels').delete().eq('id', id);
  }

  Future<({String userCardId, String masterCardId})> addCard(AddCardFormData form) async {
    String? formMasterId = form.masterCardId;
    String normalizedParallelName = form.parallelName.trim().isEmpty ? 'Base' : form.parallelName.trim();

    late String catalogVariantId;
    if (formMasterId == null) {
      if (form.setId == null) {
        throw Exception('setId is required when creating a set_card from the form');
      }
      final parallels = await getParallels(form.setId!);
      if (parallels.isEmpty) {
        throw Exception('Add at least one parallel to this set before adding a card');
      }
      final baseParallel = pickDefaultPaperParallel(parallels);
      if (baseParallel == null) {
        throw Exception('Add at least one parallel to this set before adding a card');
      }
      final scRow = await _supabase
          .from('set_cards')
          .insert({
            'set_id': form.setId,
            'player': form.player,
            'card_number': form.cardNumber,
            'is_rookie': form.isRookie,
          })
          .select('id')
          .single();
      final ins = await _supabase
          .from('master_card_definitions')
          .insert({
            'set_card_id': scRow['id'] as String,
            'parallel_id': baseParallel.id,
            'is_auto': form.isAuto,
            'is_patch': form.isPatch,
            'is_ssp': form.isSSP,
            'serial_max': form.serialMax,
          })
          .select('id')
          .single();
      catalogVariantId = ins['id'] as String;
    } else {
      catalogVariantId = formMasterId;
    }

    catalogVariantId = await ensureCatalogVariant(
      catalogVariantId: catalogVariantId,
      parallelId: form.parallelId,
    );

    // Canonicalize parallel_name from the selected parallel row whenever possible.
    if (form.parallelId != null && form.parallelId!.isNotEmpty) {
      final parallelRow = await _supabase
          .from('set_parallels')
          .select('name')
          .eq('id', form.parallelId!)
          .maybeSingle();
      final dbName = parallelRow == null
          ? null
          : (Map<String, dynamic>.from(parallelRow)['name'] as String?)?.trim();
      if (dbName != null && dbName.isNotEmpty) {
        normalizedParallelName = dbName;
      }
    }

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final result = await _supabase.from('user_cards').insert({
      'master_card_id': catalogVariantId,
      'user_id': userId,
      'parallel_id': form.parallelId,
      'parallel_name': normalizedParallelName,
      'price_paid': form.pricePaid,
      'serial_number': form.serialNumber?.isNotEmpty == true ? form.serialNumber : null,
      'is_graded': form.isGraded,
      'grader': form.isGraded ? form.grader : null,
      'grade_value': form.isGraded && form.gradeValue?.isNotEmpty == true ? form.gradeValue : null,
    }).select('id').single();

    return (
      userCardId: result['id'] as String,
      masterCardId: catalogVariantId,
    );
  }

  /// Fuzzy search across releases, sets, and cards in the catalog
  Future<({
    List<ReleaseRecord> releases,
    List<(SetRecord, ReleaseRecord)> sets,
    List<(MasterCard, SetRecord, ReleaseRecord)> cards,
  })> searchCatalog(String query) async {
    final queryTrim = query.trim();
    final releases = <ReleaseRecord>[];
    final sets = <(SetRecord, ReleaseRecord)>[];
    final cards = <(MasterCard, SetRecord, ReleaseRecord)>[];

    if (queryTrim.isEmpty) return (releases: releases, sets: sets, cards: cards);

    // Cache for release lookups to avoid fetching the same release multiple times
    final releaseCache = <String, ReleaseRecord>{};

    try {
      // Search releases by name or sport
      final releaseData = await _supabase
          .from('releases')
          .select('id, name, year, sport, cardsight_id, sets(id, set_cards(count))')
          .ilike('name', '%$queryTrim%')
          .order('year', ascending: false)
          .limit(20);
      releases.addAll((releaseData as List).map((r) => ReleaseRecord.fromJson(r as Map<String, dynamic>)));
    } catch (_) {}

    try {
      // Search sets by name (without nested joins)
      final setData = await _supabase
          .from('sets')
          .select('id, name, card_count, cardsight_id, release_id')
          .ilike('name', '%$queryTrim%')
          .limit(30);

      for (final s in setData as List) {
        final setMap = s as Map<String, dynamic>;
        final releaseId = setMap['release_id'] as String?;

        if (releaseId != null) {
          // Get release info (use cache if already fetched)
          ReleaseRecord? release = releaseCache[releaseId];
          if (release == null) {
            try {
              final releaseData = await _supabase
                  .from('releases')
                  .select('id, name, year, sport, cardsight_id')
                  .eq('id', releaseId)
                  .single();
              release = ReleaseRecord.fromJson(releaseData as Map<String, dynamic>);
              releaseCache[releaseId] = release;
            } catch (_) {}
          }

          if (release != null) {
            final set = SetRecord(
              id: setMap['id'] as String,
              name: setMap['name'] as String,
              cardCount: _tryParseInt(setMap['card_count']),
              catalogImportSetKey: setMap['cardsight_id'] as String?,
            );
            sets.add((set, release));
          }
        }
      }
    } catch (_) {}

    try {
      // Search cards by player name (without nested joins)
      final cardData = await _supabase
          .from('set_card_base_variants')
          .select('id, player, card_number, is_rookie, is_auto, is_patch, is_ssp, serial_max, image_url, set_id')
          .ilike('player', '%$queryTrim%')
          .limit(50);

      for (final c in cardData as List) {
        final cardMap = c as Map<String, dynamic>;
        final setId = cardMap['set_id'] as String?;

        if (setId != null) {
          try {
            // Fetch set info
            final setData = await _supabase
                .from('sets')
                .select('id, name, card_count, cardsight_id, release_id')
                .eq('id', setId)
                .single();

            final setMap = setData as Map<String, dynamic>;
            final releaseId = setMap['release_id'] as String?;

            if (releaseId != null) {
              // Get release info (use cache if already fetched)
              ReleaseRecord? release = releaseCache[releaseId];
              if (release == null) {
                try {
                  final releaseData = await _supabase
                      .from('releases')
                      .select('id, name, year, sport, cardsight_id')
                      .eq('id', releaseId)
                      .single();
                  release = ReleaseRecord.fromJson(releaseData as Map<String, dynamic>);
                  releaseCache[releaseId] = release;
                } catch (_) {}
              }

              if (release != null) {
                final card = MasterCard.fromJson(cardMap);
                final set = SetRecord(
                  id: setMap['id'] as String,
                  name: setMap['name'] as String,
                  cardCount: _tryParseInt(setMap['card_count']),
                  catalogImportSetKey: setMap['cardsight_id'] as String?,
                );
                cards.add((card, set, release));
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    return (releases: releases, sets: sets, cards: cards);
  }
}

final cardsServiceProvider = Provider<CardsService>((ref) {
  return CardsService(ref.watch(supabaseProvider));
});

final pendingParallelsProvider = FutureProvider<List<PendingParallel>>((ref) async {
  return ref.watch(cardsServiceProvider).getPendingParallels();
});

final pendingParallelCountProvider = FutureProvider<int>((ref) async {
  final list = await ref.watch(cardsServiceProvider).getPendingParallels();
  return list.length;
});

final parallelsProvider = FutureProvider.family<List<SetParallel>, String>((ref, setId) async {
  return ref.watch(cardsServiceProvider).getParallels(setId);
});

final setsForReleaseProvider = FutureProvider.family<List<SetRecord>, String>((ref, releaseId) async {
  return ref.watch(cardsServiceProvider).getSetsForRelease(releaseId);
});

final userCardsProvider = FutureProvider<List<UserCard>>((ref) async {
  return ref.watch(cardsServiceProvider).loadUserCards();
});

// ── Admin models ──────────────────────────────────────────────────────────────

class PendingParallel {
  const PendingParallel({
    required this.id,
    required this.setId,
    required this.name,
    required this.submissionCount,
    required this.status,
    this.setName,
    this.releaseName,
  });
  final String id;
  final String setId;
  final String name;
  final int submissionCount;
  final String status;
  final String? setName;
  final String? releaseName;

  factory PendingParallel.fromJson(Map<String, dynamic> j) {
    final set = j['sets'] as Map<String, dynamic>?;
    final release = set?['releases'] as Map<String, dynamic>?;
    return PendingParallel(
      id:              j['id'] as String,
      setId:           j['set_id'] as String,
      name:            j['name'] as String,
      submissionCount: _tryParseInt(j['submission_count']) ?? 1,
      status:          j['status'] as String? ?? 'pending',
      setName:         set?['name'] as String?,
      releaseName:     release?['name'] as String?,
    );
  }
}

final cardStacksProvider = Provider<AsyncValue<List<CardStack>>>((ref) {
  return ref.watch(userCardsProvider).whenData(CardStack.fromCards);
});

