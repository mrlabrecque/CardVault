import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';
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
    this.importedCount = 0,
  });
  final String id;
  final String name;
  final int? cardCount;
  /// External id for the catalog import provider (matches the import column on `sets`).
  final String? catalogImportSetKey;
  final int importedCount;

  factory SetRecord.fromJson(Map<String, dynamic> j) {
    final defsRaw = j['set_cards'] as List?;
    return SetRecord(
      id:            j['id'] as String,
      name:          j['name'] as String,
      cardCount:     _tryParseInt(j['card_count']),
      catalogImportSetKey: j['cardsight_id'] as String?,
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
    })).toList();
  }

  Future<List<SetRecord>> getSetsForRelease(String releaseId) async {
    final data = await _supabase
        .from('sets')
        .select('id, name, card_count, cardsight_id, set_cards(count)')
        .eq('release_id', releaseId)
        .order('name', ascending: true);
    return (data as List).map((r) => SetRecord.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// Lazily imports all cards for a set from the catalog API and caches them in DB.
  Future<void> importCardsForSet({
    required String cardsightReleaseId,
    required String cardsightSetId,
    required String setId,
  }) async {
    final res = await _supabase.functions.invoke(
      'catalog-import-cards',
      body: {
        'cardsightReleaseId': cardsightReleaseId,
        'cardsightSetId': cardsightSetId,
        'setId': setId,
      },
    );
    if (res.status != 200) throw Exception('Import cards failed: ${res.status}');
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

  /// Loads any catalog variant by `master_card_definitions.id` (not limited to Base —
  /// unlike [set_card_base_variants], which exposes one row per checklist line).
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

  /// Resolves [catalogVariantId] (any variant of a checklist line) to the row for [parallelId],
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
        .select('is_auto, is_patch, is_ssp, serial_max')
        .eq('id', catalogVariantId)
        .single();

    final inserted = await _supabase.from('master_card_definitions').insert({
      'set_card_id': setCardId,
      'parallel_id': targetParallel,
      'is_auto': flags['is_auto'] as bool? ?? false,
      'is_patch': flags['is_patch'] as bool? ?? false,
      'is_ssp': flags['is_ssp'] as bool? ?? false,
      'serial_max': flags['serial_max'],
    }).select('id').single();
    return inserted['id'] as String;
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

  /// Resolve a catalog card: lazy-import set + parallels, then find or import the card
  Future<({String masterCardId, String setId, List<SetParallel> parallels})>
      resolveCardFromCatalog({
    required CatalogSearchCardResult card,
    required String releaseName,
    required int releaseYear,
    String? releaseSegmentId,
  }) async {
    // Step 1: Lazy-import set + parallels
    final importResult = await lazyImportCatalog(
      cardsightReleaseId: card.releaseId,
      releaseName: releaseName,
      releaseYear: releaseYear.toString(),
      releaseSegmentId: releaseSegmentId ?? '',
      cardsightSetId: card.setId,
    );
    final setId = importResult.setId;
    final parallels = importResult.parallels;

    // Step 2: Check if card already exists in DB (set_cards by external catalog card id)
    final existingSc = await _supabase
        .from('set_cards')
        .select('id')
        .eq('cardsight_card_id', card.id)
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

    // Step 3: Import all cards for this set, then look up the card
    await importCardsForSet(
      cardsightReleaseId: card.releaseId,
      cardsightSetId: card.setId,
      setId: setId,
    );

    final foundSc = await _supabase
        .from('set_cards')
        .select('id')
        .eq('cardsight_card_id', card.id)
        .maybeSingle();

    if (foundSc == null) {
      throw Exception('Card not found in catalog after import');
    }

    final v = await _supabase
        .from('set_card_base_variants')
        .select('id')
        .eq('set_card_id', foundSc['id'] as String)
        .single();

    return (masterCardId: v['id'] as String, setId: setId, parallels: parallels);
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

  Future<Map<String, dynamic>> bulkImportReleases({
    required int year,
    required String segment,
    int skip = 0,
  }) async {
    final res = await _supabase.functions.invoke('catalog-bulk-import', body: {
      'year': year,
      'segment': segment,
      'skip': skip,
    });
    if (res.status != 200) throw Exception('Bulk import failed: ${res.status}');
    return res.data as Map<String, dynamic>;
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
        throw Exception('setId is required when creating a checklist card');
      }
      final parallels = await getParallels(form.setId!);
      if (parallels.isEmpty) {
        throw Exception('Add at least one parallel to this set before adding a card');
      }
      SetParallel baseParallel = parallels.first;
      for (final p in parallels) {
        if (p.name.trim().toLowerCase() == 'base') {
          baseParallel = p;
          break;
        }
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

