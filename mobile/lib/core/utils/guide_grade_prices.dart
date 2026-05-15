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
