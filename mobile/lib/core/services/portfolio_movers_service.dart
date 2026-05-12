import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_service.dart';
import '../models/portfolio_mover.dart';
import '../utils/cardhedge_grade_prices.dart';
import '../utils/cardhedge_match_query.dart';

class PortfolioMoversService {
  PortfolioMoversService(this._supabase);
  final SupabaseClient _supabase;

  /// All vault rows from `portfolio_movers_from_vault` (no sport param); filter client-side.
  Future<List<PortfolioMover>> fetchVaultPortfolioMoversRaw() async {
    final rows = await _supabase.rpc(
      'portfolio_movers_from_vault',
      params: const <String, dynamic>{},
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

    return movers;
  }

  /// One CardHedge top-movers fetch (no `category`); client filters by sport without re-calling.
  Future<List<PortfolioMover>> fetchTopMoversRaw() async {
    late final FunctionResponse res;
    try {
      res = await _supabase.functions.invoke(
        'cardhedge-top-movers',
        body: <String, dynamic>{'count': 100},
      );
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map) {
        final m = Map<String, dynamic>.from(details);
        final err = m['error']?.toString() ?? 'Request failed';
        final d = m['details']?.toString();
        throw Exception(
          d != null && d.isNotEmpty ? '$err (${e.status}): ${d.length > 160 ? '${d.substring(0, 160)}…' : d}' : '$err (${e.status})',
        );
      }
      throw Exception('Portfolio movers failed (${e.status})');
    }

    final raw = res.data;
    if (raw is! Map) {
      throw Exception('Unexpected response (${res.status})');
    }
    final map = Map<String, dynamic>.from(raw);
    if (res.status != 200) {
      final err = map['error']?.toString() ?? 'Request failed';
      final details = map['details']?.toString();
      throw Exception(
        details != null && details.isNotEmpty
            ? '$err: ${details.length > 160 ? '${details.substring(0, 160)}…' : details}'
            : err,
      );
    }

    final cardsRaw = map['cards'];
    if (cardsRaw is! List) {
      return const [];
    }

    final movers = <PortfolioMover>[];
    for (final item in cardsRaw) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);
      final player = (row['player'] as String?)?.trim() ?? '';
      if (player.isEmpty) continue;

      final sprRaw = (row['category'] as String? ?? '').trim();
      final spr = canonicalCardHedgeMoverCategory(sprRaw);
      if (spr == null) continue;

      final cardId = (row['card_id'] as String?)?.trim() ?? '';
      final key = cardId.isNotEmpty ? cardId : '$player|$spr';

      final gainRaw = row['gain'];
      final gain = (gainRaw is num) ? gainRaw.toDouble() : double.tryParse('$gainRaw') ?? 0;

      final headline = _headlinePriceFromCardHedgePrices(row['prices']);
      if (headline == null || headline <= 0) continue;

      final prev = gain > -99.9 ? headline / (1 + gain / 100.0) : headline;

      final sales30 = row['30 Day Sales'];
      final sales7 = row['7 Day Sales'];
      int vol = 0;
      if (sales30 is num) {
        vol = sales30.toInt();
      } else if (sales7 is num) {
        vol = sales7.toInt();
      }

      movers.add(
        PortfolioMover(
          topPlayerId: key,
          playerName: player,
          sport: spr,
          cardDescription: _buildTopMoverDescription(row),
          currentAvg: headline,
          previousAvg: prev,
          currentVolume: vol,
          previousVolume: vol,
          priceChangePct: gain,
          volumeChangePct: 0,
        ),
      );
    }

    movers.sort((a, b) => b.priceChangePct.compareTo(a.priceChangePct));
    return movers;
  }
}

/// Rising / cooling lists from vault RPC data; [sport] filters client-side only.
PortfolioMoversData vaultMoversForDisplay(List<PortfolioMover> raw, String? sport) {
  var pool = raw;
  if (sport != null) {
    pool = raw.where((m) => m.sport == sport).toList();
  }

  const maxSlots = 20;
  const maxPerSportAll = 5;

  final hotSorted = pool.where((m) => m.priceChangePct > 0).toList()
    ..sort((a, b) => b.priceChangePct.compareTo(a.priceChangePct));

  final coldSorted = pool.where((m) => m.priceChangePct <= 0).toList()
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

/// CardHedge top movers: applies app-bar sport chip without network I/O.
List<PortfolioMover> marketTopMoversForDisplay(List<PortfolioMover> rawSortedDesc, String? uiSportFilter) {
  const maxSlots = 20;
  const maxPerSportAll = 5;
  final category = cardHedgeCategoryForMoversFilter(uiSportFilter);
  if (category == null) {
    return _fairQuotaTake(rawSortedDesc, maxSlots, maxPerSportAll);
  }
  return rawSortedDesc.where((m) => m.sport == category).take(maxSlots).toList();
}

String? _buildTopMoverDescription(Map<String, dynamic> row) {
  final num = (row['number']?.toString() ?? '').trim();
  final variant = (row['variant']?.toString() ?? '').trim();
  final setName = (row['set']?.toString() ?? '').trim();

  final bits = <String>[];
  if (num.isNotEmpty) bits.add('#$num');
  if (variant.isNotEmpty && variant.toLowerCase() != 'base') bits.add(variant);
  if (setName.isNotEmpty) bits.add(setName);

  if (bits.isEmpty) return null;
  var s = bits.join(' · ');
  if (s.length > 96) s = '${s.substring(0, 93)}…';
  return s;
}

double? _headlinePriceFromCardHedgePrices(dynamic raw) {
  if (raw is! List || raw.isEmpty) return null;
  final rows = <Map<String, dynamic>>[];
  for (final p in raw) {
    if (p is Map) rows.add(Map<String, dynamic>.from(p));
  }
  if (rows.isEmpty) return null;

  for (final m in rows) {
    final g = (m['grade'] ?? m['Grade'] ?? '').toString().trim();
    if (g == 'PSA 10') {
      final v = parseCardHedgePriceField(m['price'] ?? m['Price']);
      if (v != null && v > 0) return v;
    }
  }
  for (final m in rows) {
    final g = (m['grade'] ?? m['Grade'] ?? '').toString().trim().toLowerCase();
    if (g == 'raw') {
      final v = parseCardHedgePriceField(m['price'] ?? m['Price']);
      if (v != null && v > 0) return v;
    }
  }
  for (final m in rows) {
    final v = parseCardHedgePriceField(m['price'] ?? m['Price']);
    if (v != null && v > 0) return v;
  }
  return null;
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

final vaultPortfolioMoversRawProvider = FutureProvider<List<PortfolioMover>>((ref) async {
  return ref.watch(portfolioMoversServiceProvider).fetchVaultPortfolioMoversRaw();
});

final marketTopMoversRawProvider = FutureProvider<List<PortfolioMover>>((ref) async {
  return ref.watch(portfolioMoversServiceProvider).fetchTopMoversRaw();
});
