import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';
import '../models/portfolio_mover.dart';

class PortfolioMoversService {
  PortfolioMoversService(this._supabase);
  final SupabaseClient _supabase;

  /// RPC aggregates all users’ [user_cards] (current vs previous value after comps refresh).
  Future<PortfolioMoversData> getPortfolioMovers({String? sport}) async {
    final rows = await _supabase.rpc(
      'portfolio_movers_from_vault',
      params: sport != null ? {'p_sport': sport} : const <String, dynamic>{},
    );

    final list = rows as List<dynamic>? ?? [];
    final movers = <PortfolioMover>[];

    for (final row in list) {
      final map = row as Map<String, dynamic>;
      final name = map['player_name'] as String? ?? '';
      if (name.isEmpty) continue;

      final spr = (map['sport'] as String? ?? '').trim();
      if (spr.isEmpty) continue;

      final key = map['player_key'] as String? ?? '$name|$spr';
      final rawPct = map['price_change_pct'];
      final priceChangePct = (rawPct is num) ? rawPct.toDouble() : double.tryParse('$rawPct') ?? 0;
      final cur = map['avg_current'];
      final prev = map['avg_previous'];
      final currentAvg = (cur is num) ? cur.toDouble() : double.tryParse('$cur') ?? 0;
      final previousAvg = (prev is num) ? prev.toDouble() : double.tryParse('$prev') ?? 0;
      final n = map['card_count'];
      final cardCount = (n is num) ? n.toInt() : int.tryParse('$n') ?? 0;

      movers.add(
        PortfolioMover(
          topPlayerId: key,
          playerName: name,
          sport: spr,
          currentAvg: currentAvg,
          previousAvg: previousAvg,
          currentVolume: cardCount,
          previousVolume: cardCount,
          priceChangePct: priceChangePct,
          volumeChangePct: 0,
        ),
      );
    }

    const maxSlots = 20;
    const maxPerSportAll = 5;

    final hotSorted = movers.where((m) => m.priceChangePct > 0).toList()
      ..sort((a, b) => b.priceChangePct.compareTo(a.priceChangePct));

    final coldSorted = movers.where((m) => m.priceChangePct <= 0).toList()
      ..sort((a, b) => a.priceChangePct.compareTo(b.priceChangePct));

    final hot = sport == null
        ? _fairQuotaTake(hotSorted, maxSlots, maxPerSportAll)
        : hotSorted.take(maxSlots).toList();

    final cold = sport == null
        ? _fairQuotaTake(coldSorted, maxSlots, maxPerSportAll)
        : coldSorted.take(maxSlots).toList();

    return PortfolioMoversData(
      hot: hot,
      cold: cold,
      lastUpdated: DateTime.now(),
    );
  }
}

List<PortfolioMover> _fairQuotaTake(
  List<PortfolioMover> sorted,
  int maxTotal,
  int maxPerSport,
) {
  final counts = <String, int>{};
  final out = <PortfolioMover>[];
  for (final m in sorted) {
    final key = m.sport;
    final n = counts[key] ?? 0;
    if (n >= maxPerSport) continue;
    counts[key] = n + 1;
    out.add(m);
    if (out.length >= maxTotal) break;
  }
  return out;
}

final portfolioMoversServiceProvider = Provider<PortfolioMoversService>((ref) {
  return PortfolioMoversService(ref.watch(supabaseProvider));
});

/// [sport] null = all sports.
final portfolioMoversProvider =
    FutureProvider.family<PortfolioMoversData, String?>((ref, sport) async {
  return ref.watch(portfolioMoversServiceProvider).getPortfolioMovers(sport: sport);
});
