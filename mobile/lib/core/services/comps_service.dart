import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';
import '../models/comp.dart';

const _backendUrl = String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:3000');

class CompsService {
  CompsService(this._supabase);
  final SupabaseClient _supabase;

  Future<List<Comp>> search(String query) async {
    final session = _supabase.auth.currentSession;
    final res = await http.post(
      Uri.parse('$_backendUrl/api/comps/search'),
      headers: {
        'Content-Type': 'application/json',
        if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
      },
      body: jsonEncode({'query': query}),
    );
    if (res.statusCode != 200) throw Exception('Search failed: ${res.statusCode}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final items = data['results'] as List? ?? data['items'] as List? ?? [];
    return items.map((r) => Comp.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<List<Comp>> getCardComps(String cardId) async {
    final data = await _supabase
        .from('card_sold_comps')
        .select('title, price, currency, sale_type, sold_at, url')
        .eq('user_card_id', cardId)
        .order('sold_at', ascending: false, nullsFirst: false);
    return (data as List).map((r) => Comp.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<void> refreshCardValue(String cardId) async {
    await _supabase.functions.invoke(
      'refresh-card-value',
      body: {'cardId': cardId},
    );
  }

  Future<List<LookupHistory>> getHistory() async {
    final data = await _supabase
        .from('lookup_history')
        .select()
        .order('timestamp', ascending: false)
        .limit(50);
    return (data as List).map((r) => LookupHistory.fromJson(r as Map<String, dynamic>)).toList();
  }
}

final compsServiceProvider = Provider<CompsService>((ref) {
  return CompsService(ref.watch(supabaseProvider));
});

final lookupHistoryProvider = FutureProvider<List<LookupHistory>>((ref) async {
  return ref.watch(compsServiceProvider).getHistory();
});
