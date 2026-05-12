/// CardHedge grade labels aligned with sold-comps pills and `current_prices.grade`.
const List<String> kCardHedgeDisplayGrades = ['Raw', 'PSA 10', 'PSA 9'];

Map<String, double?> emptyCardHedgeGradePriceMap() => {
      for (final k in kCardHedgeDisplayGrades) k: null,
    };

/// Maps API / DB grade strings onto [kCardHedgeDisplayGrades]; returns null if unknown.
String? normalizeCardHedgeDisplayGrade(String grade) {
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
  if (kCardHedgeDisplayGrades.contains(g)) return g;
  return null;
}

double? parseCardHedgePriceField(dynamic raw) {
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

/// Picks the CardHedge / `current_prices` row for the user's slab, matching
/// [CompsService._valueForGrade] (Raw vs PSA 9 vs PSA 10 buckets).
double? displayPriceForUserCopyFromGradeMap({
  required bool isGraded,
  required String? gradeValueRaw,
  required Map<String, double?> gradeToPrice,
}) {
  double? pick(String k) {
    final v = gradeToPrice[k];
    return (v != null && v > 0) ? v : null;
  }

  final raw = pick('Raw');
  final psa9 = pick('PSA 9');
  final psa10 = pick('PSA 10');
  if (!isGraded) return raw;
  final gv = gradeValueRaw?.trim();
  if (gv == null || gv.isEmpty) return raw;
  if (gv == '10' || gv == '10.0') return psa10 ?? raw;
  if (gv == '9' || gv == '9.0') return psa9 ?? raw;
  return raw;
}

/// Parses nested PostgREST `current_prices` rows into [kCardHedgeDisplayGrades] keys.
Map<String, double?> parseEmbeddedCurrentPrices(List<dynamic>? rows) {
  final out = emptyCardHedgeGradePriceMap();
  if (rows == null) return out;
  for (final row in rows) {
    if (row is! Map) continue;
    final m = Map<String, dynamic>.from(row);
    final key = normalizeCardHedgeDisplayGrade(m['grade']?.toString() ?? '');
    if (key == null) continue;
    final p = parsePostgresNumeric(m['price']);
    if (p == null || p <= 0) continue;
    out[key] = p;
  }
  return out;
}

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

bool cardHedgeGradeMapHasAnyPrice(Map<String, double?> m) =>
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

  final map = parseEmbeddedCurrentPrices(rows);
  final mapped = displayPriceForUserCopyFromGradeMap(
    isGraded: isGraded,
    gradeValueRaw: gradeValueRaw,
    gradeToPrice: map,
  );
  if (mapped != null && mapped > 0) return mapped;

  // Single-row feeds sometimes use a nonstandard label (e.g. "NM-MT") for raw market.
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
