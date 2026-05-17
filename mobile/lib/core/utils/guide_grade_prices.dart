import 'package:flutter/cupertino.dart' show CupertinoIcons, IconData;

/// Preferred ordering when multiple `current_prices.grade` labels exist (not a fixed display set).
const List<String> kPreferredGuidePriceGradeOrder = ['Raw', 'PSA 10', 'PSA 9'];

/// Extra grades offered in the sold-comps picker (beyond recent-price slots).
const List<String> kCommonGuideCompsGradeOptions = [
  'Raw',
  'PSA 10',
  'PSA 9',
  'PSA 8',
  'PSA 7',
  'BGS 10',
  'BGS 9.5',
  'BGS 9',
  'SGC 10',
  'CGC 10',
];

Map<String, double?> emptyGuideGradePriceMap() => {};

/// Maps common API / DB aliases onto canonical labels for sorting and slab matching.
String? normalizeGuideDisplayGrade(String grade) {
  final g = grade.trim();
  if (g.isEmpty) return null;
  final lower = g.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (lower == 'raw' ||
      lower == 'ungraded' ||
      lower == 'nm' ||
      lower == 'near mint' ||
      lower == 'nm-mt' ||
      lower == 'nm/mt' ||
      lower == 'mint') {
    return 'Raw';
  }
  if (lower == 'psa 10' || lower == 'psa10') return 'PSA 10';
  if (lower == 'psa 9' || lower == 'psa9') return 'PSA 9';
  return g;
}

/// Whether [map] already has a row for the canonical slot [Raw] / [PSA 10] / [PSA 9].
bool canonicalGuidePriceSlotFilled(Map<String, double?> map, String canonical) {
  for (final key in map.keys) {
    final n = normalizeGuideDisplayGrade(key);
    if (n == canonical) return true;
    if (currentPricesGradeLooselyEqual(key, canonical)) return true;
  }
  return false;
}

int _guidePriceDisplaySortBucket(String grade) {
  final canonical = normalizeGuideDisplayGrade(grade);
  if (canonical == 'Raw') return 0;
  if (canonical == 'PSA 10') return 1;
  if (canonical == 'PSA 9') return 2;

  final lower = grade.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (lower.contains('raw') ||
      lower.contains('ungraded') ||
      lower == 'nm' ||
      lower.contains('near mint')) {
    return 0;
  }
  if (RegExp(r'(^|[^\d])10([^\d]|$)').hasMatch(lower)) return 1;
  if (RegExp(r'(^|[^\d])9([^\d]|$)').hasMatch(lower)) return 2;
  return 3;
}

int compareGuidePriceGradeLabels(String a, String b) {
  final ba = _guidePriceDisplaySortBucket(a);
  final bb = _guidePriceDisplaySortBucket(b);
  if (ba != bb) return ba.compareTo(bb);
  return a.compareTo(b);
}

/// Merges recent-price labels, cached comps grades, and [kCommonGuideCompsGradeOptions].
List<String> mergeGuideCompsGradeOptions({
  Map<String, double?>? recentPrices,
  Iterable<String> cachedCompsGrades = const [],
}) {
  final out = <String>[];
  void add(String raw) {
    final g = raw.trim();
    if (g.isEmpty) return;
    for (final existing in out) {
      if (currentPricesGradeLooselyEqual(existing, g)) return;
    }
    out.add(g);
  }

  for (final slot in guideRecentPriceDisplaySlots(recentPrices ?? const {})) {
    add(slot.key);
  }
  for (final g in cachedCompsGrades) {
    add(g);
  }
  for (final g in kCommonGuideCompsGradeOptions) {
    add(g);
  }
  out.sort(compareGuidePriceGradeLabels);
  return out;
}

/// When fewer than three priced rows exist, adds null placeholders for missing
/// [Raw] / [PSA 10] / [PSA 9] slots so the market UI always shows three boxes.
Map<String, double?> withCanonicalGuidePricePlaceholders(Map<String, double?> parsed) {
  final pricedCount =
      parsed.entries.where((e) => e.value != null && e.value! > 0).length;
  if (pricedCount >= 3) return parsed;

  final out = Map<String, double?>.from(parsed);
  final placeholdersNeeded = 3 - pricedCount;
  var added = 0;
  for (final canonical in kPreferredGuidePriceGradeOrder) {
    if (added >= placeholdersNeeded) break;
    if (!canonicalGuidePriceSlotFilled(out, canonical)) {
      out.putIfAbsent(canonical, () => null);
      added++;
    }
  }
  return out;
}

/// Entries for display (includes N/A placeholders), sorted Raw → 10s → 9s → other.
List<MapEntry<String, double?>> orderedGuidePriceEntries(Map<String, double?> prices) {
  final padded = withCanonicalGuidePricePlaceholders(prices);
  final entries = padded.entries.toList();
  entries.sort((a, b) => compareGuidePriceGradeLabels(a.key, b.key));
  return entries;
}

/// Exactly three slots for the Recent Prices row (pads or trims after sort).
List<MapEntry<String, double?>> guideRecentPriceDisplaySlots(Map<String, double?> prices) {
  final ordered = orderedGuidePriceEntries(prices);
  if (ordered.length >= 3) return ordered.take(3).toList();

  final slots = List<MapEntry<String, double?>>.from(ordered);
  for (final canonical in kPreferredGuidePriceGradeOrder) {
    if (slots.length >= 3) break;
    final filled = slots.any(
      (e) => canonicalGuidePriceSlotFilled({e.key: e.value}, canonical),
    );
    if (!filled) slots.add(MapEntry(canonical, null));
  }
  return slots.take(3).toList();
}

/// Priced rows only — for comps grade picker and similar.
List<MapEntry<String, double>> orderedGuidePriceEntriesWithValues(Map<String, double?> prices) {
  final out = <MapEntry<String, double>>[];
  for (final e in orderedGuidePriceEntries(prices)) {
    final p = e.value;
    if (p == null || p <= 0) continue;
    out.add(MapEntry(e.key, p));
  }
  return out;
}

double? parseGuidePriceField(dynamic raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();
  if (raw is! String) return null;
  final cleaned = raw.replaceAll(RegExp(r'[^0-9.-]'), '');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

/// PostgREST / JSON often returns `numeric` as a string — never cast with `as num` only.
double? parsePostgresNumeric(dynamic raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();
  if (raw is String) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }
  return null;
}

/// Preserves upstream / DB grade labels from `current_prices` rows (no fixed Raw/PSA bucket collapse).
Map<String, double?> parseCurrentPricesRowsToMap(List<dynamic>? rows) {
  final out = <String, double?>{};
  if (rows == null) return out;
  for (final row in rows) {
    if (row is! Map) continue;
    final m = Map<String, dynamic>.from(row);
    final label = m['grade']?.toString().trim() ?? '';
    if (label.isEmpty) continue;
    final p = parsePostgresNumeric(m['price']);
    if (p == null || p <= 0) continue;

    String? existingKey;
    for (final k in out.keys) {
      if (currentPricesGradeLooselyEqual(k, label)) {
        existingKey = k;
        break;
      }
    }
    final key = existingKey ?? label;
    out[key] = p;
  }
  return withCanonicalGuidePricePlaceholders(out);
}

/// Parses nested PostgREST `current_prices` rows using each row's [grade] label.
Map<String, double?> parseEmbeddedCurrentPrices(List<dynamic>? rows) =>
    parseCurrentPricesRowsToMap(rows);

DateTime? maxFetchedAtFromCurrentPriceRows(List<dynamic>? rows) {
  if (rows == null) return null;
  DateTime? maxFt;
  for (final row in rows) {
    if (row is! Map) continue;
    final raw = row['fetched_at'];
    if (raw == null) continue;
    final t = DateTime.tryParse(raw.toString());
    if (t == null) continue;
    if (maxFt == null || t.isAfter(maxFt)) maxFt = t;
  }
  return maxFt;
}

/// Aligns with scheduled `auto-refresh-cards` staleness (23h cron window); UI uses 24h.
const Duration kGuideCurrentPricesStaleAfter = Duration(hours: 24);

/// True when there are no price rows or the newest `current_prices.fetched_at` is older than [kGuideCurrentPricesStaleAfter].
bool guideCurrentPricesAreStale(DateTime? newestFetchedAt, {DateTime? now}) {
  if (newestFetchedAt == null) return true;
  final clock = now ?? DateTime.now();
  return clock.difference(newestFetchedAt) >= kGuideCurrentPricesStaleAfter;
}

bool guideGradeMapHasAnyPrice(Map<String, double?> m) =>
    m.values.any((v) => v != null && v > 0);

/// Value equality for guide price maps (ignores key order).
bool guideGradePriceMapsEqual(
  Map<String, double?>? a,
  Map<String, double?>? b,
) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (!b.containsKey(e.key) || b[e.key] != e.value) return false;
  }
  return true;
}

/// True when [a] and [b] refer to the same slab label (spacing / case insensitive).
bool currentPricesGradeLooselyEqual(String a, String b) {
  final na = a.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final nb = b.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (na == nb) return true;
  final ca = na.replaceAll(RegExp(r'[\s-]'), '');
  final cb = nb.replaceAll(RegExp(r'[\s-]'), '');
  return ca == cb;
}

double? _priceFromGradeMapLoose(Map<String, double?> gradeToPrice, String target) {
  for (final e in gradeToPrice.entries) {
    final v = e.value;
    if (v == null || v <= 0) continue;
    if (currentPricesGradeLooselyEqual(e.key, target)) return v;
  }
  return null;
}

/// Picks the guide / `current_prices` row for the user's slab when labels are variable.
double? displayPriceForUserCopyFromGradeMap({
  required bool isGraded,
  required String? grader,
  required String? gradeValueRaw,
  required Map<String, double?> gradeToPrice,
}) {
  if (gradeToPrice.isEmpty) return null;

  final raw = _priceFromGradeMapLoose(gradeToPrice, 'Raw');
  if (!isGraded) return raw ?? gradeToPrice.values.firstWhere((v) => v != null && v > 0, orElse: () => null);

  final gv = gradeValueRaw?.trim();
  if (gv == null || gv.isEmpty) return raw;

  for (final c in currentPricesGradeLookupCandidates(
    isGraded: true,
    grader: grader,
    gradeValueRaw: gv,
  )) {
    final hit = _priceFromGradeMapLoose(gradeToPrice, c);
    if (hit != null) return hit;
  }

  return raw;
}

/// Labels to try against [current_prices.grade] for this user copy (order matters).
List<String> currentPricesGradeLookupCandidates({
  required bool isGraded,
  required String? grader,
  required String? gradeValueRaw,
}) {
  if (!isGraded) {
    return const ['Raw', 'raw', 'Ungraded', 'ungraded', 'UNGRADED'];
  }
  final gv = gradeValueRaw?.trim() ?? '';
  final gr = grader?.trim() ?? '';
  final out = <String>[];
  void add(String s) {
    final t = s.trim();
    if (t.isEmpty) return;
    if (!out.contains(t)) out.add(t);
  }

  String? normNum;
  if (gv.isNotEmpty) {
    normNum = gv.replaceAll(RegExp(r'\.0+$'), '');
    if (normNum.isEmpty) normNum = gv;
  }

  if (gr.isNotEmpty && gv.isNotEmpty) {
    add('$gr $gv');
    if (normNum != null && normNum != gv) add('$gr $normNum');
    add('$gr$gv');
    if (normNum != null && normNum != gv) add('$gr$normNum');
  }

  if (normNum != null) {
    if (normNum == '10') {
      add('PSA 10');
      add('PSA10');
      add('10');
    } else if (normNum == '9') {
      add('PSA 9');
      add('PSA9');
      add('9');
    }
  }
  add(gv);
  return out;
}

/// Single price for the user's copy: row in [current_prices] whose [grade] matches
/// this slab (`user_cards.is_graded`, `grader`, `grade_value`), else bucket fallback.
double? priceFromCurrentPricesRowsForUserCopy(
  List<dynamic>? rows, {
  required bool isGraded,
  required String? grader,
  required String? gradeValueRaw,
}) {
  if (rows == null || rows.isEmpty) return null;

  final candidates = currentPricesGradeLookupCandidates(
    isGraded: isGraded,
    grader: grader,
    gradeValueRaw: gradeValueRaw,
  );

  for (final row in rows) {
    if (row is! Map) continue;
    final m = Map<String, dynamic>.from(row);
    final g = m['grade']?.toString().trim();
    final p = parsePostgresNumeric(m['price']);
    if (g == null || g.isEmpty || p == null || p <= 0) continue;
    for (final c in candidates) {
      if (currentPricesGradeLooselyEqual(g, c)) return p;
    }
  }

  final map = parseCurrentPricesRowsToMap(rows);
  final mapped = displayPriceForUserCopyFromGradeMap(
    isGraded: isGraded,
    grader: grader,
    gradeValueRaw: gradeValueRaw,
    gradeToPrice: map,
  );
  if (mapped != null && mapped > 0) return mapped;

  if (!isGraded && rows.length == 1) {
    final row = rows.first;
    if (row is Map) {
      final m = Map<String, dynamic>.from(row);
      final p = parsePostgresNumeric(m['price']);
      if (p != null && p > 0) return p;
    }
  }
  return null;
}

// ── Active listings vs CardHedge guide ─────────────────────────────────────

/// Latest guide value for [gradeLabel] from `current_prices`-style map (loose grade match).
double? guideLatestPriceForGradeMap(Map<String, double?>? map, String gradeLabel) {
  if (map == null || map.isEmpty) return null;
  final g = gradeLabel.trim().isEmpty ? 'Raw' : gradeLabel.trim();
  for (final e in map.entries) {
    final v = e.value;
    if (v == null || v <= 0) continue;
    if (currentPricesGradeLooselyEqual(e.key, g)) return v;
  }
  return null;
}

/// Raw vs slab read from an eBay listing title (best-effort; defaults to raw).
class InferredListingCondition {
  const InferredListingCondition({
    required this.isGraded,
    required this.displayTag,
    this.grader,
    this.gradeValueRaw,
  });

  final bool isGraded;
  /// Short chip label, e.g. `Raw`, `PSA 10`, `BGS 9.5`.
  final String displayTag;
  final String? grader;
  final String? gradeValueRaw;
}

final RegExp _psaGradeInTitle = RegExp(
  r'\bPSA\s*(?:GEM\s*MT\s*|GEM\s*MINT\s*)?(\d+(?:\.\d+)?)\b',
  caseSensitive: false,
);
final RegExp _psaTightInTitle = RegExp(r'\bPSA(\d{1,2}(?:\.\d+)?)\b', caseSensitive: false);
final RegExp _bgsGradeInTitle = RegExp(r'\bBGS\s*(\d+(?:\.\d+)?)\b', caseSensitive: false);
final RegExp _beckettGradeInTitle = RegExp(
  r'\bBeckett\s*(?:black\s*label\s*)?(\d+(?:\.\d+)?)\b',
  caseSensitive: false,
);
final RegExp _sgcGradeInTitle = RegExp(r'\bSGC\s*(\d+(?:\.\d+)?)\b', caseSensitive: false);
final RegExp _cgcGradeInTitle = RegExp(r'\bCGC\s*(\d+(?:\.\d+)?)\b', caseSensitive: false);
final RegExp _csgGradeInTitle = RegExp(r'\bCSG\s*(\d+(?:\.\d+)?)\b', caseSensitive: false);
final RegExp _rawWordsInTitle = RegExp(r'\b(raw|ungraded)\b', caseSensitive: false);

/// Heuristic slab / raw detection from marketplace listing titles.
InferredListingCondition inferListingConditionFromTitle(String title) {
  final t = title.trim();
  if (t.isEmpty) {
    return const InferredListingCondition(isGraded: false, displayTag: 'Raw');
  }

  Match? m = _psaGradeInTitle.firstMatch(t);
  if (m != null) {
    final n = m.group(1)!;
    return InferredListingCondition(
      isGraded: true,
      displayTag: 'PSA $n',
      grader: 'PSA',
      gradeValueRaw: n,
    );
  }
  m = _psaTightInTitle.firstMatch(t);
  if (m != null) {
    final n = m.group(1)!;
    return InferredListingCondition(
      isGraded: true,
      displayTag: 'PSA $n',
      grader: 'PSA',
      gradeValueRaw: n,
    );
  }
  m = _bgsGradeInTitle.firstMatch(t);
  if (m != null) {
    final n = m.group(1)!;
    return InferredListingCondition(
      isGraded: true,
      displayTag: 'BGS $n',
      grader: 'BGS',
      gradeValueRaw: n,
    );
  }
  m = _beckettGradeInTitle.firstMatch(t);
  if (m != null) {
    final n = m.group(1)!;
    return InferredListingCondition(
      isGraded: true,
      displayTag: 'BGS $n',
      grader: 'BGS',
      gradeValueRaw: n,
    );
  }
  m = _sgcGradeInTitle.firstMatch(t);
  if (m != null) {
    final n = m.group(1)!;
    return InferredListingCondition(
      isGraded: true,
      displayTag: 'SGC $n',
      grader: 'SGC',
      gradeValueRaw: n,
    );
  }
  m = _cgcGradeInTitle.firstMatch(t);
  if (m != null) {
    final n = m.group(1)!;
    return InferredListingCondition(
      isGraded: true,
      displayTag: 'CGC $n',
      grader: 'CGC',
      gradeValueRaw: n,
    );
  }
  m = _csgGradeInTitle.firstMatch(t);
  if (m != null) {
    final n = m.group(1)!;
    return InferredListingCondition(
      isGraded: true,
      displayTag: 'CSG $n',
      grader: 'CSG',
      gradeValueRaw: n,
    );
  }

  if (_rawWordsInTitle.hasMatch(t)) {
    return const InferredListingCondition(isGraded: false, displayTag: 'Raw');
  }

  return const InferredListingCondition(isGraded: false, displayTag: 'Raw');
}

/// Guide row for [inferred] from a `current_prices` map.
///
/// Graded listings only match their slab row — no silent fallback to Raw (avoids
/// misleading deal tiers when that grade is missing from [gradeToPrice]).
double? guidePriceForInferredListing({
  required Map<String, double?>? gradeToPrice,
  required InferredListingCondition inferred,
}) {
  final map = gradeToPrice;
  if (map == null || map.isEmpty) return null;
  if (!inferred.isGraded) {
    return guideLatestPriceForGradeMap(map, 'Raw');
  }
  final candidates = currentPricesGradeLookupCandidates(
    isGraded: true,
    grader: inferred.grader,
    gradeValueRaw: inferred.gradeValueRaw,
  );
  for (final c in candidates) {
    final hit = _priceFromGradeMapLoose(map, c);
    if (hit != null) return hit;
  }
  return null;
}

/// Five-step deal quality vs CardHedge guide (% over/under asking vs guide).
enum ActiveListingGuideDealTier {
  badDeal,
  okDeal,
  fairDeal,
  goodDeal,
  greatDeal,
}

/// SF Symbol names for adaptive menus; same shapes as [dealTierCupertinoIcon].
String dealTierSfSymbolName(ActiveListingGuideDealTier tier) {
  return switch (tier) {
    ActiveListingGuideDealTier.badDeal => 'arrow.up.circle.fill',
    ActiveListingGuideDealTier.okDeal => 'arrow.up.right.circle.fill',
    ActiveListingGuideDealTier.fairDeal => 'arrow.right.circle.fill',
    ActiveListingGuideDealTier.goodDeal => 'arrow.down.right.circle.fill',
    ActiveListingGuideDealTier.greatDeal => 'arrow.down.circle.fill',
  };
}

/// Cupertino / SF-style icons for listing rows and filter UI.
IconData dealTierCupertinoIcon(ActiveListingGuideDealTier tier) {
  return switch (tier) {
    ActiveListingGuideDealTier.badDeal => CupertinoIcons.arrow_up_circle_fill,
    ActiveListingGuideDealTier.okDeal => CupertinoIcons.arrow_up_right_circle_fill,
    ActiveListingGuideDealTier.fairDeal => CupertinoIcons.arrow_right_circle_fill,
    ActiveListingGuideDealTier.goodDeal => CupertinoIcons.arrow_down_right_circle_fill,
    ActiveListingGuideDealTier.greatDeal => CupertinoIcons.arrow_down_circle_fill,
  };
}

class ActiveListingVsGuideDelta {
  const ActiveListingVsGuideDelta({
    required this.label,
    required this.tier,
  });

  final String label;
  final ActiveListingGuideDealTier tier;
}

/// [pct] = percent over guide: `(listing / guide - 1) * 100`.
///
/// Five contiguous bands (buyer view; lower [pct] = better):
/// - **Great Deal**: pct ≤ -25%
/// - **Good Deal**: -25% < pct < -5% (includes ≤ -15%)
/// - **Fair Deal**: -5% ≤ pct ≤ +5%
/// - **Ok Deal**: +5% < pct < +25% (includes ≥ +15%)
/// - **Bad Deal**: pct ≥ +25%
ActiveListingVsGuideDelta? computeActiveListingGuideDeal({
  required double listingPrice,
  required double guidePrice,
}) {
  if (listingPrice <= 0 || guidePrice <= 0) return null;
  final pct = ((listingPrice / guidePrice) - 1) * 100;

  if (pct <= -25) {
    return const ActiveListingVsGuideDelta(
      label: 'Great Deal',
      tier: ActiveListingGuideDealTier.greatDeal,
    );
  }
  if (pct < -5) {
    return const ActiveListingVsGuideDelta(
      label: 'Good Deal',
      tier: ActiveListingGuideDealTier.goodDeal,
    );
  }
  if (pct <= 5) {
    return const ActiveListingVsGuideDelta(
      label: 'Fair Deal',
      tier: ActiveListingGuideDealTier.fairDeal,
    );
  }
  if (pct < 25) {
    return const ActiveListingVsGuideDelta(
      label: 'Ok Deal',
      tier: ActiveListingGuideDealTier.okDeal,
    );
  }
  return const ActiveListingVsGuideDelta(
    label: 'Bad Deal',
    tier: ActiveListingGuideDealTier.badDeal,
  );
}
