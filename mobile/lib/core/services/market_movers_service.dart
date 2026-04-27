import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';
import '../models/market_mover.dart';

int _tryParseInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? 0;
  if (value is num) return value.toInt();
  return 0;
}

class MarketMoversService {
  MarketMoversService(this._supabase);
  final SupabaseClient _supabase;

  Future<MarketMoversData> getMovers({String? sport, int days = 7}) async {
    // Fetch snapshots for the requested period + extra for previous week
    final now = DateTime.now();
    final sinceDate = now.subtract(Duration(days: days + 7));
    final sinceDateStr = sinceDate.toIso8601String().split('T')[0];

    final data = await _supabase
        .from('market_movers_snapshots')
        .select('''
          top_player_id, avg_price, comp_count, snapshot_week,
          top_players!inner(id, name, sport)
        ''')
        .gte('snapshot_week', sinceDateStr)
        .order('snapshot_week', ascending: false);

    final rows = data as List<dynamic>? ?? [];

    // Group by top_player_id, collecting snapshots per player
    final playerSnapshots = <String, List<_Snapshot>>{};

    for (final row in rows) {
      final topPlayerId = row['top_player_id'] as String;
      final avgPrice = double.parse((row['avg_price'] ?? 0).toString());
      final compCount = _tryParseInt(row['comp_count']);
      final snapshotWeek = row['snapshot_week'] as String;
      final playerData = row['top_players'] as Map<String, dynamic>;
      final playerName = playerData['name'] as String;
      final playerSport = playerData['sport'] as String;

      // Filter by sport if provided
      if (sport != null && playerSport != sport) continue;

      playerSnapshots.putIfAbsent(topPlayerId, () => []).add(
        _Snapshot(
          playerName: playerName,
          playerSport: playerSport,
          avgPrice: avgPrice,
          compCount: compCount,
          snapshotWeek: DateTime.parse(snapshotWeek),
        ),
      );
    }

    // For each player, compute change between oldest and newest snapshot in period
    final movers = <MarketMover>[];

    for (final entry in playerSnapshots.entries) {
      final topPlayerId = entry.key;
      final snapshots = entry.value;

      if (snapshots.length < 2) continue; // Need at least 2 snapshots to compute change

      // Sort by date ascending (oldest first)
      snapshots.sort((a, b) => a.snapshotWeek.compareTo(b.snapshotWeek));

      // Get within the requested period window
      final cutoff = now.subtract(Duration(days: days));
      final inPeriod =
          snapshots.where((s) => s.snapshotWeek.isAfter(cutoff)).toList();

      if (inPeriod.length < 2) continue; // Need 2 in the period

      inPeriod.sort((a, b) => a.snapshotWeek.compareTo(b.snapshotWeek));

      final oldest = inPeriod.first;
      final newest = inPeriod.last;

      final priceChange = newest.avgPrice - oldest.avgPrice;
      final priceChangePct =
          oldest.avgPrice > 0 ? (priceChange / oldest.avgPrice) * 100 : 0;

      final volumeChange = newest.compCount - oldest.compCount;
      final volumeChangePct =
          oldest.compCount > 0 ? (volumeChange / oldest.compCount) * 100 : 0;

      movers.add(
        MarketMover(
          topPlayerId: topPlayerId,
          playerName: newest.playerName,
          sport: newest.playerSport,
          currentAvg: newest.avgPrice,
          previousAvg: oldest.avgPrice,
          currentVolume: newest.compCount,
          previousVolume: oldest.compCount,
          priceChangePct: priceChangePct.toDouble(),
          volumeChangePct: volumeChangePct.toDouble(),
        ),
      );
    }

    // Split into hot (price up) and cold (price down), top 20 each
    final hot = movers
        .where((m) => m.priceChangePct > 0)
        .toList()
        ..sort((a, b) => b.priceChangePct.compareTo(a.priceChangePct));

    final cold = movers
        .where((m) => m.priceChangePct <= 0)
        .toList()
        ..sort((a, b) => a.priceChangePct.compareTo(b.priceChangePct));

    return MarketMoversData(
      hot: hot.take(20).toList(),
      cold: cold.take(20).toList(),
      lastUpdated: DateTime.now(),
    );
  }
}

class _Snapshot {
  final String playerName;
  final String playerSport;
  final double avgPrice;
  final int compCount;
  final DateTime snapshotWeek;

  _Snapshot({
    required this.playerName,
    required this.playerSport,
    required this.avgPrice,
    required this.compCount,
    required this.snapshotWeek,
  });
}

final marketMoversServiceProvider = Provider<MarketMoversService>((ref) {
  return MarketMoversService(ref.watch(supabaseProvider));
});

final marketMoversProvider =
    FutureProvider.family<MarketMoversData, String?>((ref, sport) async {
  return ref.watch(marketMoversServiceProvider).getMovers(sport: sport);
});
