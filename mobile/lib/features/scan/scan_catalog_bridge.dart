import '../../core/models/cardhedge_image_search.dart';
import '../../core/services/cards_service.dart';
import 'scan_models.dart';

String _normKey(String? s) {
  if (s == null) return '';
  return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

bool _numbersRoughMatch(String? a, String? b) {
  if (a == null || b == null) return false;
  final na = a.replaceFirst(RegExp(r'^#'), '').trim().toLowerCase();
  final nb = b.replaceFirst(RegExp(r'^#'), '').trim().toLowerCase();
  if (na.isEmpty || nb.isEmpty) return false;
  if (na == nb) return true;
  final ia = int.tryParse(na);
  final ib = int.tryParse(nb);
  if (ia != null && ib != null && ia == ib) return true;
  return false;
}

double _scorePair(ImageScanMatchResult d, CardHedgeImageSearchHit h) {
  var score = 0.0;
  score += h.similarityScore * 4;
  final dp = (d.card.name ?? '').toLowerCase().trim();
  final hp = (h.player ?? '').toLowerCase().trim();
  if (dp.isNotEmpty && hp.isNotEmpty) {
    if (hp.contains(dp) || dp.contains(hp)) {
      score += 8;
    } else {
      final dTok = dp.split(RegExp(r'\s+')).where((e) => e.length > 2).toSet();
      final hTok = hp.split(RegExp(r'\s+')).where((e) => e.length > 2).toSet();
      if (dTok.intersection(hTok).isNotEmpty) score += 5;
    }
  }
  if (_numbersRoughMatch(d.card.number, h.number)) score += 10;
  return score;
}

/// Merges CardHedge image-search hits onto CardSight detections (best-effort pairing).
List<ImageScanMatchResult> mergeCardHedgeImageSearchIntoDetections(
  List<ImageScanMatchResult> detections,
  List<CardHedgeImageSearchHit> hits,
) {
  if (hits.isEmpty || detections.isEmpty) return detections;
  final sorted = [...hits]..sort((a, b) => b.similarityScore.compareTo(a.similarityScore));
  final used = <int>{};
  final out = <ImageScanMatchResult>[];

  for (final d in detections) {
    var bestI = -1;
    var bestScore = -1.0;
    for (var i = 0; i < sorted.length; i++) {
      if (used.contains(i)) continue;
      final s = _scorePair(d, sorted[i]);
      if (s > bestScore) {
        bestScore = s;
        bestI = i;
      }
    }
    const minAccept = 6.0;
    if (bestI >= 0 && bestScore >= minAccept) {
      used.add(bestI);
      final h = sorted[bestI];
      var card = d.card;
      if (card.parallel == null &&
          h.variant != null &&
          h.variant!.trim().isNotEmpty) {
        card = card.copyWith(
          parallel: ParallelInfo(
            id: '',
            name: h.variant!.trim(),
            numberedTo: null,
          ),
        );
      }
      out.add(
        d.copyWith(
          card: card,
          cardHedgeCardId: h.cardId,
          cardHedgeVariant: h.variant,
          cardHedgeSetLabel: h.setLabel,
          cardHedgeImageSimilarity: h.similarityScore,
          clearCardHedge: false,
        ),
      );
    } else {
      out.add(d);
    }
  }
  return out;
}

/// Picks a DB [SetParallel] from scan + CardHedge hints. Never returns a synthetic id.
SetParallel? pickCatalogParallel({
  required List<SetParallel> parallels,
  ParallelInfo? scanParallel,
  String? cardHedgeVariant,
}) {
  if (parallels.isEmpty) return null;

  SetParallel? matchByName(String rawName) {
    final target = _normKey(rawName);
    if (target.isEmpty) return null;
    for (final p in parallels) {
      final c = _normKey(p.name);
      if (c == target || c.contains(target) || target.contains(c)) return p;
    }
    return null;
  }

  if (scanParallel != null && scanParallel.name.isNotEmpty) {
    final m = matchByName(scanParallel.name);
    if (m != null) {
      if (m.serialMax == null && scanParallel.numberedTo != null) {
        return SetParallel(
          id: m.id,
          name: m.name,
          serialMax: scanParallel.numberedTo,
          isAuto: m.isAuto,
        );
      }
      return m;
    }
  }
  if (cardHedgeVariant != null && cardHedgeVariant.trim().isNotEmpty) {
    final m = matchByName(cardHedgeVariant);
    if (m != null) return m;
  }
  return null;
}

String catalogParallelDisplayLabel({
  required SetParallel? resolved,
  ParallelInfo? scanParallel,
  String? cardHedgeVariant,
}) {
  if (resolved != null) return resolved.name;
  if (scanParallel != null && scanParallel.name.isNotEmpty) return scanParallel.name;
  final v = cardHedgeVariant?.trim();
  if (v != null && v.isNotEmpty) return v;
  return 'Base';
}
