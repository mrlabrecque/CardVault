import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';
import '../models/user_card.dart';

class SetParallel {
  const SetParallel({required this.id, required this.name, this.serialMax, this.isAuto = false});
  final String id;
  final String name;
  final int? serialMax;
  final bool isAuto;

  factory SetParallel.fromJson(Map<String, dynamic> j) => SetParallel(
    id: j['id'] as String,
    name: j['name'] as String,
    serialMax: j['serial_max'] as int?,
    isAuto: j['is_auto'] as bool? ?? false,
  );
}

class ReleaseRecord {
  const ReleaseRecord({required this.id, required this.name, this.year, this.sport, this.cardsightId});
  final String id;
  final String name;
  final int? year;
  final String? sport;
  final String? cardsightId;

  factory ReleaseRecord.fromJson(Map<String, dynamic> j) => ReleaseRecord(
    id:          j['id'] as String,
    name:        j['name'] as String,
    year:        j['year'] as int?,
    sport:       j['sport'] as String?,
    cardsightId: j['cardsight_id'] as String?,
  );

  String get displayName => year != null ? '$year $name' : name;
}

class SetRecord {
  const SetRecord({required this.id, required this.name, this.cardCount, this.cardsightId});
  final String id;
  final String name;
  final int? cardCount;
  final String? cardsightId;

  factory SetRecord.fromJson(Map<String, dynamic> j) => SetRecord(
    id:          j['id'] as String,
    name:        j['name'] as String,
    cardCount:   j['card_count'] as int?,
    cardsightId: j['cardsight_id'] as String?,
  );
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

  factory MasterCard.fromJson(Map<String, dynamic> j) => MasterCard(
    id: j['id'] as String,
    player: j['player'] as String? ?? '',
    cardNumber: j['card_number'] as String?,
    isRookie: j['is_rookie'] as bool? ?? false,
    isAuto: j['is_auto'] as bool? ?? false,
    isPatch: j['is_patch'] as bool? ?? false,
    isSSP: j['is_ssp'] as bool? ?? false,
    serialMax: j['serial_max'] as int?,
    imageUrl: j['image_url'] as String?,
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
    parallelCount: (j['parallelCount'] as int?) ?? 0,
    cardCount:     j['cardCount'] as int?,
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

  Future<List<UserCard>> loadUserCards() async {
    final data = await _supabase.from('user_cards').select('''
      id, master_card_id, parallel_id, parallel_name,
      price_paid, current_value, previous_value, serial_number,
      is_graded, grader, grade_value, created_at,
      weekly_price_check, value_refreshed_at,
      master_card_definitions (
        player, card_number, is_rookie, is_auto, is_patch, is_ssp, serial_max, image_url,
        sets ( id, name, card_count, releases ( year, sport, name ) )
      ),
      set_parallels!parallel_id ( name, serial_max, is_auto, color_hex )
    ''').order('created_at', ascending: false);


    return (data as List).map((r) => UserCard.fromJson(r as Map<String, dynamic>)).toList();
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
    var q = _supabase.from('releases').select('id, name, year, sport, cardsight_id');
    if (query.trim().isNotEmpty) {
      q = q.ilike('name', '%${query.trim()}%');
    }
    final data = await q.order('year', ascending: false).limit(30);
    return (data as List).map((r) => ReleaseRecord.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// Browses releases from our DB — no API call. Paginated.
  Future<List<ReleaseRecord>> browseReleases({int? year, String? sport, int offset = 0, int limit = 30}) async {
    var q = _supabase.from('releases').select('id, name, year, sport, cardsight_id');
    if (year != null) q = q.eq('year', year);
    if (sport != null && sport.isNotEmpty) q = q.eq('sport', sport);
    final data = await q
        .order('year', ascending: false)
        .order('name')
        .range(offset, offset + limit - 1);
    return (data as List).map((r) => ReleaseRecord.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// Lazily fetches sets for a release from CardSight and caches them in DB.
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
      'cardsight_id': r['cardsightId'],
    })).toList();
  }

  Future<List<SetRecord>> getSetsForRelease(String releaseId) async {
    final data = await _supabase
        .from('sets')
        .select('id, name, card_count, cardsight_id')
        .eq('release_id', releaseId)
        .order('name');
    return (data as List).map((r) => SetRecord.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// Lazily imports all cards for a set from CardSight and caches them in DB.
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
        .from('master_card_definitions')
        .select('id, player, card_number, is_rookie, is_auto, is_patch, is_ssp, serial_max, image_url')
        .eq('set_id', setId);
    if (query.trim().isNotEmpty) {
      q = q.ilike('player', '%${query.trim()}%');
    }
    final data = await q.order('player').range(offset, offset + limit - 1);
    return (data as List).map((r) => MasterCard.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<void> setWeeklyPriceCheck(String cardId, bool enabled) async {
    await _supabase
        .from('user_cards')
        .update({'weekly_price_check': enabled})
        .eq('id', cardId);
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

  Future<String> addCard(AddCardFormData form) async {
    String? masterCardId = form.masterCardId;

    if (masterCardId == null) {
      final result = await _supabase
          .from('master_card_definitions')
          .insert({
            'set_id': form.setId,
            'player': form.player,
            'card_number': form.cardNumber,
            'serial_max': form.serialMax,
            'is_rookie': form.isRookie,
            'is_auto': form.isAuto,
            'is_patch': form.isPatch,
            'is_ssp': form.isSSP,
          })
          .select('id')
          .single();
      masterCardId = result['id'] as String;
    }

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final result = await _supabase.from('user_cards').insert({
      'master_card_id': masterCardId,
      'user_id': userId,
      'parallel_id': form.parallelId,
      'parallel_name': form.parallelName,
      'price_paid': form.pricePaid,
      'serial_number': form.serialNumber?.isNotEmpty == true ? form.serialNumber : null,
      'is_graded': form.isGraded,
      'grader': form.isGraded ? form.grader : null,
      'grade_value': form.isGraded && form.gradeValue?.isNotEmpty == true ? form.gradeValue : null,
    }).select('id').single();

    return result['id'] as String;
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
      submissionCount: j['submission_count'] as int? ?? 1,
      status:          j['status'] as String? ?? 'pending',
      setName:         set?['name'] as String?,
      releaseName:     release?['name'] as String?,
    );
  }
}

final cardStacksProvider = Provider<AsyncValue<List<CardStack>>>((ref) {
  return ref.watch(userCardsProvider).whenData(CardStack.fromCards);
});

/// IDs of the top 50 cards by current value — these are auto-refreshed daily.
final dailyTierCardIdsProvider = Provider<Set<String>>((ref) {
  final cards = ref.watch(userCardsProvider).value ?? [];
  final sorted = [...cards]..sort((a, b) => (b.currentValue ?? 0).compareTo(a.currentValue ?? 0));
  return sorted.take(50).map((c) => c.id).toSet();
});
