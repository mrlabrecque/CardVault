import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';
import '../models/comp.dart';

class CompsService {
  CompsService(this._supabase);
  final SupabaseClient _supabase;

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
        .select('title, price, currency, sale_type, sold_at, url, grade')
        .eq('master_card_id', masterCardId)
        .eq('parallel_name', parallelName)
        .order('sold_at', ascending: false, nullsFirst: false);
    return (data as List).map((r) => Comp.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<void> refreshMasterCardComps(String masterCardId, String parallelName) async {
    final res = await _supabase.functions.invoke(
      'get-card-comps',
      body: {'masterCardId': masterCardId, 'parallelName': parallelName},
    );
    if (res.status != 200) {
      final error = (res.data as Map<String, dynamic>?)?['error'] ?? 'Unknown error';
      throw Exception('Refresh comps failed: $error');
    }
  }

  Future<void> refreshCardValue(String cardId) async {
    final res = await _supabase.functions.invoke(
      'refresh-card-value',
      body: {'cardId': cardId},
    );
    if (res.status != 200) {
      final error = (res.data as Map<String, dynamic>?)?['error'] ?? 'Unknown error';
      throw Exception('Refresh value failed: $error (${res.status})');
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
