import '../models/guide_catalog_match.dart';
import 'guide_grade_prices.dart';

/// Trailing print-run suffix on parallel labels (e.g. `Red /149` → `Red`).
/// Matches edge `stripSerialSuffix` (shared catalog text helpers).
String stripCatalogParallelSerialSuffix(String raw) {
  return raw.replaceAll(RegExp(r'\s*/\d+$'), '').trim();
}

/// Normalized parallel label for comparing Vault [set_parallels] to CardHedge `variant`.
String normGuideParallelLabel(String raw) {
  return stripCatalogParallelSerialSuffix(raw)
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');
}

/// Whether the catalog parallel is treated as Base (looser CardHedge exact-match bucket).
bool guideCatalogParallelImpliesBase(String parallelName) {
  final n = normGuideParallelLabel(parallelName);
  return n.isEmpty ||
      n == 'base' ||
      n == 'base set' ||
      n == 'base parallel' ||
      n == 'base card' ||
      n == 'baseset' ||
      n == 'baseparallel';
}

final RegExp _baseVariantPenaltyRe = RegExp(
  r'\b(silver|gold|red|blue|green|purple|orange|pink|black|prizm|refractor|holo|mojo|wave|scope|velocity|shimmer|sparkle|ice|lazer|laser|disco|hyper|genesis|auto|patch|rc|rookie|ssp|numbered|/\d+)\b',
  caseSensitive: false,
);

/// All CardHedge rows from a catalog search payload (primary + alternates).
List<GuideCatalogMatchedRow> guideCatalogMatchCandidates(GuideCatalogMatchPayload payload) {
  final out = <GuideCatalogMatchedRow>[];
  final m = payload.match;
  if (m != null) out.add(m);
  final seen = <String?>{m?.cardId};
  for (final a in payload.alternateMatches ?? const <GuideCatalogMatchedRow>[]) {
    if (a.cardId != null && seen.contains(a.cardId)) continue;
    seen.add(a.cardId);
    out.add(a);
  }
  return out;
}

int _baseVariantPickScore(GuideCatalogMatchedRow row, {String? setName}) {
  final v = normGuideParallelLabel(row.variant ?? '');
  var score = 0;
  if (v.isEmpty || v == 'base' || v == 'base set') {
    score += 120;
  } else if (v == 'base card' || v == 'base parallel') {
    score += 100;
  } else if (v.contains('base') && !_baseVariantPenaltyRe.hasMatch(v)) {
    score += 55;
  } else {
    score += 8;
  }

  final desc = (row.description ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final set = (setName ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (set.isNotEmpty && set != 'base' && set != 'base set') {
    if (desc.contains(set)) score += 45;
    final tokens = set.split(' ').where((t) => t.length > 2).toList();
    if (tokens.isNotEmpty) {
      var hits = 0;
      for (final t in tokens) {
        if (desc.contains(t)) hits++;
      }
      score += ((hits / tokens.length) * 30).round();
    }
  }

  final prices = row.prices;
  if (prices != null && prices.isNotEmpty) score += 20;

  return score;
}

String _guideRowMarketFingerprint(GuideCatalogMatchedRow row) {
  final priceParts = <String>[];
  for (final p in row.prices ?? const <Map<String, dynamic>>[]) {
    final grade = (p['grade'] ?? p['Grade'] ?? p['label'] ?? p['Label'] ?? p['name'] ?? p['Name'])
            ?.toString()
            .trim() ??
        '';
    if (grade.isEmpty) continue;
    final price = parseGuidePriceField(
      p['price'] ?? p['Price'] ?? p['value'] ?? p['Value'] ?? p['avg'] ?? p['Avg'],
    );
    if (price == null || price <= 0) continue;
    priceParts.add('$grade:$price');
  }
  priceParts.sort();
  return '${row.sales7d}|${row.sales30d}|${row.gain}|${priceParts.join(';')}';
}

int _guideRowMarketDetailScore(GuideCatalogMatchedRow row) {
  var score = 0;
  if (row.sales7d != null) score += 12;
  if (row.sales30d != null) score += 12;
  if (row.gain != null) score += 12;
  for (final p in row.prices ?? const <Map<String, dynamic>>[]) {
    final grade = (p['grade'] ?? p['Grade'] ?? p['label'] ?? p['Label'] ?? p['name'] ?? p['Name'])
            ?.toString()
            .trim() ??
        '';
    if (grade.isEmpty) continue;
    final price = parseGuidePriceField(
      p['price'] ?? p['Price'] ?? p['value'] ?? p['Value'] ?? p['avg'] ?? p['Avg'],
    );
    if (price != null && price > 0) score += 18;
  }
  if (row.image != null && row.image!.trim().isNotEmpty) score += 6;
  if ((row.description ?? '').trim().length > 24) score += 4;
  return score;
}

/// Same exact `variant` ties: compare 7d/30d/gain/prices; if equal, stable pick; else richest row.
GuideCatalogMatchedRow pickBestAmongExactGuideCatalogMatches(
  List<GuideCatalogMatchedRow> rows,
) {
  if (rows.isEmpty) {
    throw ArgumentError('pickBestAmongExactGuideCatalogMatches: empty rows');
  }
  if (rows.length == 1) return rows.first;

  final fingerprints = rows.map(_guideRowMarketFingerprint).toList();
  final allSame = fingerprints.every((f) => f == fingerprints.first);

  final sorted = List<GuideCatalogMatchedRow>.from(rows)
    ..sort((a, b) {
      if (allSame) {
        return (a.cardId ?? '').compareTo(b.cardId ?? '');
      }
      final ds = _guideRowMarketDetailScore(b) - _guideRowMarketDetailScore(a);
      if (ds != 0) return ds;
      return (a.cardId ?? '').compareTo(b.cardId ?? '');
    });
  return sorted.first;
}

/// Picks the best Base row when CardHedge returns multiple "base bucket" matches.
GuideCatalogMatchedRow pickBestGuideCatalogMatchForBase(
  List<GuideCatalogMatchedRow> rows, {
  String? setName,
}) {
  if (rows.isEmpty) {
    throw ArgumentError('pickBestGuideCatalogMatchForBase: empty rows');
  }
  final ranked = List<GuideCatalogMatchedRow>.from(rows)
    ..sort((a, b) {
      final ds = _baseVariantPickScore(b, setName: setName) - _baseVariantPickScore(a, setName: setName);
      if (ds != 0) return ds;
      return (a.cardId ?? '').compareTo(b.cardId ?? '');
    });
  final topScore = _baseVariantPickScore(ranked.first, setName: setName);
  final topTier = ranked
      .where((r) => _baseVariantPickScore(r, setName: setName) == topScore)
      .toList();
  if (topTier.length <= 1) return ranked.first;

  final winnerVariant = normGuideParallelLabel(topTier.first.variant ?? '');
  final sameVariant = topTier
      .where((r) => normGuideParallelLabel(r.variant ?? '') == winnerVariant)
      .toList();
  return pickBestAmongExactGuideCatalogMatches(
    sameVariant.isNotEmpty ? sameVariant : topTier,
  );
}

/// Hide the picker — non-Base uses exact `variant` match on the edge (no fuzzy);
/// Base auto-picks server-side. Only show if legacy payloads still send mixed variants.
bool shouldShowGuideParallelPicker({
  required String catalogParallelName,
  required List<GuideCatalogMatchedRow> rows,
}) {
  if (rows.length <= 1) return false;
  if (guideCatalogParallelImpliesBase(catalogParallelName)) return false;

  final expected = normGuideParallelLabel(catalogParallelName);
  final variants = <String>{
    for (final r in rows)
      normGuideParallelLabel(r.variant ?? r.description ?? ''),
  };
  if (variants.length == 1 && variants.first == expected) return false;
  if (variants.length == 1) return false;
  return true;
}

/// Builds a single natural-language line for upstream `match_card`, aligned
/// with the sold-comps eBay query shape in `comps_master_refresh.ts`
/// (`buildCardEbayQuery`).
String buildGuideCatalogMatchQuery({
  required int? year,
  required String? releaseName,
  required String? setName,
  required String player,
  required String? cardNumber,
  required String parallelName,
  required bool isAuto,
  required bool isPatch,
  required bool isRookie,
  required int? serialMax,
}) {
  final parts = <String>[
    if (year != null) '$year',
    if (releaseName != null && releaseName.trim().isNotEmpty) releaseName.trim(),
  ];

  final setLabel = (setName ?? '').trim();
  final setLower = setLabel.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final releaseLower = (releaseName ?? '').toLowerCase();
  // Match edge set-label rules: "Base Set" is our DB checklist label, not an upstream product token.
  final isCanonicalBaseSet =
      setLower.isEmpty || setLower == 'base' || setLower == 'base set';
  if (setLabel.isNotEmpty &&
      !isCanonicalBaseSet &&
      !releaseLower.contains(setLabel.toLowerCase())) {
    parts.add(setLabel);
  }

  parts.add(player.trim());
  final num = (cardNumber ?? '').trim();
  if (num.isNotEmpty) {
    parts.add('#$num');
  }

  final attrs = <String>[];
  final parallelLabel = stripCatalogParallelSerialSuffix(parallelName);
  if (parallelLabel.isNotEmpty && parallelLabel.toLowerCase() != 'base') {
    attrs.add(parallelLabel);
  }
  if (isAuto) attrs.add('Auto');
  if (isPatch) attrs.add('Patch');
  if (serialMax != null && serialMax > 0) attrs.add('/$serialMax');
  if (isRookie) attrs.add('RC');

  final joined = [...parts, ...attrs].where((s) => s.isNotEmpty).join(' ');
  if (parallelLabel.isNotEmpty && parallelLabel.toLowerCase() != 'base') {
    // Anchor the LLM on the exact parallel; upstream can still return Base
    // with high confidence if this is buried earlier in the string.
    return '$joined | parallel: $parallelLabel (not base)';
  }
  return joined;
}

/// Top-movers categories are title case (e.g. `Basketball`). Best-effort from
/// our [sport] release field.
String? guideTopMoverCategoryFromSport(String? sport) {
  final s = sport?.trim();
  if (s == null || s.isEmpty) return null;
  return s
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
}

/// `category` values we keep for Portfolio Movers (matches catalog sports).
/// Top-movers only accepts one `category` query string, not an array — we request
/// uncategorized then drop rows outside this set in one round-trip.
const Set<String> guideTopMoverCategoryAllowlist = {
  'Baseball',
  'Basketball',
  'Football',
  'Soccer',
  'Hockey',
};

/// Returns canonical category label if [category] is in [guideTopMoverCategoryAllowlist].
String? canonicalTopMoverCategory(String? category) {
  final c = category?.trim().toLowerCase() ?? '';
  if (c.isEmpty) return null;
  for (final a in guideTopMoverCategoryAllowlist) {
    if (a.toLowerCase() == c) return a;
  }
  return null;
}

/// Maps Portfolio Movers sport chips to top-movers `category`.
String? sportChipToTopMoverCategory(String? uiSport) {
  switch (uiSport) {
    case 'NBA':
      return 'Basketball';
    case 'NFL':
      return 'Football';
    case 'MLB':
      return 'Baseball';
    case 'NHL':
      return 'Hockey';
    case 'Soccer':
      return 'Soccer';
    default:
      return null;
  }
}
