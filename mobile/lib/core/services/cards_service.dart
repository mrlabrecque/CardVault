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
  const ReleaseRecord({required this.id, required this.name, this.year, this.sport});
  final String id;
  final String name;
  final int? year;
  final String? sport;

  factory ReleaseRecord.fromJson(Map<String, dynamic> j) => ReleaseRecord(
    id: j['id'] as String,
    name: j['name'] as String,
    year: j['year'] as int?,
    sport: j['sport'] as String?,
  );

  String get displayName => year != null ? '$year $name' : name;
}

class SetRecord {
  const SetRecord({required this.id, required this.name, this.cardCount});
  final String id;
  final String name;
  final int? cardCount;

  factory SetRecord.fromJson(Map<String, dynamic> j) => SetRecord(
    id: j['id'] as String,
    name: j['name'] as String,
    cardCount: j['card_count'] as int?,
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

  Future<List<ReleaseRecord>> searchReleases(String query) async {
    var q = _supabase.from('releases').select('id, name, year, sport');
    if (query.trim().isNotEmpty) {
      q = q.ilike('name', '%${query.trim()}%');
    }
    final data = await q.order('year', ascending: false).limit(30);
    return (data as List).map((r) => ReleaseRecord.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<List<SetRecord>> getSetsForRelease(String releaseId) async {
    final data = await _supabase
        .from('sets')
        .select('id, name, card_count')
        .eq('release_id', releaseId)
        .order('name');
    return (data as List).map((r) => SetRecord.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<List<MasterCard>> searchMasterCards(String setId, String query) async {
    var q = _supabase
        .from('master_card_definitions')
        .select('id, player, card_number, is_rookie, is_auto, is_patch, is_ssp, serial_max, image_url')
        .eq('set_id', setId);
    if (query.trim().isNotEmpty) {
      q = q.ilike('player', '%${query.trim()}%');
    }
    final data = await q.order('player').limit(50);
    return (data as List).map((r) => MasterCard.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<void> addCard(AddCardFormData form) async {
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

    await _supabase.from('user_cards').insert({
      'master_card_id': masterCardId,
      'user_id': userId,
      'parallel_id': form.parallelId,
      'parallel_name': form.parallelName,
      'price_paid': form.pricePaid,
      'serial_number': form.serialNumber?.isNotEmpty == true ? form.serialNumber : null,
      'is_graded': form.isGraded,
      'grader': form.isGraded ? form.grader : null,
      'grade_value': form.isGraded && form.gradeValue?.isNotEmpty == true ? form.gradeValue : null,
    });
  }
}

final cardsServiceProvider = Provider<CardsService>((ref) {
  return CardsService(ref.watch(supabaseProvider));
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

final cardStacksProvider = Provider<AsyncValue<List<CardStack>>>((ref) {
  return ref.watch(userCardsProvider).whenData(CardStack.fromCards);
});
