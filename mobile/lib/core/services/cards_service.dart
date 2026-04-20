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

class CardsService {
  CardsService(this._supabase);
  final SupabaseClient _supabase;

  Future<List<UserCard>> loadUserCards() async {
    final data = await _supabase.from('user_cards').select('''
      id, master_card_id, parallel_id, parallel_name,
      price_paid, current_value, serial_number,
      is_graded, grader, grade_value, created_at,
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
}

final cardsServiceProvider = Provider<CardsService>((ref) {
  return CardsService(ref.watch(supabaseProvider));
});

final parallelsProvider = FutureProvider.family<List<SetParallel>, String>((ref, setId) async {
  return ref.watch(cardsServiceProvider).getParallels(setId);
});

final userCardsProvider = FutureProvider<List<UserCard>>((ref) async {
  return ref.watch(cardsServiceProvider).loadUserCards();
});

final cardStacksProvider = Provider<AsyncValue<List<CardStack>>>((ref) {
  return ref.watch(userCardsProvider).whenData(CardStack.fromCards);
});
