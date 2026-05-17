import 'dart:convert' show jsonDecode, JsonEncoder;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';
import '../models/cardhedge_image_search.dart';
import '../models/guide_catalog_match.dart';
import '../models/comp.dart';
import '../utils/guide_grade_prices.dart';
import '../utils/guide_catalog_match_query.dart';
import 'cards_service.dart' show MasterCard;

/// `functions.invoke` may return a parsed [Map] or a JSON [String] depending on client/runtime.
Map<String, dynamic>? _functionInvokeBodyAsMap(dynamic raw) {
  if (raw == null) return null;
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is String) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    try {
      final o = jsonDecode(t);
      if (o is Map<String, dynamic>) return o;
      if (o is Map) return Map<String, dynamic>.from(o);
    } catch (_) {}
  }
  return null;
}

/// Grade price map plus newest `current_prices.fetched_at` for staleness checks.
/// Result from [ensureGuideGradeComps] / [fetchGuideGradeComps] (CardHedge comps API + DB).
class GuideGradeCompsResult {
  const GuideGradeCompsResult({
    required this.saleCount,
    this.fromCache = false,
    this.high,
    this.low,
    this.compPrice,
  });

  /// Rows stored for this grade, or existing row count when [fromCache].
  final int saleCount;

  /// True when [hasFreshGuideGradeComps] skipped the upstream request.
  final bool fromCache;

  final double? high;
  final double? low;
  final double? compPrice;

  bool get hasPriceRange =>
      high != null && high! > 0 && low != null && low! > 0;
}

class MasterCardCurrentPricesSnapshot {
  const MasterCardCurrentPricesSnapshot({
    required this.prices,
    required this.newestFetchedAt,
  });

  final Map<String, double?> prices;
  final DateTime? newestFetchedAt;

  bool get hasAnyPrice => guideGradeMapHasAnyPrice(prices);

  bool get isStale => guideCurrentPricesAreStale(newestFetchedAt);
}

class CompsService {
  CompsService(this._supabase);
  final SupabaseClient _supabase;
  static const Duration _compsRefreshCooldown = Duration(hours: 24);

  String _extractErrorMessage(dynamic raw) {
    if (raw == null) return '';
    if (raw is String) return raw;
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final direct = map['error'] ?? map['message'] ?? map['details'];
      if (direct != null && direct.toString().trim().isNotEmpty) {
        return direct.toString();
      }
      return map.toString();
    }
    return raw.toString();
  }

  Exception _friendlyRefreshException({
    int? status,
    dynamic payload,
    Object? source,
  }) {
    final payloadMessage = _extractErrorMessage(payload);
    final lower = payloadMessage.toLowerCase();
    if (status == 404) {
      return Exception(
        'Price refresh service is not deployed. Run: supabase functions deploy refresh-comps',
      );
    }
    if (lower.contains('rapidapi') ||
        lower.contains('scrapegraphai') ||
        lower.contains('scrapingbee') ||
        lower.contains('brightdata') ||
        lower.contains('forbidden')) {
      return Exception(
        'Pricing provider rejected this request. Please verify your pricing API credentials in Supabase secrets, then try again.',
      );
    }
    if (status == 502 || status == 503 || status == 504) {
      return Exception(
        'Could not refresh market data right now. Showing your most recent saved values. Please try again in a few minutes.',
      );
    }
    if (lower.contains('marketplace temporarily blocked') ||
        lower.contains('ebay_bot_protection_page') ||
        lower.contains('task not found') ||
        lower.contains('incorrect username or password')) {
      return Exception(
        'Could not refresh market data right now. Showing your most recent saved values. Please try again soon.',
      );
    }
    if (source != null) {
      return Exception(
        'Could not refresh market data right now. Please try again shortly.',
      );
    }
    return Exception(
      'Could not refresh market data right now. Please try again shortly.',
    );
  }

  Future<List<Comp>> search(String query) async {
    final res = await _supabase.functions.invoke(
      'comps-search',
      body: {'query': query},
    );
    if (res.status != 200) throw Exception('Search failed: ${res.status}');
    final data = res.data as Map<String, dynamic>;
    final items = data['items'] as List? ?? [];
    return items.map((r) => Comp.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<List<Comp>> getCardComps(String cardId) async {
    final cardData = await _supabase
        .from('user_cards')
        .select('master_card_id')
        .eq('id', cardId)
        .single();

    final masterId = (cardData as Map)['master_card_id'] as String?;

    if (masterId == null) {
      return [];
    }

    return getMasterCardComps(masterId);
  }

  Future<List<Comp>> getMasterCardComps(String masterCardId) async {
    final data = await _supabase
        .from('card_sold_comps')
        .select('title, price, currency, sale_type, sold_at, url, image_url, grade')
        .eq('master_card_id', masterCardId)
        .order('sold_at', ascending: false, nullsFirst: false);
    return (data as List).map((r) => Comp.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// Distinct `grade` values with saved sold comps for this catalog variant.
  Future<List<String>> listCachedCompsGradesForMaster(String masterCardId) async {
    final id = masterCardId.trim();
    if (id.isEmpty) return const [];
    final data = await _supabase
        .from('card_sold_comps')
        .select('grade')
        .eq('master_card_id', id);
    final out = <String>[];
    for (final row in data as List) {
      if (row is! Map) continue;
      final g = row['grade']?.toString().trim() ?? '';
      if (g.isEmpty) continue;
      var duplicate = false;
      for (final existing in out) {
        if (currentPricesGradeLooselyEqual(existing, g)) {
          duplicate = true;
          break;
        }
      }
      if (!duplicate) out.add(g);
    }
    out.sort(compareGuidePriceGradeLabels);
    return out;
  }

  /// True when [card_sold_comps] has at least one row for this variant + [grade] (`Raw`, `PSA 10`, …).
  Future<bool> hasSoldCompsForGrade(String masterCardId, String grade) async {
    final norm = grade.trim().isEmpty ? 'Raw' : grade.trim();
    var data = await _supabase
        .from('card_sold_comps')
        .select('id')
        .eq('master_card_id', masterCardId.trim())
        .eq('grade', norm)
        .limit(1);
    if ((data as List).isNotEmpty) return true;
    if (norm == 'Raw') {
      data = await _supabase
          .from('card_sold_comps')
          .select('id')
          .eq('master_card_id', masterCardId.trim())
          .ilike('grade', 'raw')
          .limit(1);
      return (data as List).isNotEmpty;
    }
    return false;
  }

  /// Grade averages from `current_prices` (written when a guide-price card is linked).
  Future<Map<String, double?>> getMasterCardCurrentPrices(String masterCardId) async {
    return (await loadMasterCardCurrentPricesSnapshot(masterCardId)).prices;
  }

  /// Loads display-grade prices and the newest `fetched_at` across rows for this variant.
  Future<MasterCardCurrentPricesSnapshot> loadMasterCardCurrentPricesSnapshot(
    String masterCardId,
  ) async {
    final data = await _supabase
        .from('current_prices')
        .select('grade, price, fetched_at')
        .eq('master_card_id', masterCardId.trim());
    final rows = <Map<String, dynamic>>[];
    DateTime? newestFetchedAt;
    for (final row in data as List) {
      final m = Map<String, dynamic>.from(row as Map);
      rows.add(m);
      final rawFt = m['fetched_at'];
      if (rawFt != null) {
        final t = DateTime.tryParse(rawFt.toString());
        if (t != null && (newestFetchedAt == null || t.isAfter(newestFetchedAt))) {
          newestFetchedAt = t;
        }
      }
    }
    return MasterCardCurrentPricesSnapshot(
      prices: parseCurrentPricesRowsToMap(rows),
      newestFetchedAt: newestFetchedAt,
    );
  }

  /// Re-fetches guide prices + sales/gain from CardHedge when linked; updates `current_prices`
  /// and `master_card_definitions.cardhedge_fetched_at` via [persistCardHedgeHydratedFromCardId].
  Future<MasterCard?> refreshStaleLinkedGuidePrices({
    required String masterVariantId,
    required String guidePriceCardId,
  }) {
    return persistCardHedgeHydratedFromCardId(
      masterVariantId: masterVariantId,
      guidePriceCardId: guidePriceCardId,
    );
  }

  /// Same hydration path as [CardDetailScreen] catalog guide sync:
  /// when `cardhedge_id` is set and `current_prices` has fresh rows, no network call;
  /// when stale (>24h), hydrates from CardHedge; otherwise invokes catalog search.
  ///
  /// Call after adding to collection or when opening item detail so `current_prices`
  /// and `master_card_definitions` match what the catalog detail screen would load.
  Future<void> syncMasterCatalogPricingForVariant(String masterVariantId) async {
    final trimId = masterVariantId.trim();
    if (trimId.isEmpty) return;

    final raw = await _supabase.from('master_card_definitions').select('''
      cardhedge_id,
      set_cards ( player, card_number, sets ( name, releases ( year, sport, name ) ) ),
      set_parallels ( name )
    ''').eq('id', trimId).maybeSingle();
    if (raw == null) return;
    final row = Map<String, dynamic>.from(raw as Map);

    final linkedGuideCardId = row['cardhedge_id']?.toString().trim();
    if (linkedGuideCardId != null && linkedGuideCardId.isNotEmpty) {
      final snap = await loadMasterCardCurrentPricesSnapshot(trimId);
      if (snap.hasAnyPrice && !snap.isStale) return;
      if (snap.hasAnyPrice && snap.isStale) {
        await refreshStaleLinkedGuidePrices(
          masterVariantId: trimId,
          guidePriceCardId: linkedGuideCardId,
        );
        return;
      }
    }

    Map<String, dynamic>? asMap(dynamic v) {
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
      return null;
    }

    final sc = asMap(row['set_cards']);
    final player = sc?['player']?.toString().trim() ?? '';
    if (player.isEmpty) return;
    final cardNumber = sc?['card_number']?.toString();
    final sets = asMap(sc?['sets']);
    final checklistName = sets?['name']?.toString();
    final rel = asMap(sets?['releases']);
    int? yearVal;
    final y = rel?['year'];
    if (y is int) {
      yearVal = y;
    } else if (y is num) {
      yearVal = y.toInt();
    } else if (y != null) {
      yearVal = int.tryParse(y.toString());
    }
    final releaseName = rel?['name']?.toString();
    final sport = rel?['sport']?.toString();
    final par = asMap(row['set_parallels']);
    final parallelName = par?['name']?.toString();

    await searchGuidePriceCatalog(
      player: player,
      year: yearVal,
      releaseName: releaseName,
      setName: checklistName,
      sport: sport,
      cardNumber: cardNumber,
      parallelName: parallelName,
      persistMasterVariantId: trimId,
    );
  }

  /// True when any comps exist for this catalog variant + grade within the last 24h.
  Future<bool> hasFreshGuideGradeComps(
    String masterCardId,
    String grade,
  ) async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24)).toIso8601String();
    final g = grade.trim().isEmpty ? 'Raw' : grade.trim();
    final rows = await _supabase
        .from('card_sold_comps')
        .select('id')
        .eq('master_card_id', masterCardId)
        .eq('grade', g)
        .gte('fetched_at', cutoff)
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  /// Min/max sale price for a variant + grade from stored [card_sold_comps] rows.
  Future<({double? low, double? high, int count})> getSoldCompsPriceRangeForGrade(
    String masterCardId,
    String grade,
  ) async {
    final id = masterCardId.trim();
    if (id.isEmpty) return (low: null, high: null, count: 0);

    final norm = grade.trim().isEmpty ? 'Raw' : grade.trim();
    var data = await _supabase
        .from('card_sold_comps')
        .select('price, grade')
        .eq('master_card_id', id)
        .eq('grade', norm);

    var rows = data as List;
    if (rows.isEmpty && norm == 'Raw') {
      data = await _supabase
          .from('card_sold_comps')
          .select('price, grade')
          .eq('master_card_id', id)
          .ilike('grade', 'raw');
      rows = data as List;
    }

    double? low;
    double? high;
    var count = 0;
    for (final row in rows) {
      if (row is! Map) continue;
      final m = Map<String, dynamic>.from(row);
      final g = m['grade']?.toString() ?? '';
      if (!currentPricesGradeLooselyEqual(g, norm)) continue;
      final p = parsePostgresNumeric(m['price']);
      if (p == null || p <= 0) continue;
      count++;
      if (low == null || p < low) low = p;
      if (high == null || p > high) high = p;
    }
    return (low: low, high: high, count: count);
  }

  /// Loads upstream sold comps for the grade unless [hasFreshGuideGradeComps] is true.
  Future<GuideGradeCompsResult?> ensureGuideGradeComps({
    required String masterVariantId,
    required String guidePriceCardId,
    required String grade,
    int count = 40,
  }) async {
    if (await hasFreshGuideGradeComps(masterVariantId, grade)) {
      final range = await getSoldCompsPriceRangeForGrade(masterVariantId, grade);
      return GuideGradeCompsResult(
        saleCount: range.count,
        fromCache: true,
        high: range.high,
        low: range.low,
      );
    }
    return fetchGuideGradeComps(
      masterVariantId: masterVariantId,
      guidePriceCardId: guidePriceCardId,
      grade: grade,
      count: count,
    );
  }

  Future<List<ActiveListing>> getActiveListings(String masterCardId) async {
    try {
      final res = await _supabase.functions.invoke(
        'card-active-listings',
        body: {'masterCardId': masterCardId},
      );
      if (res.status != 200) {
        final err = (res.data is Map ? (res.data as Map)['error'] : null) ?? 'Request failed';
        throw Exception('Active listings failed: $err');
      }
      final raw = res.data;
      if (raw == null) return [];
      if (raw is! Map) {
        throw Exception('Active listings: bad response shape');
      }
      final data = Map<String, dynamic>.from(raw);
      final itemsRaw = data['items'];
      if (itemsRaw is! List) return [];
      final out = <ActiveListing>[];
      for (final r in itemsRaw) {
        if (r is! Map) continue;
        try {
          out.add(ActiveListing.fromJson(Map<String, dynamic>.from(r)));
        } catch (_) {
          continue;
        }
      }
      return out;
    } on FunctionException catch (e) {
      if (e.status == 404) {
        throw Exception(
          'Active listings are not deployed. Run: supabase functions deploy card-active-listings',
        );
      }
      throw Exception('Active listings failed (${e.status}): $e');
    }
  }

  Future<void> refreshMasterCardComps(String masterCardId) async {
    try {
      final res = await _supabase.functions.invoke(
        'refresh-comps',
        body: {'masterCardId': masterCardId},
      );
      if (res.status != 200) {
        throw _friendlyRefreshException(status: res.status, payload: res.data);
      }
    } on FunctionException catch (e) {
      throw _friendlyRefreshException(status: e.status, source: e, payload: e.details);
    }
  }

  Future<void> refreshCardValue(String cardId) async {
    await refreshCardValues([cardId]);
  }

  double _valueForGrade({
    required bool isGraded,
    required String? gradeValue,
    required double rawAvg,
    required double psa9Avg,
    required double psa10Avg,
  }) {
    if (!isGraded) return rawAvg;
    if (gradeValue == '10' || gradeValue == '10.0') return psa10Avg;
    if (gradeValue == '9' || gradeValue == '9.0') return psa9Avg;
    return rawAvg;
  }

  double _averageForGrade(List<Comp> comps, String grade) {
    final filtered = comps.where((c) => (c.grade ?? 'Raw') == grade).toList();
    if (filtered.isEmpty) return 0;
    final total = filtered.fold<double>(0, (sum, c) => sum + c.price);
    return total / filtered.length;
  }

  Future<void> _writeUserCardValuesFromAverages({
    required List<Map<String, dynamic>> matchingRows,
    required double rawAvg,
    required double psa10Avg,
    required double psa9Avg,
  }) async {
    final refreshedAt = DateTime.now().toIso8601String();
    for (final card in matchingRows) {
      final id = card['id'] as String?;
      if (id == null) continue;
      final isGraded = card['is_graded'] as bool? ?? false;
      final gradeValue = _normalizeGradeValue(card['grade_value']);
      final currentValue = _valueForGrade(
        isGraded: isGraded,
        gradeValue: gradeValue,
        rawAvg: rawAvg,
        psa9Avg: psa9Avg,
        psa10Avg: psa10Avg,
      );
      await _supabase.from('user_cards').update({
        'current_value': currentValue,
        'value_refreshed_at': refreshedAt,
      }).eq('id', id);
    }
  }

  Future<bool> _hasFreshCachedComps(String masterCardId) async {
    final cutoff = DateTime.now().subtract(_compsRefreshCooldown).toIso8601String();
    final rows = await _supabase
        .from('card_sold_comps')
        .select('id')
        .eq('master_card_id', masterCardId)
        .gte('fetched_at', cutoff)
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  String? _normalizeGradeValue(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  Future<void> refreshCardValues(List<String> cardIds) async {
    if (cardIds.isEmpty) return;

    final rows = <Map<String, dynamic>>[];
    for (final cardId in cardIds) {
      final cardData = await _supabase
          .from('user_cards')
          .select('id, master_card_id, is_graded, grade_value')
          .eq('id', cardId)
          .maybeSingle();
      if (cardData == null) continue;
      rows.add(Map<String, dynamic>.from(cardData as Map));
    }
    if (rows.isEmpty) return;

    final byCompsKey = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final id = row['id'] as String?;
      final masterId = row['master_card_id'] as String?;
      if (id == null || masterId == null) continue;
      final key = masterId;
      byCompsKey.putIfAbsent(key, () => []).add(row);
    }
    if (byCompsKey.isEmpty) {
      throw Exception('This card is missing catalog data and cannot be refreshed yet.');
    }

    for (final entry in byCompsKey.entries) {
      final first = entry.value.first;
      final masterId = first['master_card_id'] as String;

      final matchingRowsRaw = await _supabase
          .from('user_cards')
          .select('id, master_card_id, is_graded, grade_value')
          .eq('master_card_id', masterId);
      final matchingRows = (matchingRowsRaw as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

      final masterRow = await _supabase
          .from('master_card_definitions')
          .select('cardhedge_id')
          .eq('id', masterId)
          .maybeSingle();
      final linkedGuidePriceCardId = (masterRow?['cardhedge_id'] as String?)?.trim();

      if (linkedGuidePriceCardId != null && linkedGuidePriceCardId.isNotEmpty) {
        final prices = await getMasterCardCurrentPrices(masterId);
        final hasGuideCatalogPrices = prices.values.any((v) => v != null && v > 0);
        if (hasGuideCatalogPrices) {
          final rawAvg = prices['Raw'] ?? 0;
          final psa10Avg = prices['PSA 10'] ?? 0;
          final psa9Avg = prices['PSA 9'] ?? 0;
          await _writeUserCardValuesFromAverages(
            matchingRows: matchingRows,
            rawAvg: rawAvg,
            psa10Avg: psa10Avg,
            psa9Avg: psa9Avg,
          );
          continue;
        }
      }

      final hasFreshCachedComps = await _hasFreshCachedComps(masterId);
      if (!hasFreshCachedComps) {
        late final FunctionResponse res;
        try {
          res = await _supabase.functions.invoke(
            'refresh-comps',
            body: {'masterCardId': masterId},
          );
        } on FunctionException catch (e) {
          throw _friendlyRefreshException(status: e.status, source: e, payload: e.details);
        }
        if (res.status != 200) {
          throw _friendlyRefreshException(status: res.status, payload: res.data);
        }
      }

      // Re-read the same DB rows the UI uses so `current_value` and
      // displayed Sold Comps averages always stay in sync.
      final comps = await getMasterCardComps(masterId);
      if (comps.isEmpty) {
        for (final card in entry.value) {
          final id = card['id'] as String?;
          if (id == null) continue;
          await _supabase.from('user_cards').update({
            'current_value': null,
            'value_refreshed_at': DateTime.now().toIso8601String(),
          }).eq('id', id);
        }
        continue;
      }
      final rawAvg = _averageForGrade(comps, 'Raw');
      final psa10Avg = _averageForGrade(comps, 'PSA 10');
      final psa9Avg = _averageForGrade(comps, 'PSA 9');

      await _writeUserCardValuesFromAverages(
        matchingRows: matchingRows,
        rawAvg: rawAvg,
        psa10Avg: psa10Avg,
        psa9Avg: psa9Avg,
      );
    }
  }

  Future<List<LookupHistory>> getHistory() async {
    final data = await _supabase
        .from('lookup_history')
        .select()
        .order('timestamp', ascending: false)
        .limit(50);
    return (data as List).map((r) => LookupHistory.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// Lazily fetches a card image from the catalog API and caches it.
  /// Safe to call multiple times — returns immediately if already cached.
  Future<String?> fetchCardImage(String masterCardId) async {
    try {
      final res = await _supabase.functions.invoke(
        'fetch-card-image',
        body: {'masterCardId': masterCardId},
      );
      if (res.status != 200) return null;
      final data = _functionInvokeBodyAsMap(res.data);
      final rawUrl = data?['image_url'];
      if (rawUrl == null) return null;
      final s = rawUrl.toString().trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  /// Normalizes upstream `prices[]` entries (mixed key casing) for Edge insert into `current_prices`.
  static List<Map<String, dynamic>>? _normalizeGuidePricesForPersist(
    List<Map<String, dynamic>>? raw,
  ) {
    if (raw == null || raw.isEmpty) return null;
    double? parsePrice(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) {
        final cleaned = v.replaceAll(RegExp(r'[^0-9.-]'), '');
        if (cleaned.isEmpty) return null;
        return double.tryParse(cleaned);
      }
      return null;
    }

    final out = <Map<String, dynamic>>[];
    for (final row in raw) {
      final grade = (row['grade'] ?? row['Grade'] ?? row['label'] ?? row['Label'] ?? row['name'] ?? row['Name'])
          ?.toString()
          .trim();
      if (grade == null || grade.isEmpty) continue;
      final price = parsePrice(row['price'] ?? row['Price'] ?? row['value'] ?? row['Value'] ?? row['avg'] ?? row['Avg']);
      if (price == null || price <= 0) continue;
      out.add({'grade': grade, 'price': price});
    }
    return out.isEmpty ? null : out;
  }

  /// CardHedge visual similarity search (same photo as CardSight identify). Returns [] on failure.
  Future<List<CardHedgeImageSearchHit>> cardHedgeImageSearch({
    required String imageBase64Jpeg,
    int k = 12,
  }) async {
    try {
      final res = await _supabase.functions.invoke(
        'cardhedge-image-search',
        body: {'image_base64': imageBase64Jpeg, 'k': k},
      );
      if (res.status != 200) return const [];
      final map = _functionInvokeBodyAsMap(res.data);
      if (map == null) return const [];
      final hitsRaw = map['hits'];
      if (hitsRaw is! List) return const [];
      final out = <CardHedgeImageSearchHit>[];
      for (final e in hitsRaw) {
        if (e is! Map) continue;
        final h = CardHedgeImageSearchHit.fromJson(Map<String, dynamic>.from(e));
        if (h.cardId.isNotEmpty) out.add(h);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Links [guidePriceCardId] to the variant and hydrates prices/sales from CardHedge `card-details`.
  Future<MasterCard?> persistCardHedgeHydratedFromCardId({
    required String masterVariantId,
    required String guidePriceCardId,
  }) async {
    final tid = masterVariantId.trim();
    final gid = guidePriceCardId.trim();
    if (tid.isEmpty || gid.isEmpty) return null;
    try {
      final res = await _supabase.functions.invoke(
        'cardhedge-persist-variant',
        body: {
          'masterVariantId': tid,
          'guidePriceCardId': gid,
          'hydrateFromCardHedge': true,
        },
      );
      if (res.status != 200) return null;
      final map = _functionInvokeBodyAsMap(res.data);
      final pm = map?['persisted_master'];
      if (pm is! Map) return null;
      return MasterCard.fromJson(Map<String, dynamic>.from(pm));
    } catch (_) {
      return null;
    }
  }

  /// Persists a guide-price catalog match onto the variant via Edge `cardhedge-persist-variant`.
  /// Returns the updated row from the response (`persisted_master`), or null on failure.
  Future<MasterCard?> persistGuidePriceCatalogMatch({
    required String masterVariantId,
    required String? guidePriceCardId,
    required String? imageUrl,
    List<Map<String, dynamic>>? prices,
    int? sales7d,
    int? sales30d,
    double? gain,
  }) async {
    try {
      final normalizedPrices = _normalizeGuidePricesForPersist(prices);
      final res = await _supabase.functions.invoke(
        'cardhedge-persist-variant',
        body: {
          'masterVariantId': masterVariantId,
          if (guidePriceCardId != null && guidePriceCardId.isNotEmpty) 'guidePriceCardId': guidePriceCardId,
          if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
          if (normalizedPrices != null && normalizedPrices.isNotEmpty) 'prices': normalizedPrices,
          if (sales7d != null) 'sales7d': sales7d,
          if (sales30d != null) 'sales30d': sales30d,
          if (gain != null) 'gain': gain,
        },
      );
      if (res.status != 200) return null;
      final raw = res.data;
      if (raw is! Map) return null;
      final map = Map<String, dynamic>.from(raw);
      final pm = map['persisted_master'];
      if (pm is! Map) return null;
      return MasterCard.fromJson(Map<String, dynamic>.from(pm));
    } catch (_) {
      return null;
    }
  }

  /// POST sold-comps for [grade], upserts `comps_cache`, replaces
  /// `card_sold_comps` rows for that catalog variant + grade.
  Future<GuideGradeCompsResult?> fetchGuideGradeComps({
    required String masterVariantId,
    required String guidePriceCardId,
    required String grade,
    int count = 40,
  }) async {
    try {
      final res = await _supabase.functions.invoke(
        'cardhedge-grade-comps',
        body: {
          'masterVariantId': masterVariantId,
          'guidePriceCardId': guidePriceCardId,
          'grade': grade,
          'count': count,
        },
      );
      if (res.status != 200) return null;
      final raw = res.data;
      if (raw is! Map) return null;
      final map = Map<String, dynamic>.from(raw);
      if (map['ok'] != true) return null;
      final saleCount = (map['count'] as num?)?.toInt() ?? 0;
      final high = parsePostgresNumeric(map['high']);
      final low = parsePostgresNumeric(map['low']);
      final compPrice = parsePostgresNumeric(map['comp_price']);
      return GuideGradeCompsResult(
        saleCount: saleCount,
        high: high != null && high > 0 ? high : null,
        low: low != null && low > 0 ? low : null,
        compPrice: compPrice != null && compPrice > 0 ? compPrice : null,
      );
    } on FunctionException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Catalog card-search via Edge `cardhedge-search-cards`. CardHedge POST body:
  /// `category`, `page`, `page_size`, `search` where search =
  /// Player + Year + Release + #Number + Set. [setName] / [parallelName] filter after fetch.
  /// Trailing print-run suffixes on [parallelName] (e.g. ` /149`) are stripped in
  /// the client before the request, aligned with [stripSerialSuffix] on the edge.
  /// Edge scans multiple pages, then card # + insert + parallel scoring.
  ///
  /// When [persistMasterVariantId] is set and a match is found, the same request
  /// writes guide fields + `current_prices` and returns `persisted_master`.
  Future<GuideCatalogMatchPayload> searchGuidePriceCatalog({
    required String player,
    int? year,
    String? releaseName,
    String? setName,
    String? sport,
    String? category,
    String? cardNumber,
    String? parallelName,
    String? persistMasterVariantId,
    int pageSize = 100,
  }) async {
    final body = buildGuidePriceCatalogRequestBody(
      player: player,
      year: year,
      releaseName: releaseName,
      setName: setName,
      sport: sport,
      category: category,
      cardNumber: cardNumber,
      parallelName: parallelName,
      persistMasterVariantId: persistMasterVariantId,
      pageSize: pageSize,
    );
    _logGuidePriceCatalogRequest(body);

    try {
      final res = await _supabase.functions.invoke(
        'cardhedge-search-cards',
        body: body,
      );
      final raw = res.data;
      if (raw is Map) {
        final map = Map<String, dynamic>.from(raw);
        if (res.status == 200) {
          final payload = GuideCatalogMatchPayload.fromJson(map).withVaultRequestToEdge(body);
          _logGuidePriceCatalogCardhedgeRequest(payload.cardhedgeRequest);
          return payload;
        }
        final err = map['error']?.toString() ?? 'Request failed';
        final hint = map['hint']?.toString();
        final details = map['details']?.toString();
        final chr = map['cardhedge_request'];
        if (chr is Map) {
          _logGuidePriceCatalogCardhedgeRequest(Map<String, dynamic>.from(chr));
        }
        if (details != null && details.isNotEmpty) {
          final short = details.length > 200 ? '${details.substring(0, 200)}…' : details;
          return GuideCatalogMatchPayload.error(
            hint != null && hint.isNotEmpty ? '$err: $short\n$hint' : '$err: $short',
          ).withVaultRequestToEdge(body);
        }
        return GuideCatalogMatchPayload.error(
          hint != null && hint.isNotEmpty ? '$err\n$hint' : err,
        ).withVaultRequestToEdge(body);
      }
      return GuideCatalogMatchPayload.error('Catalog search: unexpected response (${res.status})');
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map) {
        final m = Map<String, dynamic>.from(details);
        final chr = m['cardhedge_request'];
        if (chr is Map) {
          _logGuidePriceCatalogCardhedgeRequest(Map<String, dynamic>.from(chr));
        }
        final err = m['error']?.toString() ?? 'Request failed';
        return GuideCatalogMatchPayload.error('$err (${e.status})').withVaultRequestToEdge(body);
      }
      return GuideCatalogMatchPayload.error('Catalog search failed (${e.status})')
          .withVaultRequestToEdge(body);
    } catch (e) {
      return GuideCatalogMatchPayload.error(e.toString()).withVaultRequestToEdge(body);
    }
  }
}

/// Body for `cardhedge-search-cards` (shared by [CompsService.searchGuidePriceCatalog]).
Map<String, dynamic> buildGuidePriceCatalogRequestBody({
  required String player,
  int? year,
  String? releaseName,
  String? setName,
  String? sport,
  String? category,
  String? cardNumber,
  String? parallelName,
  String? persistMasterVariantId,
  int pageSize = 100,
}) {
  final body = <String, dynamic>{
    'player': player.trim(),
    'page_size': pageSize.clamp(1, 100),
  };
  if (year != null) body['year'] = year;
  final r = releaseName?.trim();
  if (r != null && r.isNotEmpty) body['releaseName'] = r;
  final s = setName?.trim();
  if (s != null && s.isNotEmpty) body['setName'] = s;
  final sp = sport?.trim();
  if (sp != null && sp.isNotEmpty) body['sport'] = sp;
  final c = category?.trim();
  if (c != null && c.isNotEmpty) body['category'] = c;
  final cn = cardNumber?.trim();
  if (cn != null && cn.isNotEmpty) body['cardNumber'] = cn;
  final pRaw = parallelName?.trim();
  if (pRaw != null && pRaw.isNotEmpty) {
    final p = stripCatalogParallelSerialSuffix(pRaw);
    if (p.isNotEmpty) body['parallelName'] = p;
  }
  final pid = persistMasterVariantId?.trim();
  if (pid != null && pid.isNotEmpty) body['persistMasterVariantId'] = pid;
  return body;
}

void _logGuidePriceCatalogRequest(Map<String, dynamic> vaultToEdge) {
  if (!kDebugMode) return;
  debugPrint(
    '[cardhedge-search] vault→edge:\n${const JsonEncoder.withIndent('  ').convert(vaultToEdge)}',
  );
}

void _logGuidePriceCatalogCardhedgeRequest(Map<String, dynamic>? cardhedgeRequest) {
  if (!kDebugMode || cardhedgeRequest == null) return;
  debugPrint(
    '[cardhedge-search] CardHedge API (from edge):\n'
    '${const JsonEncoder.withIndent('  ').convert(cardhedgeRequest)}',
  );
}

/// Key for [soldCompsExistForGradeProvider].
class SoldCompsGradeKey {
  const SoldCompsGradeKey({required this.masterCardId, required this.grade});
  final String masterCardId;
  final String grade;

  @override
  bool operator ==(Object other) =>
      other is SoldCompsGradeKey && other.masterCardId == masterCardId && other.grade == grade;

  @override
  int get hashCode => Object.hash(masterCardId, grade);
}

/// Whether `card_sold_comps` has rows for this master + grade (catalog browse UI).
final soldCompsExistForGradeProvider = FutureProvider.family<bool, SoldCompsGradeKey>((ref, key) async {
  return ref.watch(compsServiceProvider).hasSoldCompsForGrade(key.masterCardId, key.grade);
});

final compsServiceProvider = Provider<CompsService>((ref) {
  return CompsService(ref.watch(supabaseProvider));
});

final lookupHistoryProvider = FutureProvider<List<LookupHistory>>((ref) async {
  return ref.watch(compsServiceProvider).getHistory();
});
