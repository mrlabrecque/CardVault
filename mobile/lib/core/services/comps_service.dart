import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';
import '../models/comp.dart';

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
    final lower = _extractErrorMessage(payload).toLowerCase();
    if (status == 404) {
      return Exception(
        'Price refresh service is not deployed. Run: supabase functions deploy refresh-comps',
      );
    }
    if (lower.contains('rapidapi') ||
        lower.contains('scrapegraphai') ||
        lower.contains('scrapingbee') ||
        lower.contains('forbidden')) {
      return Exception(
        'Pricing provider rejected this request. Please verify your pricing API credentials in Supabase secrets, then try again.',
      );
    }
    if (status == 502 || status == 503 || status == 504) {
      return Exception(
        'Pricing service is temporarily unavailable (${status ?? 'upstream error'}). Please try again in a minute.',
      );
    }
    if (source != null) {
      return Exception('Refresh comps failed: $source');
    }
    return Exception(
      'Refresh comps failed'
      '${status != null ? ' ($status)' : ''}'
      '${lower.isNotEmpty ? ': ${_extractErrorMessage(payload)}' : ''}',
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
    // Resolve master_card_id + parallel_name from user_card, then fetch comps
    final cardData = await _supabase
        .from('user_cards')
        .select('master_card_id, parallel_name')
        .eq('id', cardId)
        .single();

    final masterId = (cardData as Map)['master_card_id'] as String?;
    final parallelName = ((cardData as Map)['parallel_name'] as String?) ?? 'Base';

    if (masterId == null) {
      return [];
    }

    return getMasterCardComps(masterId, parallelName);
  }

  Future<List<Comp>> getMasterCardComps(String masterCardId, String parallelName) async {
    final data = await _supabase
        .from('card_sold_comps')
        .select('title, price, currency, sale_type, sold_at, url, image_url, grade')
        .eq('master_card_id', masterCardId)
        .eq('parallel_name', parallelName)
        .order('sold_at', ascending: false, nullsFirst: false);
    return (data as List).map((r) => Comp.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<List<ActiveListing>> getActiveListings(String masterCardId, String parallelName) async {
    try {
      final res = await _supabase.functions.invoke(
        'card-active-listings',
        body: {'masterCardId': masterCardId, 'parallelName': parallelName},
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

  Future<void> refreshMasterCardComps(String masterCardId, String parallelName) async {
    try {
      final res = await _supabase.functions.invoke(
        'refresh-comps',
        body: {'masterCardId': masterCardId, 'parallelName': parallelName},
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

  Future<bool> _hasFreshCachedComps(String masterCardId, String parallelName) async {
    final cutoff = DateTime.now().subtract(_compsRefreshCooldown).toIso8601String();
    final rows = await _supabase
        .from('card_sold_comps')
        .select('id')
        .eq('master_card_id', masterCardId)
        .eq('parallel_name', parallelName)
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
          .select('id, master_card_id, parallel_name, is_graded, grade_value')
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
      final parallelName = (row['parallel_name'] as String?) ?? 'Base';
      final key = '$masterId|$parallelName';
      byCompsKey.putIfAbsent(key, () => []).add(row);
    }
    if (byCompsKey.isEmpty) {
      throw Exception('This card is missing catalog data and cannot be refreshed yet.');
    }

    for (final entry in byCompsKey.entries) {
      final first = entry.value.first;
      final masterId = first['master_card_id'] as String;
      final parallelName = (first['parallel_name'] as String?) ?? 'Base';

      final hasFreshCachedComps = await _hasFreshCachedComps(masterId, parallelName);
      if (!hasFreshCachedComps) {
        late final FunctionResponse res;
        try {
          res = await _supabase.functions.invoke(
            'refresh-comps',
            body: {'masterCardId': masterId, 'parallelName': parallelName},
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
      final comps = await getMasterCardComps(masterId, parallelName);
      final rawAvg = _averageForGrade(comps, 'Raw');
      final psa10Avg = _averageForGrade(comps, 'PSA 10');
      final psa9Avg = _averageForGrade(comps, 'PSA 9');
      final refreshedAt = DateTime.now().toIso8601String();

      for (final card in entry.value) {
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
  }

  Future<List<LookupHistory>> getHistory() async {
    final data = await _supabase
        .from('lookup_history')
        .select()
        .order('timestamp', ascending: false)
        .limit(50);
    return (data as List).map((r) => LookupHistory.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// Lazily fetches a card image from CardSight and caches it.
  /// Safe to call multiple times — returns immediately if already cached.
  Future<String?> fetchCardImage(String masterCardId) async {
    try {
      final res = await _supabase.functions.invoke(
        'fetch-card-image',
        body: {'masterCardId': masterCardId},
      );
      if (res.status == 200) {
        final data = res.data as Map<String, dynamic>?;
        return data?['image_url'] as String?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

final compsServiceProvider = Provider<CompsService>((ref) {
  return CompsService(ref.watch(supabaseProvider));
});

final lookupHistoryProvider = FutureProvider<List<LookupHistory>>((ref) async {
  return ref.watch(compsServiceProvider).getHistory();
});
